'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const {randomUUID}=require('node:crypto');
const {execFile}=require('node:child_process');
const {promisify}=require('node:util');
const exec=promisify(execFile);
const M=require('./model.cjs');
async function privateDirectory(directory){await fs.mkdir(directory,{recursive:true,mode:0o700});const stat=await fs.lstat(directory);if(stat.isSymbolicLink()||!stat.isDirectory())throw Error('私有数据目录无效。 / Invalid private directory.');if(process.platform==='win32'){const {stdout}=await exec('whoami.exe',['/user','/fo','csv','/nh'],{windowsHide:true,timeout:10000});const sid=stdout.match(/S-1-5-[0-9-]+/)?.[0];if(!sid)throw Error('无法识别当前 Windows 用户。 / Cannot identify Windows user.');await exec('icacls.exe',[directory,'/inheritance:r','/grant:r',`*${sid}:(OI)(CI)F`,'*S-1-5-18:(OI)(CI)F'],{windowsHide:true,timeout:10000});}else await fs.chmod(directory,0o700);}
async function atomic(file,data){const temporary=file+'.'+randomUUID()+'.tmp';try{await fs.writeFile(temporary,data,{flag:'wx',mode:0o600});await fs.rename(temporary,file);if(process.platform!=='win32')await fs.chmod(file,0o600);}finally{await fs.rm(temporary,{force:true}).catch(()=>{});}}
function record(raw){if(!raw||typeof raw.id!=='string'||!/^[a-f0-9-]{36}$/i.test(raw.id))throw Error('服务器记录无效。 / Invalid server record.');const request=M.request(raw.request);const value={id:raw.id,name:String(raw.name||request.host).slice(0,80),request};if(raw.pin)value.pin=M.pin(raw.pin,request);if(raw.node)value.node=M.node(raw.node);if(raw.lastState)value.lastState=String(raw.lastState).slice(0,30);if(raw.verifiedAt&&Number.isFinite(Date.parse(raw.verifiedAt))){value.verifiedAt=raw.verifiedAt;if(Number.isFinite(raw.milliseconds)&&raw.milliseconds>=0)value.milliseconds=Math.round(raw.milliseconds);}return value;}
class Store{
 constructor(directory){this.directory=directory;this.file=path.join(directory,'servers.json');this.records=[];}
 async init(){await privateDirectory(this.directory);try{const stat=await fs.lstat(this.file);if(stat.isSymbolicLink()||stat.size>M.MAX)throw Error('服务器记录文件无效。');const raw=JSON.parse(await fs.readFile(this.file,'utf8'));if(!Array.isArray(raw)||raw.length>5000)throw Error('服务器记录文件无效。');this.records=raw.map(record);}catch(error){if(error.code!=='ENOENT')throw Error('无法读取服务器记录，原文件已保留。 / Cannot read server records; original file preserved.');}return this;}
 async put(raw){const value=record(raw),next=this.records.filter(r=>r.id!==value.id);next.push(value);const data=JSON.stringify(next,null,2);if(Buffer.byteLength(data)>M.MAX)throw Error('服务器记录超出大小限制。');await atomic(this.file,data);this.records=next;return value;}
 async remove(id){const next=this.records.filter(r=>r.id!==id);await atomic(this.file,JSON.stringify(next,null,2));this.records=next;}
}
async function exportFiles(node,directory){M.node(node);await privateDirectory(directory);const qr=require('qrcode');const link=M.share(node);const files={'node.xray.json':JSON.stringify(M.nativeJSON(node),null,2)+'\n','node.clash.yaml':M.YAML.stringify(M.clash(node)),'node.vless.txt':link+'\n','node-qr.png':await qr.toBuffer(link,{type:'png',errorCorrectionLevel:'M',margin:4,scale:8})};try{for(const[name,data]of Object.entries(files))await atomic(path.join(directory,name),data);}catch(error){await fs.rm(directory,{recursive:true,force:true});throw error;}return Object.keys(files);}
module.exports={privateDirectory,atomic,record,Store,exportFiles};
