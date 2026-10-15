globalThis.chrome = globalThis.browser || globalThis.chrome;
const $ = id => document.getElementById(id);
chrome.storage.local.get(['automatic','lastError']).then(s => { $('automatic').checked = !!s.automatic; $('status').textContent = s.lastError || '首次使用：在 App 中启用浏览器联动，然后检查连接。'; });
$('automatic').onchange = () => chrome.storage.local.set({automatic:$('automatic').checked});
async function request(message) { try { const r = await chrome.runtime.sendMessage(message); $('status').textContent = r?.ok ? (message.command === 'ping' ? '连接正常 · App '+(r.version || '')+' · '+(r.bridgeRevision || '后台仍为旧版，请在扩展页重新加载') : '已加入 App 下载队列') : (r?.error || '请先在 App 中启用浏览器联动'); } catch(e) { $('status').textContent = e.message; } }
$('check').onclick = () => request({command:'ping'});
$('send').onclick = () => request({command:'send',url:$('url').value});

async function enableVideo() {
  try {
    const patterns = ['http://*/*','https://*/*'];
    const allowed = await chrome.permissions.request({origins:patterns});
    if (!allowed) throw new Error('未获准网站访问权限，保持原来的范围');
    const id = 'video-all-sites';
    const files = ['video-source.js','video.js'];
    const existing = await chrome.scripting.getRegisteredContentScripts({ids:[id]});
    if (!existing.length) await chrome.scripting.registerContentScripts([{id,matches:patterns,js:files,allFrames:true,runAt:'document_idle',persistAcrossSessions:true}]);
    const tabs = await chrome.tabs.query({url:patterns});
    await Promise.allSettled(tabs.map(t=>chrome.scripting.executeScript({target:{tabId:t.id,allFrames:true},files})));
    $('site').textContent = '已为所有 HTTP / HTTPS 网站启用视频按钮。';
    $('status').textContent='回到视频页面即可看到“疾风下载”按钮。受浏览器保护的页面不支持。';
  } catch(error) { $('status').textContent=error.message; }
}
$('enable-all-video').onclick = () => enableVideo();

$('version').textContent = "浏览器已加载助手版本：" + chrome.runtime.getManifest().version;

chrome.permissions.contains({origins:["http://*/*","https://*/*"]}).then(all=>{if(all) $("site").textContent="已允许所有普通网站；如没有按钮，点击“所有网站显示视频按钮”恢复启用。";});
