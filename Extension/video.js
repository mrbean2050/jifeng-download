(() => {
  if (globalThis.__swiftDownloadVideoInstalled) return;
  globalThis.__swiftDownloadVideoInstalled = true;
  const records = new Map();
  let scheduled = false;
  let inactive = false;
  function scan() {
    scheduled = false;
    if (inactive) return;
    try { if (!chrome.runtime.id) throw new Error('扩展已重新加载'); }
    catch { inactive=true; for (const record of records.values()) record.host.remove(); records.clear(); return; }
    for (const [video, record] of records) {
      if (!video.isConnected) { record.host.remove(); records.delete(video); }
    }
    for (const video of document.querySelectorAll('video')) {
      const rect = video.getBoundingClientRect();
      if (rect.width < 180 || rect.height < 100) { if (records.has(video)) records.get(video).host.style.display = 'none'; continue; }
      let record = records.get(video);
      if (!record) {
        const host = document.createElement('div'); host.dataset.swiftDownloadVideo = 'true';
        Object.assign(host.style,{position:'fixed',zIndex:'2147483646',pointerEvents:'auto',fontSize:'14px'});
        const shadow = host.attachShadow({mode:'open'});
        const style = document.createElement('style');
        style.textContent = ':host{all:initial}div{display:flex;gap:0;align-items:center;background:#1262d9;white-space:nowrap;box-shadow:0 3px 14px #0004;border:1px solid #ffffff80;border-radius:9px;overflow:hidden;font:13px -apple-system,BlinkMacSystemFont,sans-serif}button{appearance:none;border:0;background:transparent;color:#fff;font:inherit;cursor:pointer;padding:9px 11px;line-height:18px}button:hover{background:#ffffff28}button:focus-visible{outline:2px solid #fff;outline-offset:-4px}button:disabled{cursor:wait}button.close{padding:9px 8px;border-left:1px solid #ffffff45}span{color:#fff}p{position:absolute;top:100%;left:0;margin:6px 0 0;padding:9px 12px;width:260px;max-width:65vw;border-radius:8px;color:white;background:#17263e;font:12px/1.6 -apple-system,BlinkMacSystemFont,sans-serif;white-space:normal;overflow-wrap:anywhere;box-shadow:0 3px 14px #0004}p:empty{display:none}';
        const bar = document.createElement('div'); const button = document.createElement('button');
        button.type = 'button'; button.setAttribute('aria-label','使用疾风下载此视频');
        const close = document.createElement('button'); close.type = 'button'; close.className = 'close'; close.textContent = '×'; close.setAttribute('aria-label','隐藏此视频的下载按钮');
        const status = document.createElement('p'); status.setAttribute('role','status');
        bar.append(button, close); shadow.append(style, bar, status); document.documentElement.append(host);
        record = {host, button, status, hidden:false, busy:false, source:'',sizeURL:'',bytes:null,infoState:'idle'}; records.set(video,record);
        close.addEventListener('click',event=>{event.stopPropagation();record.hidden=true;host.style.display='none';});
        button.addEventListener('click',async event=>{
          event.preventDefault(); event.stopPropagation();
          const item = SwiftDownloadVideo.resolve(video);
          if (item.error) { status.textContent=item.error; return; }
          record.busy = true; button.disabled = true; button.textContent = '正在发送…'; status.textContent='';
          try {
            const response = await chrome.runtime.sendMessage({command:'video-download',url:item.url,filename:SwiftDownloadVideo.filename(document.title,item.ext)});
            if (!response?.ok) throw new Error(response?.error || 'App 未接收，请打开助手检查连接');
            status.textContent = '已加入疾风下载，请在 App 中查看进度';
          } catch (error) { status.textContent='发送失败：'+error.message; }
          finally { record.busy=false;button.disabled=false;schedule(); }
        });
      }
      const visible = !record.hidden && rect.bottom > 0 && rect.top < innerHeight && rect.right > 0 && rect.left < innerWidth;
      const display = visible ? 'block' : 'none'; if (record.host.style.display !== display) record.host.style.display=display;
      const left = Math.max(4, Math.min(rect.left+8, innerWidth-260))+'px';
      const top = Math.max(4,rect.top+8)+'px';
      if(record.host.style.left!==left)record.host.style.left=left;
      if(record.host.style.top!==top)record.host.style.top=top;
      const item = SwiftDownloadVideo.resolve(video);
      if (!item.youtube && item.url && record.sizeURL !== item.url) {
        record.sizeURL=item.url; record.bytes=null; record.infoState='loading';
        Promise.resolve().then(()=>chrome.runtime.sendMessage({command:'video-info',url:item.url})).then(result=>{
          if(record.sizeURL!==item.url)return;
          record.bytes=result?.ok && Number.isFinite(result.size) ? result.size : null;
          record.infoState='done'; schedule();
        }).catch(()=>{if(record.sizeURL===item.url){record.infoState='done';schedule();}});
      }
      const size = item.youtube ? '解析后显示进度' : record.infoState==='loading' ? '查询大小…' : SwiftDownloadVideo.formatSize(record.bytes);
      const label = item.error ? '↓ 疾风下载 · 视频' : '↓ 疾风下载 · '+item.format+' · '+size;
      if(!record.busy && record.button.textContent!==label) record.button.textContent=label;
      record.button.title = item.error || '下载当前播放器提供的视频；预览画质与原片可能不同';
      const source = item.url || item.error;
      if(record.source!==source){record.source=source;record.status.textContent='';}
    }
  }
  function schedule() { if (!scheduled) { scheduled=true;requestAnimationFrame(scan); } }
  new MutationObserver(mutations=>{
    if(mutations.some(m=>!(m.target instanceof Element && m.target.closest('[data-swift-download-video]'))))schedule();
  }).observe(document.documentElement,{subtree:true,childList:true,attributes:true,attributeFilter:['src','class','style','width','height']});
  for(const event of ['scroll','resize','loadedmetadata','loadstart','emptied','play','fullscreenchange']) addEventListener(event,schedule,true);
  schedule();
})();
