const HOST = 'local.ultra.SwiftDownload';
const isWeb = value => { try { const u = new URL(value); return ['http:', 'https:'].includes(u.protocol) && !u.username && !u.password; } catch { return false; } };
async function send(url, filename = '', automatic = false, referer = null) {
  if (!isWeb(url)) throw new Error('仅支持 HTTP/HTTPS 链接');
  const result = await chrome.runtime.sendNativeMessage(HOST, {command: 'enqueue', url, filename, automatic, referer});
  if (!result?.ok) throw new Error(result?.error || 'App 没有接收任务');
  return result;
}
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({id:'swift-download', title:'使用疾风下载', contexts:['link'], targetUrlPatterns:['http://*/*','https://*/*']});
});
chrome.contextMenus.onClicked.addListener(async info => {
  if (info.menuItemId !== 'swift-download') return;
  try { await send(info.linkUrl); await chrome.action.setBadgeText({text:''}); }
  catch (error) { await chrome.storage.local.set({lastError:error.message}); await chrome.action.setBadgeText({text:'!'}); }
});
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (!message || typeof message !== 'object' || (sender.id && sender.id !== chrome.runtime.id)) return false;
  const popup = sender.url === chrome.runtime.getURL('popup.html');
  const source = [sender.url, sender.origin, sender.tab?.url].find(isWeb);
  const video = !!source && ['video-download','video-info'].includes(message.command);
  if (!popup && !video) { respond({ok:false,error:'消息来源无法确认，请刷新视频页后重试'}); return false; }
  if (video) {
    if (message.command === 'video-info') {
      if (!isWeb(message.url)) { respond({ok:false,error:'视频地址无效'}); return false; }
      chrome.runtime.sendNativeMessage(HOST,{command:'probe',url:message.url,referer:new URL(source).origin+'/'}).then(respond).catch(error=>respond({ok:false,error:error.message})); return true;
    }
    if (typeof message.url !== 'string' || typeof message.filename !== 'string' || message.filename.length > 240) { respond({ok:false,error:'视频信息格式无效'}); return false; }
    send(message.url,message.filename,false,new URL(source).origin+'/').then(result=>respond(result)).catch(error=>respond({ok:false,error:error.message})); return true;
  }
  if (message.command === 'send') { send(message.url).then(result=>respond(result)).catch(error=>respond({ok:false,error:error.message})); return true; }
  if (message.command === 'ping') { chrome.runtime.sendNativeMessage(HOST,{command:'ping'}).then(result=>respond({...result,bridgeRevision:'1.2.0-video'})).catch(error=>respond({ok:false,error:error.message})); return true; }
  return false;
});
