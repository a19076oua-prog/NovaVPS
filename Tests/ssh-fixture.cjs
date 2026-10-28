const { Server } = require('ssh2');
const fs=require('fs'), http=require('http'), net=require('net');
const folder=process.argv[2];
const panel=http.createServer((req,res)=>{res.writeHead(200,{'Content-Type':'text/plain'});res.end('NOVAVPS_TUNNEL_FIXTURE');});
let connections=new Set();
panel.listen(0,'127.0.0.1',()=>{
 const state={panelPort:panel.address().port,basePath:'/'+'a'.repeat(32)+'/',username:'fixture',password:'fixture-panel-password-only',version:'v3.11.0'};
 const ssh=new Server({hostKeys:[fs.readFileSync(folder+'/host-key')]},c=>{
  connections.add(c); c.on('close',()=>connections.delete(c)); c.on('error',()=>{});
  c.on('authentication',a=>a.method==='password'&&a.username==='root'&&a.password==='fixture-ssh-password-only'?a.accept():a.reject());
  c.on('ready',()=>{
   c.on('session',accept=>{const s=accept();s.on('exec',(accept,reject,info)=>{const stream=accept();let input='';stream.on('data',d=>input+=d);stream.on('end',()=>{
    if(!input.includes('NOVAVPS_PYTHON')||!input.includes('python3')) {stream.exit(1);stream.end();return;}
    const result={success:true,result:{installed:true,state:'active',panel:{...state,port:state.panelPort},inboundCount:0,node:null}};
    delete result.result.panel.panelPort;
    stream.write('NOVAVPS_RESULT: '+Buffer.from(JSON.stringify(result)).toString('base64')+'\n');stream.exit(0);stream.end();
   });});});
   c.on('tcpip',(accept,reject,info)=>{
    if(info.destIP!=='127.0.0.1'||info.destPort!==state.panelPort){reject();return;}
    const remote=net.connect(state.panelPort,'127.0.0.1',()=>{const stream=accept();remote.pipe(stream).pipe(remote);stream.on('error',()=>remote.destroy());});remote.on('error',()=>{try{reject();}catch{}});
   });
  });
 });
 ssh.on('error',e=>{process.stderr.write(e.message+'\n');process.exit(1);});
 ssh.listen(0,'127.0.0.1',()=>fs.writeFileSync(folder+'/ready.json',JSON.stringify({sshPort:ssh.address().port,panel:state}),{mode:0o600}));
 const stop=()=>{for(const c of connections)c.end();ssh.close();panel.close(()=>process.exit(0));setTimeout(()=>process.exit(0),1000).unref();};process.on('SIGTERM',stop);
});
