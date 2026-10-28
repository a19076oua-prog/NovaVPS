#!/usr/bin/env python3
"""NovaVPS-owned 3x-ui instance. Invoked only through an authenticated SSH stdin."""
import base64
import contextlib
import hashlib
import ipaddress
import json
import os
import pathlib
import platform
import re
import secrets
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request
import uuid

VERSION = "v3.11.0"
RELEASES = {
    "x86_64": ("amd64", "0ddfa4702f595442e2962acd81addc768fdacaa4ff2672c971a0463dae744916"),
    "aarch64": ("arm64", "f50b4c30fd919d018f2f4c3d8db53a4ca027503d581328727770afb116a79d90"),
    "arm64": ("arm64", "f50b4c30fd919d018f2f4c3d8db53a4ca027503d581328727770afb116a79d90"),
}
MAX_RESPONSE = 512 * 1024


class Failure(Exception):
    pass


def validate_request(request):
    ipaddress.ip_address(request["host"])
    if type(request.get("nodePort")) is not int or not 1 <= request["nodePort"] <= 65535:
        raise Failure("节点端口无效。")
    host = request.get("serverName", "")
    if not isinstance(host, str) or len(host) > 253 or ".." in host or not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", host) or "." not in host:
        raise Failure("Reality 目标域名无效。")
    if type(request.get("autoTarget")) is not bool:
        raise Failure("自动目标参数无效。")
    return request


def private_json(path, value):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_name(path.name + "." + secrets.token_hex(8))
    try:
        with temporary.open("x", encoding="utf-8") as stream:
            os.chmod(temporary, 0o600)
            json.dump(value, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def safe_extract(archive, destination):
    with tarfile.open(archive, "r:gz") as bundle:
        members = bundle.getmembers()
        if len(members) > 2000 or sum(m.size for m in members) > 600 * 1024 * 1024:
            raise Failure("后台安装包超出大小限制。")
        for member in members:
            path = pathlib.PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts or not (member.isfile() or member.isdir()):
                raise Failure("后台安装包包含不安全路径或文件类型。")
        bundle.extractall(destination, members=members)


def command(arguments, *, env=None, timeout=60):
    try:
        result = subprocess.run(arguments, env=env, capture_output=True, timeout=timeout, check=False)
    except (subprocess.TimeoutExpired, OSError):
        raise Failure("服务器命令超时或不可用，请检查系统和网络。")
    if result.returncode:
        raise Failure("服务器命令未完成；未确认服务就绪。")
    if len(result.stdout) > MAX_RESPONSE:
        raise Failure("服务器响应过大。")
    return result.stdout.decode("utf-8", errors="replace")


def free_port(port=0, host="127.0.0.1"):
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind((host, port))
            return probe.getsockname()[1]
    except OSError:
        if port:
            raise Failure("节点 TCP 端口 %d 已被其他服务占用。可先单独安装网页后台；生成新节点时请选择空闲端口，现有服务不会被覆盖。" % port)
        raise Failure("无法分配网页后台的 VPS 本机端口，请检查系统端口资源。")


def target_name(request):
    candidates = [request["serverName"]]
    if request["autoTarget"]:
        candidates += ["dl.google.com", "www.bing.com"]
    for candidate in dict.fromkeys(candidates):
        try:
            context = ssl.create_default_context()
            context.minimum_version = ssl.TLSVersion.TLSv1_3
            context.maximum_version = ssl.TLSVersion.TLSv1_3
            context.set_alpn_protocols(["h2"])
            with socket.create_connection((candidate, 443), timeout=6) as connection:
                with context.wrap_socket(connection, server_hostname=candidate) as secure:
                    if secure.selected_alpn_protocol() == "h2":
                        return candidate
        except (OSError, ssl.SSLError):
            continue
    raise Failure("服务器无法验证 Reality 目标的证书、TLS 1.3 和 h2。请更换目标后重试。")


class API:
    def __init__(self, state):
        self.base = "http://127.0.0.1:%d%s" % (state["panelPort"], state["basePath"])
        self.token = state["apiToken"]
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                raise Failure("后台返回了重定向，未向其他地址发送凭据。")
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())

    def call(self, path, value=None):
        if not path.startswith("panel/api/") or ".." in path:
            raise Failure("后台 API 路径无效。")
        body = json.dumps(value).encode() if value is not None else None
        request = urllib.request.Request(self.base + path, data=body, method="POST" if value is not None else "GET",
                                         headers={"Authorization": "Bearer " + self.token, "Content-Type": "application/json"})
        try:
            with self.opener.open(request, timeout=25) as response:
                data = response.read(MAX_RESPONSE + 1)
            if len(data) > MAX_RESPONSE:
                raise Failure("后台响应过大。")
            result = json.loads(data)
            if result.get("success") is not True:
                raise Failure("后台未接受该操作；请在网页后台核对服务状态。")
            return result.get("obj")
        except (OSError, ValueError, urllib.error.URLError):
            raise Failure("无法访问 VPS 本机后台。请先启动后台；网页端改过监听地址或路径时需恢复原设置。")


