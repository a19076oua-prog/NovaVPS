'use strict';
const {isIP}=require('node:net');
const {createHash}=require('node:crypto');
const YAML=require('yaml');
const MAX=2*1024*1024;
const domain=s=>typeof s==='string'&&s.length<=253&&/^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$/.test(s)&&s.includes('.')&&!s.includes('..');
function request(raw,nodeRequired=false){
  const r={host:String(raw?.host||'').trim(),sshPort:Number(raw?.sshPort),username:String(raw?.username||'root'),nodePort:Number(raw?.nodePort),serverName:String(raw?.serverName||'dl.google.com'),autoTarget:raw?.autoTarget!==false,auth:raw?.auth||'password',identityFile:String(raw?.identityFile||'')};
  if(!isIP(r.host))throw Error('请输入有效的 VPS IPv4 或 IPv6 地址。 / Enter a valid VPS IP.');
  if(!Number.isInteger(r.sshPort)||r.sshPort<1||r.sshPort>65535||!Number.isInteger(r.nodePort)||r.nodePort<1||r.nodePort>65535)throw Error('端口须为 1-65535 的整数。 / Invalid port.');
  if(nodeRequired&&r.sshPort===r.nodePort)throw Error('节点端口不能与 SSH 端口相同。 / Node and SSH ports must differ.');
  if(!/^[a-z_][a-z0-9_-]{0,31}$/.test(r.username)||!domain(r.serverName)||!['password','key','agent'].includes(r.auth))throw Error('SSH 用户、认证方式或 Reality 目标无效。 / Invalid connection settings.');
  return r;
}
function fingerprint(key){return 'SHA256:'+createHash('sha256').update(key).digest('base64').replace(/=+$/,'');}
function pin(raw,r){
  if(!raw||raw.host!==r.host||raw.port!==r.sshPort||typeof raw.key!=='string'||raw.key.length>16000||!/^[A-Za-z0-9+/]+={0,2}$/.test(raw.key))throw Error('请先检查并确认 SSH 指纹。 / Verify the SSH fingerprint first.');
  const key=Buffer.from(raw.key,'base64');if(key.length<32||fingerprint(key)!==raw.fingerprint)throw Error('SSH 指纹记录无效。 / Invalid host key record.');return {host:r.host,port:r.sshPort,key:raw.key,fingerprint:raw.fingerprint};
}
function normalizedIP(ip){return isIP(ip)===6?new URL('http://['+ip+']/').hostname:ip;}
function node(n,expected){
  if(!n||!isIP(n.server)||!Number.isInteger(n.port)||n.port<1||n.port>65535||!/^[-a-fA-F0-9]{36}$/.test(n.uuid)||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(n.uuid)||!/^[A-Za-z0-9_-]{43}$/.test(n.publicKey)||Buffer.from(n.publicKey,'base64url').length!==32||!/^[a-f0-9]{16}$/.test(n.shortId)||!domain(n.serverName))throw Error('节点参数无效。 / Invalid node configuration.');
  if(expected&&(normalizedIP(n.server)!==normalizedIP(expected.host)||n.port!==expected.nodePort))throw Error('节点地址与请求不一致。 / Node does not match the requested server.');
  return {server:n.server,port:n.port,uuid:n.uuid,publicKey:n.publicKey,shortId:n.shortId,serverName:n.serverName};
}
function panel(p){
  if(!p||!Number.isInteger(p.port)||p.port<1024||p.port>65535||!/^\/[a-f0-9]{32}\/$/.test(p.basePath)||typeof p.username!=='string'||p.username.length<1||p.username.length>80||/[\s\x00-\x1f]/.test(p.username)||typeof p.password!=='string'||p.password.length<16||p.password.length>256||/[\x00-\x1f]/.test(p.password)||p.version!=='v3.11.0')throw Error('后台返回了无效的访问参数。 / Invalid panel metadata.');return p;
}
function parseResult(output,exitCode,r){
  if(Buffer.byteLength(output)>512*1024)throw Error('后台响应超出大小限制。 / Oversized response.');
  const lines=output.split(/\r?\n/).filter(s=>s.startsWith('NOVAVPS_RESULT: '));
  if(lines.length!==1){if(/Permission denied|authentication/i.test(output))throw Error('SSH 认证失败。 / SSH authentication failed.');throw Error('没有收到完整的后台结果。 / No complete management result received.');}
  let e;try{e=JSON.parse(Buffer.from(lines[0].slice(16),'base64').toString('utf8'));}catch{throw Error('后台结果格式无效。 / Invalid result format.');}
  if(!e.success||exitCode!==0){const m=typeof e.error==='string'&&e.error.length<600&&!/apiToken|privateKey|BEGIN.*KEY/i.test(e.error)?e.error:'后台操作未完成。 / Management action failed.';throw Error(m);}
  const v=e.result;if(!v||typeof v.installed!=='boolean'||!['not-installed','active','inactive','failed','activating','deactivating','unknown'].includes(v.state))throw Error('后台状态无效。 / Invalid panel state.');
  if(v.installed)panel(v.panel);else if(v.state!=='not-installed'||v.node||v.panel)throw Error('后台状态不一致。 / Inconsistent installation state.');
  if(v.node)v.node=node(v.node,r);if(v.inboundCount!=null&&(!Number.isInteger(v.inboundCount)||v.inboundCount<0||v.inboundCount>100000))throw Error('后台节点数量无效。');return v;
}
function nativeJSON(n){n=node(n);return {remarks:'NovaVPS · '+n.server,log:{loglevel:'warning'},inbounds:[{tag:'socks',listen:'127.0.0.1',port:10808,protocol:'socks',settings:{udp:true}},{tag:'http',listen:'127.0.0.1',port:10809,protocol:'http'}],outbounds:[{tag:'proxy',protocol:'vless',settings:{vnext:[{address:n.server,port:n.port,users:[{id:n.uuid,encryption:'none',flow:'xtls-rprx-vision'}]}]},streamSettings:{network:'tcp',security:'reality',realitySettings:{serverName:n.serverName,fingerprint:'chrome',publicKey:n.publicKey,password:n.publicKey,shortId:n.shortId,show:false}}},{tag:'direct',protocol:'freedom'},{tag:'block',protocol:'blackhole'}],routing:{domainStrategy:'AsIs',rules:[{type:'field',ip:['127.0.0.0/8','10.0.0.0/8','172.16.0.0/12','192.168.0.0/16','::1/128','fc00::/7','fe80::/10'],outboundTag:'direct'}]}};}
function clash(n){n=node(n);const name='NovaVPS · '+n.server;return {proxies:[{name,type:'vless',server:n.server,port:n.port,uuid:n.uuid,flow:'xtls-rprx-vision',network:'tcp',udp:true,tls:true,servername:n.serverName,'client-fingerprint':'chrome','skip-cert-verify':false,'reality-opts':{'public-key':n.publicKey,'short-id':n.shortId}}],'proxy-groups':[{name:'PROXY',type:'select',proxies:[name]}],rules:['IP-CIDR,127.0.0.0/8,DIRECT,no-resolve','IP-CIDR,10.0.0.0/8,DIRECT,no-resolve','IP-CIDR,172.16.0.0/12,DIRECT,no-resolve','IP-CIDR,192.168.0.0/16,DIRECT,no-resolve','MATCH,PROXY']};}
function share(n){n=node(n);const u=new URL('vless://'+n.uuid+'@'+(isIP(n.server)===6?'['+n.server+']':n.server)+':'+n.port);for(const[k,v]of Object.entries({encryption:'none',security:'reality',type:'tcp',flow:'xtls-rprx-vision',sni:n.serverName,fp:'chrome',pbk:n.publicKey,sid:n.shortId}))u.searchParams.set(k,v);u.hash='NovaVPS · '+n.server;return u.toString();}
function importNode(text){
  if(typeof text!=='string'||Buffer.byteLength(text)>MAX)throw Error('配置过大或无效。 / Invalid or oversized configuration.');let n;
  if(text.trim().startsWith('vless://')){const u=new URL(text.trim());const q=u.searchParams;const allowed=['encryption','security','type','flow','sni','fp','pbk','sid','spx'];if([...q.keys()].some(k=>!allowed.includes(k)||q.getAll(k).length!==1)||q.get('security')!=='reality'||q.get('flow')!=='xtls-rprx-vision'||(q.get('type')||'tcp')!=='tcp'||(q.get('fp')||'chrome')!=='chrome'||(q.get('encryption')||'none')!=='none'||(q.get('spx')||'/')!=='/'||u.password||u.pathname)throw Error('只支持单个 TCP VLESS / Reality / Vision 节点。 / Unsupported node options.');n={server:u.hostname.replace(/^\[|\]$/g,''),port:Number(u.port),uuid:decodeURIComponent(u.username),serverName:q.get('sni'),publicKey:q.get('pbk'),shortId:q.get('sid')};}
  else {let d;try{d=YAML.parse(text,{maxAliasCount:50,uniqueKeys:true});}catch{throw Error('无法解析 JSON / YAML。 / Invalid JSON or YAML.');}
    if(d?.outbounds){const out=d.outbounds.filter(o=>o.protocol?.toLowerCase()==='vless');const o=out[0],v=o?.settings?.vnext,s=v?.[0],users=s?.users,c=users?.[0],st=o?.streamSettings,re=st?.realitySettings,tcp=st?.tcpSettings||st?.rawSettings;if(out.length!==1||v?.length!==1||users?.length!==1||st?.security!=='reality'||!['tcp','raw'].includes(st?.network||'tcp')||c?.flow!=='xtls-rprx-vision'||!['none',undefined].includes(c.encryption)||o.proxySettings||o.mux?.enabled||st.sockopt||(re?.fingerprint||'chrome')!=='chrome'||re?.mldsa65Verify||re?.spiderX&&re.spiderX!=='/'||tcp?.header?.type&&tcp.header.type!=='none')throw Error('节点含不支持的自定义参数。 / Unsupported custom node settings.');n={server:s.address,port:Number(s.port),uuid:c.id,serverName:re?.serverName,publicKey:re?.password||re?.publicKey,shortId:re?.shortId};}
    else {const p=d?.proxies?.[0];if(d?.proxies?.length!==1||p.type!=='vless'||p.flow!=='xtls-rprx-vision'||(p.network||'tcp')!=='tcp'||p.tls!==true||(p['client-fingerprint']||'chrome')!=='chrome'||p['skip-cert-verify']||['dialer-proxy','plugin','packet-encoding','ws-opts','grpc-opts','http-opts'].some(k=>p[k]!==undefined))throw Error('只支持单个 TCP VLESS / Reality / Vision 节点。 / Unsupported node format.');n={server:p.server,port:Number(p.port),uuid:p.uuid,serverName:p.servername,publicKey:p['reality-opts']?.['public-key'],shortId:p['reality-opts']?.['short-id']};}}
  return node(n);
}
module.exports={MAX,request,pin,fingerprint,node,panel,parseResult,nativeJSON,clash,share,importNode,YAML};
