import Foundation
import AppKit

let hostName = "local.ultra.swift_download"
let supportRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/SwiftDownload", isDirectory: true)
struct BridgeRequest: Codable {
    var command: String
    var url: String?
    var filename: String?
    var automatic: Bool?
    var id: String?
    var referer: String?
}
func extensionID() -> String {
    (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("extension-id.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
}
func bridgeInbox(_ root: URL = supportRoot) -> URL { root.appendingPathComponent("Inbox", isDirectory: true) }
func remoteHead(_ url:URL, referer:String?) throws -> HTTPURLResponse {
    final class Result: @unchecked Sendable { var response:HTTPURLResponse?; var error:Error? }
    let result=Result(); let done=DispatchSemaphore(value:0)
    let config=URLSessionConfiguration.ephemeral; config.timeoutIntervalForResource=12
    let session=URLSession(configuration:config)
    defer { session.invalidateAndCancel() }
    var request=URLRequest(url:url); request.httpMethod="HEAD"; request.timeoutInterval=10; mediaHeaders(&request); request.setValue("bytes=0-0",forHTTPHeaderField:"Range")
    if let referer=referer { request.setValue(referer,forHTTPHeaderField:"Referer") }
    let task=session.dataTask(with:request) { _,response,error in result.response=response as? HTTPURLResponse; result.error=error; done.signal() }
    task.resume()
    guard done.wait(timeout:.now()+13) != .timedOut else { task.cancel(); throw DownloadError(text:"查询响应头超时") }
    if let error=result.error { throw error }
    guard let response=result.response, (200...299).contains(response.statusCode) else { throw DownloadError(text:"服务器没有返回可用的文件信息") }
    return response
}
func nativeHost() {
    let input = FileHandle.standardInput; let output = FileHandle.standardOutput
    func readExactly(_ count: Int) -> Data? {
        var data = Data()
        while data.count < count { guard let chunk = try? input.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }; data.append(chunk) }
        return data
    }
    func reply(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        var size = UInt32(data.count).littleEndian
        try? output.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) }); try? output.write(contentsOf: data)
    }
    guard CommandLine.arguments.contains("chrome-extension://\(extensionID())/") || CommandLine.arguments.contains("jifeng-download@mrbean2050") else { reply(["ok":false,"error":"扩展身份不匹配"]); return }
    guard let header = readExactly(4) else { return }
    let size = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
    guard size > 0 && size <= 65536, let body = readExactly(Int(size)) else { reply(["ok":false,"error":"消息长度无效"]); return }
    do {
        var request = try JSONDecoder().decode(BridgeRequest.self, from: body)
        if request.command == "ping" { reply(["ok":true,"version":"1.3.0"]); return }
        guard ["enqueue","probe"].contains(request.command), let text = request.url else { throw DownloadError(text:"未知指令") }
        let url = try validURL(text)
        request.referer = try request.referer.map(originReferer)
        if request.command == "probe" {
            let response=try remoteHead(url,referer:request.referer)
            let count=remoteLength(response)
            let size:Any = count>0 ? NSNumber(value:count) : NSNull()
            reply(["ok":true,"size":size]); return
        }
        if request.automatic == true { _ = try remoteHead(url,referer:request.referer) }
        let inbox = bridgeInbox()
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        request.url = url.absoluteString; request.filename = request.filename.map(safeName); request.id = UUID().uuidString
        let file = inbox.appendingPathComponent(request.id! + ".json")
        try JSONEncoder().encode(request).write(to: file, options: .atomic)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/open")
        process.arguments = ["-g", "-a", Bundle.main.bundleURL.path]; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { try? FileManager.default.removeItem(at:file); throw DownloadError(text:"无法启动疾风下载，请先将 App 拖入应用程序文件夹并打开一次。") }
        reply(["ok":true,"queued":true,"id":request.id!])
    } catch { reply(["ok":false,"error":error.localizedDescription]) }
}
func registerHosts() throws {
    guard !Bundle.main.bundleURL.path.hasPrefix("/Volumes/") else { throw DownloadError(text:"请先把 App 拖入应用程序文件夹，再启用浏览器联动。") }
    let id = extensionID(); guard id.count == 32, let executable = Bundle.main.executableURL else { throw DownloadError(text:"扩展信息不完整。") }
    let launcher = supportRoot.appendingPathComponent("native-host")
    try FileManager.default.createDirectory(at:supportRoot,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    func shellQuote(_ s:String)->String { "'" + s.replacingOccurrences(of:"'",with:"'\\''") + "'" }
    let script = "#!/bin/sh\nexec " + shellQuote(executable.path) + " --native-host \"$@\"\n"
    try script.write(to:launcher,atomically:true,encoding:.utf8)
    try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:launcher.path)
    var manifest:[String:Any] = ["name":hostName,"description":"疾风下载本机通信","path":launcher.path,"type":"stdio","allowed_origins":["chrome-extension://\(id)/"]]
    for relative in ["Google/Chrome/NativeMessagingHosts", "Microsoft Edge/NativeMessagingHosts", "Chromium/NativeMessagingHosts", "BraveSoftware/Brave-Browser/NativeMessagingHosts", "Vivaldi/NativeMessagingHosts", "com.operasoftware.Opera/NativeMessagingHosts", "Mozilla/NativeMessagingHosts"] {
        manifest.removeValue(forKey:"allowed_extensions"); manifest["allowed_origins"] = ["chrome-extension://\(id)/"]
        if relative.hasPrefix("Mozilla/") { manifest.removeValue(forKey:"allowed_origins"); manifest["allowed_extensions"] = ["jifeng-download@mrbean2050"] }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").appendingPathComponent(relative)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let file = dir.appendingPathComponent(hostName+".json")
        if FileManager.default.fileExists(atPath:file.path) {
            let backup = file.appendingPathExtension("backup-"+UUID().uuidString)
            try FileManager.default.copyItem(at:file,to:backup)
        }
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:file,options:.atomic)
    }
}