class Manager:
    def __init__(self, root=pathlib.Path("/"), owner_uid=0):
        self.root = pathlib.Path(root)
        self.base = self.root / "opt/novavps-panel"
        self.data = self.root / "var/lib/novavps-panel"
        self.logs = self.root / "var/log/novavps-panel"
        self.unit = self.root / "etc/systemd/system/novavps-panel.service"
        self.state_file = self.data / "novavps-state.json"
        self.api_factory = API
        self.owner_uid = owner_uid

    def load(self):
        if not self.state_file.exists():
            if self.base.exists() or self.data.exists() or self.unit.exists() or self.logs.exists():
                raise Failure("发现不完整或非本软件管理的目录，已停止以避免覆盖。")
            return None
        for path in [self.base, self.data, self.unit, self.state_file]:
            if path.is_symlink() or path.stat().st_uid != self.owner_uid:
                raise Failure("后台目录所有权异常，已拒绝执行。")
        if self.state_file.stat().st_size > MAX_RESPONSE:
            raise Failure("后台记录超出大小限制。")
        state = json.loads(self.state_file.read_text())
        if state.get("owner") != "novavps-v1" or state.get("version") != VERSION:
            raise Failure("后台版本或归属不匹配，未修改现有服务。")
        if type(state.get("panelPort")) is not int or not 1024 <= state["panelPort"] <= 65535 or not re.fullmatch(r"/[a-f0-9]{32}/", state.get("basePath", "")):
            raise Failure("后台访问参数无效。")
        if not isinstance(state.get("nodes"), dict) or not all(isinstance(state.get(k), str) and 1 <= len(state[k]) <= 512 and not any(ord(c) < 32 for c in state[k]) for k in ["apiToken", "username", "password"]):
            raise Failure("后台凭据记录不完整。")
        if not all(str(k).isdigit() and 1 <= int(k) <= 65535 and isinstance(v, dict) and re.fullmatch(r"NovaVPS-[a-f0-9]{16}", v.get("tag", "")) for k, v in state["nodes"].items()):
            raise Failure("后台节点记录无效。")
        return state

    def save(self, state):
        private_json(self.state_file, state)

    def status(self):
        result = subprocess.run(["systemctl", "is-active", "novavps-panel.service"], capture_output=True, timeout=10)
        state = result.stdout.decode().strip()
        return state if state in ["active", "inactive", "failed", "activating", "deactivating"] else "unknown"

    def install(self, exclude_port=None):
        if self.base.exists() or self.data.exists() or self.unit.exists() or self.logs.exists():
            raise Failure("已有后台文件，不能覆盖安装。")
        if (self.root / "usr/local/x-ui/x-ui").exists():
            raise Failure("VPS 已有独立 3x-ui。当前安装不会覆盖它；请用原后台管理，或选择新 VPS。")
        if platform.machine() not in RELEASES:
            raise Failure("后台安装仅支持 Linux x86_64 和 arm64。")
        try:
            import bcrypt
        except ImportError:
            command(["apt-get", "-o", "DPkg::Lock::Timeout=60", "update"], timeout=180)
            command(["apt-get", "-o", "DPkg::Lock::Timeout=60", "install", "-y", "--no-install-recommends", "python3-bcrypt", "ca-certificates"], timeout=240)
            import bcrypt
        architecture, digest = RELEASES[platform.machine()]
        self.base.parent.mkdir(parents=True, exist_ok=True)
        panel_port = free_port()
        for _ in range(20):
            if panel_port != exclude_port:
                break
            panel_port = free_port()
        if panel_port == exclude_port:
            raise Failure("无法分配与节点分开的后台端口。")
        state = {"owner": "novavps-v1", "version": VERSION, "panelPort": panel_port, "basePath": "/" + secrets.token_hex(16) + "/",
                 "username": "nvps_" + secrets.token_hex(4), "password": secrets.token_urlsafe(24), "nodes": {}}
        created = False
        try:
            with tempfile.TemporaryDirectory(prefix=".novavps-install-", dir=self.base.parent) as directory:
                stage = pathlib.Path(directory)
                archive = stage / "release.tar.gz"
                url = "https://github.com/MHSanaei/3x-ui/releases/download/%s/x-ui-linux-%s.tar.gz" % (VERSION, architecture)
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                with opener.open(url, timeout=45) as response, archive.open("xb") as out:
                    count = 0
                    while True:
                        block = response.read(1024 * 1024)
                        if not block:
                            break
                        count += len(block)
                        if count > 150 * 1024 * 1024:
                            raise Failure("后台下载超出大小限制。")
                        out.write(block)
                sha = hashlib.sha256()
                with archive.open("rb") as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        sha.update(block)
                if sha.hexdigest() != digest:
                    raise Failure("后台安装包 SHA-256 校验失败，未运行下载内容。")
                safe_extract(archive, stage / "unpacked")
                source = stage / "unpacked/x-ui"
                if not (source / "x-ui").is_file() or not (source / "bin").is_dir():
                    raise Failure("后台安装包布局不匹配。")
                os.replace(source, self.base)
                created = True
            self.data.mkdir(mode=0o700, parents=True)
            self.logs.mkdir(mode=0o700, parents=True)
            env = dict(os.environ, XUI_DB_FOLDER=str(self.data), XUI_BIN_FOLDER=str(self.base / "bin"), XUI_LOG_FOLDER=str(self.logs))
            binary = str(self.base / "x-ui")
            command([binary, "setting", "-port", str(state["panelPort"]), "-listenIP", "127.0.0.1", "-webBasePath", state["basePath"]], env=env)
            # Seed only this newly created private DB. Never put passwords in argv or journals.
            with sqlite3.connect(self.data / "x-ui.db") as database:
                if database.execute("SELECT COUNT(*) FROM users").fetchone()[0] != 0:
                    raise Failure("新后台数据库已有用户，已停止初始化。")
                password_hash = bcrypt.hashpw(state["password"].encode(), bcrypt.gensalt()).decode()
                database.execute("INSERT INTO users(username,password) VALUES (?,?)", (state["username"], password_hash))
                for key, value in {"subEnable": "false", "subJsonEnable": "false", "subClashEnable": "false", "subListen": "127.0.0.1"}.items():
                    if database.execute("SELECT COUNT(*) FROM settings WHERE key=?", (key,)).fetchone()[0]:
                        database.execute("UPDATE settings SET value=? WHERE key=?", (value, key))
                    else:
                        database.execute("INSERT INTO settings(key,value) VALUES (?,?)", (key, value))
            output = command([binary, "setting", "-getApiToken", "-tokenName", "novavps", "-tokenScope", "admin"], env=env)
            tokens = re.findall(r"^apiToken:\s*(\S{20,512})\s*$", output, re.M)
            if len(tokens) != 1:
                raise Failure("未取得后台 API 凭据。")
            state["apiToken"] = tokens[0]
            self.save(state)
            self.unit.write_text("""[Unit]
Description=NovaVPS managed 3x-ui
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
WorkingDirectory=%s
ExecStart=%s/x-ui
Environment=XUI_DB_FOLDER=%s
Environment=XUI_BIN_FOLDER=%s/bin
Environment=XUI_LOG_FOLDER=%s
Restart=on-failure
RestartSec=3
KillMode=mixed
UMask=0077
NoNewPrivileges=yes
ProtectSystem=full
ProtectHome=read-only
ProtectKernelModules=yes
ProtectKernelLogs=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
ReadWritePaths=%s %s %s
CapabilityBoundingSet=CAP_DAC_OVERRIDE CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
[Install]
WantedBy=multi-user.target
""" % (self.base, self.base, self.data, self.base, self.logs, self.base, self.data, self.logs))
            os.chmod(self.unit, 0o644)
            command(["systemctl", "daemon-reload"])
            command(["systemctl", "enable", "--now", "novavps-panel.service"])
            self.wait_ready(state)
            return state
        except Exception:
            if created:
                subprocess.run(["systemctl", "disable", "--now", "novavps-panel.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                with contextlib.suppress(OSError):
                    self.unit.unlink()
                shutil.rmtree(self.base, ignore_errors=True)
                shutil.rmtree(self.data, ignore_errors=True)
                shutil.rmtree(self.logs, ignore_errors=True)
                subprocess.run(["systemctl", "daemon-reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            raise

    def wait_ready(self, state):
        for _ in range(30):
            try:
                self.api_factory(state).call("panel/api/server/status")
                return
            except Failure:
                time.sleep(0.5)
        raise Failure("后台启动后未通过本机 API 检查。")

    def provision(self, state, request):
        api = self.api_factory(state)
        inbounds = api.call("panel/api/inbounds/list")
        if not isinstance(inbounds, list):
            raise Failure("后台节点列表格式不正确。")
        key = str(request["nodePort"])
        saved = state["nodes"].get(key)
        if saved:
            matches = [item for item in inbounds if item.get("remark") == saved["tag"]]
            if len(matches) == 1:
                return self.node_from_inbound(matches[0], request)
            if matches:
                raise Failure("后台存在重复托管节点，请在网页后台核对。")
        if any(item.get("port") == request["nodePort"] for item in inbounds):
            raise Failure("该端口已由其他后台入站使用；未覆盖已有节点。")
        free_port(request["nodePort"], "0.0.0.0")
        name = target_name(request)
        pair = api.call("panel/api/server/getNewX25519Cert")
        if not isinstance(pair, dict) or not all(re.fullmatch(r"[A-Za-z0-9_-]{43}", pair.get(k, "")) for k in ["privateKey", "publicKey"]):
            raise Failure("后台没有返回有效的 Reality 密钥。")
        # Persist an idempotency tag before POST. An interrupted POST can be reconciled on retry.
        saved = {"tag": "NovaVPS-" + secrets.token_hex(8)}
        state["nodes"][key] = saved
        self.save(state)
        client_id = str(uuid.uuid4())
        sid = secrets.token_hex(8)
        inbound = {"enable": True, "remark": saved["tag"], "listen": "", "port": request["nodePort"], "protocol": "vless", "expiryTime": 0, "total": 0,
            "settings": {"clients": [{"id": client_id, "email": "nvps-" + secrets.token_hex(5), "enable": True, "flow": "xtls-rprx-vision", "totalGB": 0, "expiryTime": 0, "limitIp": 0}], "decryption": "none", "fallbacks": []},
            "streamSettings": {"network": "tcp", "security": "reality", "tcpSettings": {"header": {"type": "none"}},
                "realitySettings": {"show": False, "xver": 0, "target": name + ":443", "serverNames": [name], "privateKey": pair["privateKey"], "shortIds": [sid],
                                    "settings": {"publicKey": pair["publicKey"], "fingerprint": "chrome", "serverName": name, "spiderX": "/"}}},
            "sniffing": {"enabled": True, "destOverride": ["http", "tls", "quic"], "routeOnly": True}}
        result = api.call("panel/api/inbounds/add", inbound)
        if not isinstance(result, dict) or type(result.get("id")) is not int:
            raise Failure("后台未返回节点 ID；请刷新或重试以核对结果。")
        node = self.node_from_inbound(result, request)
        self.wait_ready(state)
        status = api.call("panel/api/server/status")
        if status.get("xray", {}).get("state") != "running":
            raise Failure("配置已保存，但后台 Xray 未运行。请在网页后台检查。")
        return node

    @staticmethod
    def node_from_inbound(inbound, request):
        def obj(value):
            return json.loads(value) if isinstance(value, str) else value
        try:
            stream = obj(inbound["streamSettings"])
            reality = stream["realitySettings"]
            settings = obj(inbound["settings"])
            client = next(c for c in settings["clients"] if c.get("enable", True) and c.get("flow") == "xtls-rprx-vision")
            if inbound["protocol"] != "vless" or stream["security"] != "reality" or stream["network"] not in ["tcp", "raw"] or inbound["port"] != request["nodePort"]:
                raise ValueError()
            node = {"server": request["host"], "port": inbound["port"], "uuid": client["id"], "publicKey": reality["settings"]["publicKey"], "shortId": reality["shortIds"][0], "serverName": reality["serverNames"][0]}
            uuid.UUID(node["uuid"])
            if not re.fullmatch(r"[A-Za-z0-9_-]{43}", node["publicKey"]) or not re.fullmatch(r"[a-f0-9]{16}", node["shortId"]):
                raise ValueError()
            if not inbound.get("enable", False):
                raise Failure("节点在网页后台已停用，未报告为可用。")
            return node
        except (KeyError, TypeError, ValueError, StopIteration):
            raise Failure("托管节点已在网页后台变更为不支持的格式，请在后台导出对应配置。")

    def run(self, action, request):
        validate_request(request)
        if action not in ["inspect", "install", "provision", "start", "stop", "restart"]:
            raise Failure("不支持的管理动作。")
        state = self.load()
        if not state:
            if action not in ["install", "provision"]:
                return {"installed": False, "state": "not-installed", "node": None, "panel": None}
            if action == "provision":
                free_port(request["nodePort"], "0.0.0.0")
                target_name(request)
            state = self.install(exclude_port=request["nodePort"])
        if action in ["start", "stop", "restart"]:
            command(["systemctl", action, "novavps-panel.service"])
            if action != "stop":
                self.wait_ready(state)
        if action in ["install", "provision"] and self.status() != "active":
            command(["systemctl", "start", "novavps-panel.service"])
            self.wait_ready(state)
        node = self.provision(state, request) if action == "provision" else None
        status = self.status()
        count = None
        if status == "active":
            values = self.api_factory(state).call("panel/api/inbounds/list")
            count = len(values)
            if node is None:
                entry = state["nodes"].get(str(request["nodePort"]), {})
                found = [v for v in values if v.get("remark") == entry.get("tag")]
                if len(found) == 1:
                    node = self.node_from_inbound(found[0], request)
        return {"installed": True, "state": status, "node": node, "inboundCount": count,
                "panel": {"port": state["panelPort"], "basePath": state["basePath"], "username": state["username"], "password": state["password"], "version": VERSION}}


def main():
    os.umask(0o077)
    try:
        if os.geteuid() != 0 or platform.system() != "Linux" or not pathlib.Path("/run/systemd/system").is_dir():
            raise Failure("需要 Debian / Ubuntu、systemd 和 root 或免密码 sudo。")
        release = pathlib.Path("/etc/os-release").read_text()
        if not re.search(r'^ID=(?:"?)(debian|ubuntu)(?:"?)$', release, re.M):
            raise Failure("当前自动安装支持 Debian / Ubuntu。")
        if len(sys.argv) != 3 or len(sys.argv[2]) > 4096:
            raise Failure("管理参数无效。")
        request = json.loads(base64.b64decode(sys.argv[2], validate=True))
        import fcntl
        with open("/run/novavps-panel.lock", "a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise Failure("此 VPS 已有管理操作进行中，请稍后重试。")
            result = Manager().run(sys.argv[1], request)
        output = {"success": True, "result": result}
        print("NOVAVPS_RESULT: " + base64.b64encode(json.dumps(output).encode()).decode())
    except Exception as error:
        # No traceback, command stdout, tokens, passwords or private keys reach the UI.
        message = str(error) if isinstance(error, Failure) else "服务器操作未完成；可刷新状态后重试，现有外部服务未被覆盖。"
        print("NOVAVPS_RESULT: " + base64.b64encode(json.dumps({"success": False, "error": message}).encode()).decode())
        sys.exit(1)


if __name__ == "__main__":
    main()
