import importlib.util, io, json, os, pathlib, socket, tarfile, tempfile, threading, unittest, hashlib, sqlite3, types, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('manager', pathlib.Path(__file__).resolve().parents[1] / 'Resources/panel-manager.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
REQUEST = dict(host='203.0.113.10', nodePort=18443, serverName='example.com', autoTarget=False)
STATE = dict(owner='novavps-v1', version=m.VERSION, panelPort=18081, basePath='/'+'a'*32+'/', username='fixture', password='fixture-password-long', apiToken='fixture-token-only', nodes={})
class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = pathlib.Path(self.temp.name)
        self.manager = m.Manager(self.root, os.geteuid())
    def tearDown(self): self.temp.cleanup()
    def owned(self):
        self.manager.base.mkdir(parents=True); self.manager.unit.parent.mkdir(parents=True); self.manager.unit.touch()
        self.manager.save(json.loads(json.dumps(STATE)))
    def test_request_validation(self):
        self.assertEqual(m.validate_request(dict(REQUEST)), REQUEST)
        for key, value in [('host','--bad'),('nodePort',True),('nodePort',0),('serverName','a;id.com'),('autoTarget',1)]:
            with self.subTest(key=key), self.assertRaises((m.Failure,ValueError)): m.validate_request(dict(REQUEST, **{key:value}))
    def test_no_owned_installation(self): self.assertIsNone(self.manager.load())
    def test_partial_install_refused(self):
        self.manager.base.mkdir(parents=True)
        with self.assertRaises(m.Failure): self.manager.load()
    def test_private_state_round_trip(self):
        self.owned(); self.assertEqual(self.manager.load(),STATE)
        self.assertEqual(self.manager.state_file.stat().st_mode & 0o777,0o600)
        self.assertEqual(self.manager.data.stat().st_mode & 0o777,0o700)
    def test_bad_state_refused(self):
        self.owned()
        for changed in [dict(STATE,owner='other'),dict(STATE,panelPort=80),dict(STATE,basePath='/public/'),dict(STATE,nodes={'443':{'tag':'foreign'}}),dict(STATE,apiToken='bad\nvalue')]:
            self.manager.save(changed)
            with self.assertRaises(m.Failure): self.manager.load()
    def test_symlink_refused(self):
        self.owned(); original=self.root/'original.json'; self.manager.state_file.rename(original); self.manager.state_file.symlink_to(original)
        with self.assertRaises(m.Failure): self.manager.load()
    def test_existing_official_panel_refused(self):
        path=self.root/'usr/local/x-ui/x-ui'; path.parent.mkdir(parents=True); path.touch()
        with self.assertRaises(m.Failure): self.manager.install()
        self.assertTrue(path.exists()); self.assertFalse(self.manager.base.exists())
    def test_port_conflict(self):
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1',0)); port=occupied.getsockname()[1]
            with self.assertRaises(m.Failure): m.free_port(port)
    def archive(self,name,kind=tarfile.REGTYPE):
        file=self.root/'test.tar.gz'
        with tarfile.open(file,'w:gz') as bundle:
            item=tarfile.TarInfo(name); item.type=kind
            if kind==tarfile.REGTYPE: item.size=2; bundle.addfile(item,io.BytesIO(b'ok'))
            else: item.linkname='/tmp/foreign'; bundle.addfile(item)
        return file
    def test_archive_paths_and_types(self):
        for name,kind in [('../foreign',tarfile.REGTYPE),('/foreign',tarfile.REGTYPE),('link',tarfile.SYMTYPE),('hard',tarfile.LNKTYPE)]:
            with self.subTest(name=name),self.assertRaises(m.Failure): m.safe_extract(self.archive(name,kind),self.root/'extract')
        m.safe_extract(self.archive('x-ui/file'),self.root/'extract'); self.assertEqual((self.root/'extract/x-ui/file').read_text(),'ok')
    def fake_api(self):
        owner=self
        class API:
            def __init__(self,state): pass
            def call(self,path,value=None):
                if path.endswith('inbounds/list'): return owner.inbounds
                if path.endswith('getNewX25519Cert'): return dict(privateKey='A'*43, publicKey='B'*43)
                if path.endswith('inbounds/add'):
                    owner.adds+=1; value=dict(value,id=1); owner.inbounds.append(value)
                    if owner.interrupt: owner.interrupt=False; raise m.Failure('fixture interrupted after commit')
                    return value
                if path.endswith('server/status'): return {'xray':{'state':'running'}}
                raise AssertionError(path)
        self.inbounds=[]; self.adds=0; self.interrupt=False; self.manager.api_factory=API
    def test_idempotent_provision(self):
        self.owned(); self.fake_api(); state=self.manager.load()
        with patch.object(m,'free_port',return_value=18443),patch.object(m,'target_name',return_value='example.com'):
            first=self.manager.provision(state,REQUEST); second=self.manager.provision(self.manager.load(),REQUEST)
        self.assertEqual(first,second); self.assertEqual(self.adds,1); self.assertNotIn('privateKey',json.dumps(first))
    def test_retry_after_committed_response_lost(self):
        self.owned(); self.fake_api(); self.interrupt=True
        with patch.object(m,'free_port',return_value=18443),patch.object(m,'target_name',return_value='example.com'):
            with self.assertRaises(m.Failure): self.manager.provision(self.manager.load(),REQUEST)
            self.assertEqual(self.manager.provision(self.manager.load(),REQUEST)['port'],18443)
        self.assertEqual(self.adds,1)
    def test_foreign_inbound_not_overwritten(self):
        self.owned(); self.fake_api(); self.inbounds=[dict(port=18443,remark='foreign')]
        with self.assertRaises(m.Failure): self.manager.provision(self.manager.load(),REQUEST)
        self.assertEqual(self.adds,0)
    def test_disabled_node_rejected(self):
        self.owned(); self.fake_api()
        with patch.object(m,'free_port',return_value=18443),patch.object(m,'target_name',return_value='example.com'):
            self.manager.provision(self.manager.load(),REQUEST)
        self.inbounds[0]['enable']=False
        with self.assertRaises(m.Failure): self.manager.node_from_inbound(self.inbounds[0],REQUEST)
    def test_missing_install_inspection_is_read_only(self):
        result=self.manager.run('inspect',REQUEST)
        self.assertFalse(result['installed']); self.assertFalse(self.manager.base.exists())
    def test_unknown_action_refused(self):
        with self.assertRaises(m.Failure): self.manager.run('shell',REQUEST)
    def test_backend_install_ignores_occupied_node_port(self):
        self.fake_api()
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1',0)); request=dict(REQUEST,nodePort=occupied.getsockname()[1])
            with patch.object(self.manager,'install',return_value=dict(STATE)) as install, patch.object(self.manager,'status',return_value='active'), patch.object(m,'free_port') as probe, patch.object(m,'target_name') as target:
                result=self.manager.run('install',request)
                install.assert_called_once_with(exclude_port=request['nodePort']); probe.assert_not_called(); target.assert_not_called()
        self.assertTrue(result['installed']); self.assertIsNone(result['node']); self.assertEqual(self.adds,0)
    def test_new_node_still_protects_occupied_port(self):
        with socket.socket() as occupied:
            occupied.bind(('127.0.0.1',0)); request=dict(REQUEST,nodePort=occupied.getsockname()[1])
            with patch.object(self.manager,'install') as install:
                with self.assertRaises(m.Failure) as error: self.manager.run('provision',request)
                self.assertIn(str(request['nodePort']),str(error.exception)); install.assert_not_called()
class InstallationTests(unittest.TestCase):
    setUp=ManagerTests.setUp
    tearDown=ManagerTests.tearDown
    # Fake only the downloaded executable and systemctl; exercise actual extraction,
    # SQLite seeding, state writes, service unit creation and rollback in a temp root.
    def prepare_install(self):
        archive=self.root/'release.tar.gz'
        with tarfile.open(archive,'w:gz') as bundle:
            for name,kind in [('x-ui',tarfile.DIRTYPE),('x-ui/bin',tarfile.DIRTYPE),('x-ui/x-ui',tarfile.REGTYPE)]:
                item=tarfile.TarInfo(name); item.type=kind; item.mode=0o755
                if kind==tarfile.REGTYPE: item.size=7; bundle.addfile(item,io.BytesIO(b'fixture'))
                else: bundle.addfile(item)
        data=archive.read_bytes()
        manager=self.manager; manager.unit.parent.mkdir(parents=True)
        class Opener:
            def open(self,*a,**kw): return io.BytesIO(data)
        def fake_command(arguments,env=None,timeout=60):
            if len(arguments)>2 and arguments[1]=='setting':
                if '-getApiToken' in arguments: return 'apiToken: fixture-private-api-token-1234567890\n'
                with sqlite3.connect(manager.data/'x-ui.db') as db:
                    db.execute('CREATE TABLE users(id INTEGER PRIMARY KEY, username TEXT, password TEXT, login_epoch INTEGER DEFAULT 0)')
                    db.execute('CREATE TABLE settings(key TEXT,value TEXT)')
            return ''
        return [patch.object(m.platform,'machine',return_value='x86_64'),patch.dict(m.RELEASES,{'x86_64':('amd64',hashlib.sha256(data).hexdigest())}),patch.object(m.urllib.request,'build_opener',return_value=Opener()),patch.object(m,'command',side_effect=fake_command),patch.dict(sys.modules,{'bcrypt':types.SimpleNamespace(hashpw=lambda p,s:b'fixture-hash-only',gensalt=lambda:b'fixture-salt')})]
    def test_fresh_install_initialization(self):
        import contextlib
        with contextlib.ExitStack() as stack:
            for p in self.prepare_install(): stack.enter_context(p)
            stack.enter_context(patch.object(self.manager,'wait_ready'))
            state=self.manager.install()
        self.assertEqual(self.manager.load(),state)
        with sqlite3.connect(self.manager.data/'x-ui.db') as db:
            username,password=db.execute('SELECT username,password FROM users').fetchone()
            settings=dict(db.execute('SELECT key,value FROM settings'))
        self.assertEqual(username,state['username']); self.assertNotEqual(password,state['password'])
        self.assertEqual(settings['subEnable'],'false'); self.assertEqual(settings['subJsonEnable'],'false'); self.assertEqual(settings['subClashEnable'],'false')
        unit=self.manager.unit.read_text(); self.assertNotIn(state['password'],unit); self.assertNotIn(state['apiToken'],unit)
        self.assertIn('UMask=0077',unit)
    def test_failed_install_rolls_back_owned_paths(self):
        import contextlib
        foreign=self.root/'foreign'; foreign.write_text('keep')
        with contextlib.ExitStack() as stack:
            for p in self.prepare_install(): stack.enter_context(p)
            stack.enter_context(patch.object(self.manager,'wait_ready',side_effect=m.Failure('fixture not ready')))
            stack.enter_context(patch.object(m.subprocess,'run'))
            with self.assertRaises(m.Failure): self.manager.install()
        self.assertFalse(self.manager.base.exists()); self.assertFalse(self.manager.data.exists()); self.assertFalse(self.manager.unit.exists()); self.assertEqual(foreign.read_text(),'keep')
class APITests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(self):
                cls.headers=dict(self.headers)
                if self.path.endswith('/redirect'):
                    self.send_response(302); self.send_header('Location','http://127.0.0.1:1/'); self.end_headers(); return
                self.send_response(200); self.end_headers()
                if self.path.endswith('/large'): self.wfile.write(b'x'*(m.MAX_RESPONSE+1))
                elif self.path.endswith('/fail'): self.wfile.write(b'{"success":false,"msg":"private detail"}')
                else: self.wfile.write(b'{"success":true,"obj":{"fixture":true}}')
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),Handler); cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True); cls.thread.start()
    @classmethod
    def tearDownClass(cls): cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
    def api(self): return m.API(dict(STATE,panelPort=self.server.server_port))
    def test_bearer_contract(self):
        self.assertEqual(self.api().call('panel/api/ok'),{'fixture':True}); self.assertEqual(self.headers.get('Authorization'),'Bearer fixture-token-only')
    def test_redirect_refused(self):
        with self.assertRaises(m.Failure): self.api().call('panel/api/redirect')
    def test_oversized_response_refused(self):
        with self.assertRaises(m.Failure): self.api().call('panel/api/large')
    def test_failure_redacts_server_detail(self):
        with self.assertRaises(m.Failure) as error: self.api().call('panel/api/fail')
        self.assertNotIn('private detail',str(error.exception))
    def test_path_guard(self):
        with self.assertRaises(m.Failure): self.api().call('../other')
if __name__=='__main__': unittest.main(verbosity=2)
