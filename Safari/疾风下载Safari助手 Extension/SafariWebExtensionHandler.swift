import SafariServices
import AppKit
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
 func beginRequest(with context:NSExtensionContext) {
  func reply(_ data:[String:Any]) { let item=NSExtensionItem(); item.userInfo=[SFExtensionMessageKey:data]; context.completeRequest(returningItems:[item]) }
  guard let item=context.inputItems.first as? NSExtensionItem, let message=item.userInfo?[SFExtensionMessageKey] as? [String:Any], let command=message["command"] as? String else { reply(["ok":false,"error":"消息无效"]); return }
  func web(_ text:String)->URL? { guard text.utf8.count<=16384,let u=URL(string:text),["http","https"].contains(u.scheme?.lowercased() ?? ""),u.host != nil,u.user == nil,u.password == nil else{return nil};return u }
  if command == "ping" { reply(["ok":NSWorkspace.shared.urlForApplication(withBundleIdentifier:"local.ultra.SwiftDownload") != nil,"version":"1.2.0 Safari"]); return }
  guard let text=message["url"] as? String,let url=web(text) else {reply(["ok":false,"error":"只支持 HTTP/HTTPS 地址"]);return}
  var referer:String?
  if let source=message["referer"] as? String { guard let u=web(source),var c=URLComponents(url:u,resolvingAgainstBaseURL:false) else {reply(["ok":false,"error":"来源无效"]);return};c.path="/";c.query=nil;c.fragment=nil;referer=c.string }
  if command == "probe" {
   var request=URLRequest(url:url);request.httpMethod="HEAD";request.timeoutInterval=12
   for (key,value) in ["User-Agent":"Mozilla/5.0","Accept":"*/*","Accept-Encoding":"identity","Range":"bytes=0-0"] {request.setValue(value,forHTTPHeaderField:key)}
   if let referer=referer {request.setValue(referer,forHTTPHeaderField:"Referer")}
   URLSession.shared.dataTask(with:request) {_,response,error in
    guard error == nil,let r=response as? HTTPURLResponse,(200...299).contains(r.statusCode) else {reply(["ok":false,"error":"服务器未提供文件信息"]);return}
    let count=r.statusCode == 206 ? Int64((r.value(forHTTPHeaderField:"Content-Range") ?? "").split(separator:"/").last.map(String.init) ?? "") ?? 0 : r.expectedContentLength
    reply(["ok":true,"size":count>0 ? NSNumber(value:count) : NSNull()])
   }.resume();return
  }
  guard command == "enqueue" else {reply(["ok":false,"error":"未知指令"]);return}
  var parts=URLComponents();parts.scheme="swift-download";parts.host="enqueue"
  parts.queryItems=[URLQueryItem(name:"url",value:url.absoluteString),URLQueryItem(name:"filename",value:String((message["filename"] as? String ?? "").prefix(240))),URLQueryItem(name:"referer",value:referer)]
  guard let link=parts.url else {reply(["ok":false,"error":"无法发送链接"]);return}
  DispatchQueue.main.async { let ok=NSWorkspace.shared.open(link);reply(["ok":ok,"error":ok ? "" : "请先打开疾风下载 App"]) }
 }
}
