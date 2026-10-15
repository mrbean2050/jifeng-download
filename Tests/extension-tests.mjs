import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
let messageListener;
let created, failure=false, events=[], automatic=true;
const chrome={runtime:{id:'test',getURL:p=>'chrome-extension://test/'+p,onInstalled:{addListener(){}},onMessage:{addListener:f=>messageListener=f},sendNativeMessage:async(host,message)=>{events.push('send');if(failure)throw Error('host absent');return message.command==='probe'?{ok:true,size:8126464}:{ok:true};}},contextMenus:{onClicked:{addListener(){}},create(){}},action:{setBadgeText:async()=>{}},storage:{local:{get:async()=>({automatic}),set:async()=>{}}},downloads:{onCreated:{addListener:f=>created=f},pause:async()=>events.push('pause'),cancel:async()=>events.push('cancel'),resume:async()=>events.push('resume')}};
vm.runInNewContext(fs.readFileSync(new URL('../Extension/background.js',import.meta.url),'utf8'),{chrome,URL,console});
const item={id:1,state:'in_progress',url:'https://example.com/file.bin',filename:'file.bin'};
await created(item);assert.deepEqual(events,['pause','send','cancel']);
events=[];failure=true;await created(item);assert.deepEqual(events,['pause','send','resume']);
for(const changed of [{url:'blob:test'},{incognito:true},{byExtensionId:'other'},{state:'complete'}]) { events=[];await created({...item,...changed});assert.deepEqual(events,[]); }
events=[];automatic=false;await created(item);assert.deepEqual(events,[]);
console.log('PASS extension: acknowledged handoff, native failure recovery, unsupported schemes, privacy and disabled capture');

function message(payload,sender){return new Promise(resolve=>{const async=messageListener(payload,sender,resolve);if(!async)resolve(undefined);});}
failure=false;events=[];
let result=await message({command:'video-download',url:'https://example.com/preview.mp4',filename:'preview.mp4'},{id:'test',url:'https://example.com/page',tab:{id:2}});
assert.equal(result.ok,true);assert.deepEqual(events,['send']);
events=[];result=await message({command:'send',url:'https://example.com/x'},{id:'test',url:'https://example.com/page',tab:{id:2}});assert.equal(result.ok,false);assert.deepEqual(events,[]);
result=await message({command:'video-download',url:'file:///etc/passwd',filename:'x'},{id:'test',url:'https://example.com/page',tab:{id:2}});assert.equal(result.ok,false);
result=await message({command:'video-download',url:'https://example.com/x',filename:'x'},{id:'foreign',url:'https://example.com/page',tab:{id:2}});assert.equal(result,undefined);
console.log('PASS video messages accept own content script and reject foreign/invalid requests');

result=await message({command:'video-download',url:'https://example.com/preview.mp4',filename:'preview.mp4'},{id:'test',origin:'https://example.com'});assert.equal(result.ok,true);
result=await message({command:'video-download',url:'https://example.com/preview.mp4',filename:'preview.mp4'},{origin:'https://example.com'});assert.equal(result.ok,true);
console.log('PASS own message contexts with origin-only metadata');

result=await message({command:'video-info',url:'https://example.com/preview.mp4'},{id:'test',origin:'https://example.com'});assert.equal(result.size,8126464);
result=await message({command:'video-info',url:'file:///etc/passwd'},{id:'test',origin:'https://example.com'});assert.equal(result.ok,false);
console.log('PASS read-only video size requests and URL validation');
