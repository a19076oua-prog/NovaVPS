'use strict';
const fs=require('node:fs/promises');
const path=require('node:path');
const crypto=require('node:crypto');
const {execFileSync}=require('node:child_process');
const version='v26.10.21';
const assets={
 'win32-x64':['Xray-windows-64.zip','fc58c39ee2f2717b4c54d28d374362389e5319b20ae44aea76ea45a5243ec827','xray.exe'],
 'win32-arm64':['Xray-windows-arm64-v8a.zip','bb44af3380c9975f951ce7645c04d56ab600040e68f23974a2806e08e0a3f872','xray.exe'],
 'darwin-arm64':['Xray-macos-arm64-v8a.zip','926cc55fda2a8757dabe4f22dc98772f218ace025f101bd0b68aee232e59d5dc','xray']
};
async function main(){const target=process.argv[2]||process.platform+'-'+process.arch;const asset=assets[target];if(!asset)throw Error('Unsupported target: '+target);const folder=path.resolve(__dirname,'../resources/core');await fs.mkdir(folder,{recursive:true});const url=`https://github.com/XTLS/Xray-core/releases/download/${version}/${asset[0]}`;const response=await fetch(url);if(!response.ok)throw Error('Xray download failed: '+response.status);const bytes=Buffer.from(await response.arrayBuffer());if(bytes.length>100*1024*1024||crypto.createHash('sha256').update(bytes).digest('hex')!==asset[1])throw Error('Xray archive SHA-256 mismatch');const archive=path.join(folder,'download.zip');await fs.writeFile(archive,bytes);try{await require('extract-zip')(archive,{dir:folder});const binary=path.join(folder,asset[2]);await fs.access(binary);if(process.platform!=='win32')await fs.chmod(binary,0o755);const binarySHA256=crypto.createHash('sha256').update(await fs.readFile(binary)).digest('hex');await fs.writeFile(path.join(folder,'manifest.json'),JSON.stringify({version,target,archiveURL:url,archiveSHA256:asset[1],binary:asset[2],binarySHA256,source:'https://github.com/XTLS/Xray-core/tree/'+version},null,2)+'\n');for(const file of await fs.readdir(folder)){if(![asset[2],'manifest.json','download.zip'].includes(file))await fs.rm(path.join(folder,file),{recursive:true,force:true});}await fs.copyFile(path.resolve(__dirname,'../../ThirdParty/Xray-LICENSE'),path.join(folder,'LICENSE'));console.log('Verified Xray '+version+' for '+target);}finally{await fs.rm(archive,{force:true});}}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
