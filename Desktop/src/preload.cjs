'use strict';
const {contextBridge,ipcRenderer}=require('electron');
const allowed=new Set(['state','select','scan','confirm','action','open-panel','close-tunnel','copy-panel','choose-key','import','choose-import','export','copy-link','qr','verify']);
contextBridge.exposeInMainWorld('nova',{call:(method,data={})=>{if(!allowed.has(method))return Promise.reject(Error('Invalid request'));return ipcRenderer.invoke('nvps:call',method,data).then(r=>{if(!r.ok)throw Error(r.error);return r.value;});},onState:callback=>{if(typeof callback!=='function')return;const listener=(_event,value)=>callback(value);ipcRenderer.on('nvps:state',listener);return()=>ipcRenderer.removeListener('nvps:state',listener);}});
