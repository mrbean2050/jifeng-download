from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import time,re,json,pathlib,os
DATA=bytes(range(256))*32768
REQUESTS=[]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_HEAD(self):self.serve(True)
 def do_GET(self):self.serve(False)
 def serve(self,head):
  if self.path=='/stats':
   body=json.dumps(REQUESTS).encode(); self.send_response(200);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body);return
  if self.path=='/needs-ref' and self.headers.get('Referer')!='https://example.com/':self.send_error(403);return
  if self.path=='/missing':self.send_error(404);return
  data=DATA[:524288] if self.path.startswith('/small') else DATA
  ranges=not self.path.startswith('/single'); tag='"fixture-1"'
  value=self.headers.get('Range');start=0;end=len(data)-1
  if value and not self.path.startswith('/liar'):
   match=re.fullmatch(r'bytes=(\d+)-(\d+)',value)
   if not match:self.send_error(416);return
   start,end=map(int,match.groups())
   if start>end or end>=len(data):self.send_error(416);return
  REQUESTS.append({'method':self.command,'path':self.path,'range':value})
  status=206 if value and not self.path.startswith('/liar') else 200
  self.send_response(status);self.send_header('Content-Length',str(end-start+1));self.send_header('ETag',tag)
  if ranges:self.send_header('Accept-Ranges','bytes')
  if status==206:self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
  self.end_headers()
  if head:return
  try:
   for i in range(start,end+1,16384):self.wfile.write(data[i:min(i+16384,end+1)]);self.wfile.flush();time.sleep(.006)
  except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
pathlib.Path(os.environ.get('PORT_FILE','work/fixture-port')).write_text(str(server.server_port))
print(server.server_port,flush=True);server.serve_forever()
