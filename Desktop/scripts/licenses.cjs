'use strict';
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..'),lock=JSON.parse(fs.readFileSync(path.join(root,'package-lock.json')));
let text='NovaVPS Desktop 0.2.0\nGPL-3.0-only; main license is bundled separately.\n\nElectron 45.1.0 (MIT) and Chromium third-party notices are included in the application distribution.\n\n';
for(const [relative,metadata]of Object.entries(lock.packages)){if(!relative||metadata.dev)continue;const folder=path.join(root,relative);if(!fs.existsSync(folder))continue;const pkg=JSON.parse(fs.readFileSync(path.join(folder,'package.json')));text+=`\n===== ${pkg.name} ${pkg.version} (${metadata.license||pkg.license||'see package'}) =====\n`;const files=fs.readdirSync(folder).filter(n=>/^(LICENSE|COPYING)(\.|$|-)/i.test(n));for(const file of files)if(fs.statSync(path.join(folder,file)).isFile())text+=fs.readFileSync(path.join(folder,file),'utf8')+'\n';}
fs.mkdirSync(path.join(root,'resources'),{recursive:true});fs.writeFileSync(path.join(root,'resources/THIRD-PARTY-LICENSES.txt'),text);console.log('Runtime dependency licenses collected.');
