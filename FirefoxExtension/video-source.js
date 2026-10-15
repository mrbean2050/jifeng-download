(() => {
  function resolve(video, base = document.baseURI) {
    if (video.mediaKeys) return {error:'此视频使用加密播放，无法直接下载'};
    let page;
    try { page = new URL(base); } catch {}
    if (page && ['youtube.com','www.youtube.com','m.youtube.com'].includes(page.hostname)) {
      const id = page.pathname === '/watch' ? page.searchParams.get('v') : page.pathname.match(/^\/(?:shorts|live)\/([\w-]{11})$/)?.[1];
      if (/^[\w-]{11}$/.test(id || '')) return {url:'https://www.youtube.com/watch?v='+id,ext:'mkv',format:'YouTube',youtube:true};
    }
    const source = video.currentSrc || video.src || video.querySelector('source[src]')?.src || '';
    if (!source) return {error:'请先播放视频，等待视频地址加载'};
    let url;
    try { url = new URL(source, base); } catch { return {error:'无法识别视频地址'}; }
    if (url.protocol === 'blob:') return {error:'这是分片或内存视频，当前版本不支持直接下载'};
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return {error:'不支持此视频地址'};
    if (/\.(m3u8|mpd)$/i.test(url.pathname)) return {error:'这是流媒体播放列表，当前版本暂不支持合并下载'};
    const match = url.pathname.match(/\.(mp4|webm|mov|m4v|ogv|ogg)$/i);
    const type = video.querySelector('source[type]')?.type || '';
    const ext = match?.[1].toLowerCase() || ({'video/mp4':'mp4','video/webm':'webm','video/ogg':'ogv'}[type]) || 'video';
    return {url:url.href, ext, format:ext === 'video' ? '视频' : ext.toUpperCase()};
  }
  function filename(title, ext) {
    const name = String(title || '网页视频').replace(/[\\/:*?"<>|\x00-\x1f]/g,'_').trim().slice(0,100) || '网页视频';
    return name + '.' + ext;
  }
  function formatSize(bytes) {
    if (!Number.isFinite(bytes) || bytes <= 0) return '大小未知';
    if (bytes >= 1024**3) return (bytes/1024**3).toFixed(2)+' GB';
    if (bytes >= 1024**2) return (bytes/1024**2).toFixed(2)+' MB';
    if (bytes >= 1024) return (bytes/1024).toFixed(1)+' KB';
    return Math.round(bytes)+' B';
  }
  globalThis.SwiftDownloadVideo = {resolve, filename, formatSize};
})();
