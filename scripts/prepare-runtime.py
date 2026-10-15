#!/usr/bin/env python3
import hashlib, pathlib, subprocess, urllib.request, zipfile
root=pathlib.Path(__file__).resolve().parent.parent
cache=root/'.cache';cache.mkdir(exist_ok=True)
runtime=root/'Runtime';runtime.mkdir(exist_ok=True)
assets=[('yt-dlp', 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp_macos', '0f192b7ec147ab6288885d6351d9ab67367640029b4377576ef46dd79cf7b202'), ('deno-macos-arm64.zip', 'https://github.com/denoland/deno/releases/download/v2.9.7/deno-aarch64-apple-darwin.zip', '5cd46d6268f6f78f5d88bdc7159d20bd44cdaa4b3303474839f87ec6fe7ae25c'), ('ffmpeg-8.0.1.tar.xz', 'https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz', '05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41')]
for name,url,digest in assets:
 p=cache/name
 if not p.exists(): urllib.request.urlretrieve(url,p)
 if hashlib.sha256(p.read_bytes()).hexdigest()!=digest: raise SystemExit('Checksum mismatch: '+name)
(runtime/'yt-dlp').write_bytes((cache/'yt-dlp').read_bytes())
with zipfile.ZipFile(cache/'deno-macos-arm64.zip') as z: (runtime/'deno').write_bytes(z.read('deno'))
source=cache/'ffmpeg-8.0.1'
if not source.exists(): subprocess.run(['tar','-xf',str(cache/'ffmpeg-8.0.1.tar.xz'),'-C',str(cache)],check=True)
subprocess.run(['bash',str(root/'scripts/build-ffmpeg.sh'),str(source)],check=True)
(runtime/'ffmpeg').write_bytes((source/'ffmpeg').read_bytes())
for name in ['yt-dlp','deno','ffmpeg']: (runtime/name).chmod(0o755)
print('Runtime ready')
