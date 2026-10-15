import Foundation
import Combine

struct Piece: Codable { var start: Int64; var end: Int64 }
struct Download: Codable, Identifiable {
    var id = UUID()
    var url: String
    var filename: String
    var folder: String
    var connections: Int
    var limitKB: Int
    var status = "等待中"
    var detail = ""
    var total: Int64 = 0
    var received: Int64 = 0
    var validator = ""
    var ranged = false
    var pieces: [Piece] = []
    var forceSingle: Bool? = false
    var bridgeID: String? = nil
    var referer: String? = nil
    var date = Date()
}
struct DownloadError: LocalizedError { let text: String; var errorDescription: String? { text } }
func validURL(_ text: String) throws -> URL {
    guard text.utf8.count <= 16384, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { throw DownloadError(text: "请输入有效的 HTTP 或 HTTPS 链接；不支持嵌入账号密码的链接。") }
    return url
}
func mediaHeaders(_ request: inout URLRequest) {
    request.setValue("Mozilla/5.0",forHTTPHeaderField:"User-Agent")
    request.setValue("*/*",forHTTPHeaderField:"Accept")
    request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
}
func remoteLength(_ response: HTTPURLResponse) -> Int64 {
    if response.statusCode == 206 {
        let range = response.value(forHTTPHeaderField:"Content-Range") ?? ""
        return Int64(range.split(separator:"/").last.map(String.init) ?? "") ?? 0
    }
    return Int64(response.value(forHTTPHeaderField:"Content-Length") ?? "") ?? 0
}
func youtubeURL(_ text: String) -> URL? {
    guard let url = try? validURL(text), let parts = URLComponents(url:url,resolvingAgainstBaseURL:false) else { return nil }
    let host = url.host?.lowercased() ?? ""
    guard ["youtube.com","www.youtube.com","m.youtube.com","youtu.be"].contains(host) else { return nil }
    let id = host == "youtu.be" ? url.pathComponents.dropFirst().first : (url.path == "/watch" ? parts.queryItems?.first(where:{$0.name == "v"})?.value : (["shorts","live"].contains(url.pathComponents.dropFirst().first ?? "") ? url.pathComponents.last : nil))
    guard let id = id, id.count == 11, id.allSatisfy({$0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")}) else { return nil }
    return URL(string:"https://www.youtube.com/watch?v=\(id)")
}
func safeName(_ name: String) -> String {
    let value = name.replacingOccurrences(of: "\\", with: "/").components(separatedBy: "/").last ?? "download"
    let clean = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(180))
    return clean.isEmpty || clean == "." || clean == ".." ? "download" : clean
}
func originReferer(_ text:String) throws -> String {
    let url = try validURL(text)
    guard var parts = URLComponents(url:url,resolvingAgainstBaseURL:false) else { throw DownloadError(text:"来源地址无效") }
    parts.path = "/"; parts.query = nil; parts.fragment = nil
    guard let origin = parts.url?.absoluteString else { throw DownloadError(text:"来源地址无效") }
    return origin
}
final class DownloadEngine: NSObject, ObservableObject {
    @Published var jobs: [Download] = []
    @Published var notice = ""
    let root: URL
    private var generation: [UUID: UUID] = [:]
    private var workers: [UUID: [Task<Void, Never>]] = [:]
    private var videoProcesses: [UUID: Process] = [:]
    private var remaining: [UUID: Int] = [:]
    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpMaximumConnectionsPerHost = 8; c.timeoutIntervalForRequest = 45; c.timeoutIntervalForResource = 7 * 86400
        c.urlCache = nil
        return URLSession(configuration: c)
    }()
    init(root: URL) {
        self.root = root
        super.init()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let file = root.appendingPathComponent("history.json")
            if FileManager.default.fileExists(atPath: file.path) {
                jobs = try JSONDecoder().decode([Download].self, from: Data(contentsOf: file))
                for i in jobs.indices where ["下载中", "检查链接", "合并中"].contains(jobs[i].status) { jobs[i].status = "已暂停" }
            }
        } catch { notice = "无法读取任务记录：\(error.localizedDescription)" }
    }
    func save() {
        do { try JSONEncoder().encode(jobs).write(to: root.appendingPathComponent("history.json"), options: .atomic) }
        catch { notice = "保存任务记录失败：\(error.localizedDescription)" }
    }
    func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func pieceFile(_ id: UUID, _ index: Int) -> URL { directory(id).appendingPathComponent("\(index).part") }
    func length(_ url: URL) -> Int64 { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0 }
    @discardableResult func add(url text: String, name: String? = nil, folder: URL, connections: Int = 4, limitKB: Int = 0, bridgeID: String? = nil, referer:String? = nil) throws -> UUID {
        if let bridgeID = bridgeID, let existing = jobs.first(where: { $0.bridgeID == bridgeID }) { return existing.id }
        let url = try validURL(text)
        let source = try referer.map(originReferer)
        guard [1,2,4,8].contains(connections), (0...1_000_000).contains(limitKB) else { throw DownloadError(text: "连接数或限速设置无效。") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = safeName(youtubeURL(text) != nil ? ((name ?? "YouTube 视频") as NSString).deletingPathExtension + ".mkv" : name?.isEmpty == false ? name! : (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent))
        let stem = (base as NSString).deletingPathExtension; let ext = (base as NSString).pathExtension
        var filename = base; var suffix = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent(filename).path) || jobs.contains(where: { $0.folder == folder.path && $0.filename == filename && $0.status != "已取消" }) {
            filename = "\(stem) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)"); suffix += 1
        }
        var job = Download(url: url.absoluteString, filename: filename, folder: folder.path, connections: connections, limitKB: limitKB)
        job.bridgeID = bridgeID; job.referer = source
        jobs.insert(job, at: 0); save(); start(job.id); return job.id
    }
    func start(_ id: UUID) {
        if videoProcesses[id]?.isRunning == true { notice = "视频工具正在停止，请稍后再继续"; return }
        guard let i = jobs.firstIndex(where: { $0.id == id }), !["下载中", "检查链接", "合并中", "已完成"].contains(jobs[i].status) else { return }
        let g = UUID(); generation[id] = g; jobs[i].status = "检查链接"; jobs[i].detail = ""; save()
        let snapshot = jobs[i]
        if let url = youtubeURL(snapshot.url) { startYouTube(snapshot, url:url, g:g); return }
        Task {
            do {
                var head = URLRequest(url: try validURL(snapshot.url)); head.httpMethod = "HEAD"; head.timeoutInterval = 30; mediaHeaders(&head); head.setValue("bytes=0-0",forHTTPHeaderField:"Range")
                if let referer = snapshot.referer { head.setValue(referer,forHTTPHeaderField:"Referer") }
                var size: Int64 = 0; var tag = ""; var ranges = false
                do {
                    let (_, response) = try await URLSession.shared.data(for: head)
                    if let r = response as? HTTPURLResponse {
                        if r.statusCode >= 400 && r.statusCode != 405 && r.statusCode != 501 { throw DownloadError(text: "服务器返回 HTTP \(r.statusCode)") }
                        if (200...299).contains(r.statusCode) {
                            size = remoteLength(r)
                            let etag = r.value(forHTTPHeaderField: "ETag") ?? ""
                            tag = etag.hasPrefix("W/") ? (r.value(forHTTPHeaderField: "Last-Modified") ?? "") : (etag.isEmpty ? (r.value(forHTTPHeaderField: "Last-Modified") ?? "") : etag)
                            ranges = snapshot.forceSingle != true && size > 0 && r.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes" && !tag.isEmpty
                        }
                    }
                } catch let e as DownloadError { throw e } catch { /* shortcut: HEAD 不可用时单连接下载，取得可靠长度与验证标识后再启用续传。 */ }
                let metadata = (size, tag, ranges)
                await MainActor.run { self.begin(id, g: g, size: metadata.0, validator: metadata.1, ranged: metadata.2) }
            } catch { await MainActor.run { if self.generation[id] == g { self.fail(id, error.localizedDescription) } } }
        }
    }
    private func startYouTube(_ job: Download, url: URL, g: UUID) {
        let id = job.id
        do {
            let tools = Bundle.main.resourceURL!.appendingPathComponent("Tools",isDirectory:true)
            let executable = tools.appendingPathComponent("yt-dlp")
            let ffmpeg = tools.appendingPathComponent("ffmpeg")
            let deno = tools.appendingPathComponent("deno")
            guard FileManager.default.isExecutableFile(atPath:executable.path), FileManager.default.isExecutableFile(atPath:ffmpeg.path), FileManager.default.isExecutableFile(atPath:deno.path) else { throw DownloadError(text:"内置视频工具不完整，请重新安装完整发行版。") }
            try FileManager.default.createDirectory(at:directory(id),withIntermediateDirectories:true)
            let log = directory(id).appendingPathComponent("youtube.log")
            FileManager.default.createFile(atPath:log.path,contents:nil)
            let output = try FileHandle(forWritingTo:log)
            let process = Process(); process.executableURL = executable
            // shortcut: 保留分片继续下载；连接数由解析工具管理，后续有需求再开放画质选择。
            process.arguments = ["--ignore-config","--no-playlist","--no-overwrites","--newline","--no-color","--progress","--progress-template","download:疾风进度 %(progress._percent_str)s","--ffmpeg-location",ffmpeg.path,"--js-runtimes","deno:"+deno.path,"--merge-output-format","mkv","--remux-video","mkv","-f","bv*+ba/b","-o",directory(id).appendingPathComponent("video.%(ext)s").path]
            if job.limitKB > 0 { process.arguments! += ["--limit-rate","\(job.limitKB)K"] }
            process.arguments! += ["--",url.absoluteString]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = tools.path+":/usr/bin:/bin"
            process.environment = environment; process.standardOutput = output; process.standardError = output
            try process.run(); videoProcesses[id] = process
            jobs[jobs.firstIndex(where:{$0.id==id})!].detail = "正在解析 YouTube 视频；不读取登录资料"; save()
            Task.detached { [self] in
                while process.isRunning {
                    let lines = (try? String(contentsOf:log,encoding:.utf8))?.split(separator:"\n") ?? []
                    let detail = lines.last.map(String.init) ?? "正在解析视频"
                    await MainActor.run {
                        guard self.generation[id] == g, let i = self.jobs.firstIndex(where:{$0.id==id}) else { return }
                        self.jobs[i].status = "下载中"; self.jobs[i].detail = String(detail.prefix(400))
                    }
                    try? await Task.sleep(nanoseconds:500_000_000)
                }
                process.waitUntilExit(); try? output.close()
                await MainActor.run {
                    if self.videoProcesses[id] === process { self.videoProcesses[id] = nil }
                    if self.jobs.first(where:{$0.id==id})?.status == "已取消" { try? FileManager.default.removeItem(at:self.directory(id)) }
                    guard self.generation[id] == g, let i = self.jobs.firstIndex(where:{$0.id==id}) else { return }
                    self.videoProcesses[id] = nil
                    do {
                        let result = self.directory(id).appendingPathComponent("video.mkv")
                        guard process.terminationStatus == 0, self.length(result) > 0 else {
                            let lines = (try? String(contentsOf:log,encoding:.utf8))?.split(separator:"\n") ?? []
                            throw DownloadError(text:String((lines.last(where:{$0.contains("ERROR:")}) ?? lines.last ?? "YouTube 下载失败，请重试").prefix(600)))
                        }
                        let target = URL(fileURLWithPath:job.folder).appendingPathComponent(job.filename)
                        try FileManager.default.moveItem(at:result,to:target)
                        self.jobs[i].received=self.length(target); self.jobs[i].total=self.jobs[i].received
                        self.jobs[i].status="已完成"; self.jobs[i].detail="已合并声音与画面，保存到 \(job.folder)"
                        self.generation[id]=nil; self.save()
                    } catch { self.fail(id,error.localizedDescription) }
                }
            }
        } catch { fail(id,error.localizedDescription) }
    }
    private func begin(_ id: UUID, g: UUID, size: Int64, validator: String, ranged: Bool) {
        guard generation[id] == g, let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        do {
            let unchanged = ranged && jobs[i].ranged && jobs[i].total == size && jobs[i].validator == validator && !jobs[i].pieces.isEmpty
            if !unchanged {
                if FileManager.default.fileExists(atPath: directory(id).path) { try FileManager.default.removeItem(at: directory(id)) }
                try FileManager.default.createDirectory(at: directory(id), withIntermediateDirectories: true)
                let n = ranged ? min(jobs[i].connections, max(1, Int(size / (256 * 1024)))) : 1
                jobs[i].pieces = (0..<n).map { j in Piece(start: ranged ? size * Int64(j) / Int64(n) : 0, end: ranged ? size * Int64(j + 1) / Int64(n) - 1 : -1) }
            }
            jobs[i].total = size; jobs[i].validator = validator; jobs[i].ranged = ranged; jobs[i].received = 0
            jobs[i].status = "下载中"
            jobs[i].detail = ranged ? "\(jobs[i].pieces.count) 个分段 · 支持续传" : "单连接 · 暂停后继续会重新下载（服务器未提供可靠续传条件）"
            var pending: [(Int, Piece, Int64)] = []
            for (j, piece) in jobs[i].pieces.enumerated() {
                let path = pieceFile(id, j)
                if !FileManager.default.fileExists(atPath: path.path) { guard FileManager.default.createFile(atPath: path.path, contents: nil) else { throw DownloadError(text: "无法创建临时文件。") } }
                let existing = length(path); let expected = piece.end - piece.start + 1
                guard !ranged || existing <= expected else { throw DownloadError(text: "分段文件长度异常，请取消任务后重新添加。") }
                jobs[i].received += existing
                if ranged && existing == expected { continue }
                pending.append((j, piece, existing))
            }
            remaining[id] = pending.count
            for (j, piece, existing) in pending {
                let snapshot = jobs[i]; let network = session
                let task = Task.detached { [weak self] in
                    guard let self = self else { return }; await self.transfer(snapshot, network:network, g:g, index:j, piece:piece, existing:existing)
                }
                workers[id, default:[]].append(task)
            }
            save()
            if pending.isEmpty { finish(id) }
        } catch { fail(id, error.localizedDescription) }
    }
    func pause(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), ["检查链接", "下载中"].contains(jobs[i].status) else { return }
        stopStreams(id); jobs[i].status = "已暂停"; save()
    }
    func cancel(_ id: UUID) {
        stopStreams(id)
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].status = "已取消"; jobs[i].detail = "已保留历史记录" }
        do { if videoProcesses[id]?.isRunning != true, FileManager.default.fileExists(atPath: directory(id).path) { try FileManager.default.removeItem(at: directory(id)) } }
        catch { notice = "临时文件清理失败：\(error.localizedDescription)" }; save()
    }
    private func stopStreams(_ id: UUID) {
        generation[id] = nil
        if let process = videoProcesses[id], process.isRunning { process.interrupt() }
        workers.removeValue(forKey:id)?.forEach { $0.cancel() }
        remaining[id] = nil
    }
    private func fail(_ id: UUID, _ message: String) {
        stopStreams(id)
        if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].status = "失败"; jobs[i].detail = message }; save()
    }
    func clearHistory() {
        let kept = jobs.filter { !["已完成", "已取消"].contains($0.status) }
        do {
            try JSONEncoder().encode(kept).write(to:root.appendingPathComponent("history.json"),options:.atomic)
            jobs = kept
        } catch { notice = "清空历史记录失败：\(error.localizedDescription)" }
    }
    func pauseAll() { for job in jobs where ["下载中", "检查链接"].contains(job.status) { pause(job.id) } }
    private func transfer(_ snapshot:Download, network:URLSession, g:UUID, index:Int, piece:Piece, existing:Int64) async {
        let id = snapshot.id
        guard await MainActor.run(body:{self.generation[id] == g}) else { return }
        var handle: FileHandle?
        do {
            var request = URLRequest(url:try validURL(snapshot.url))
            mediaHeaders(&request)
            if let referer = snapshot.referer { request.setValue(referer,forHTTPHeaderField:"Referer") }
            if snapshot.ranged { request.setValue("bytes=\(piece.start+existing)-\(piece.end)",forHTTPHeaderField:"Range"); request.setValue(snapshot.validator,forHTTPHeaderField:"If-Range") }
            let (bytes, response) = try await network.bytes(for:request)
            try Task.checkCancellation()
            guard await MainActor.run(body:{self.generation[id] == g}), let r = response as? HTTPURLResponse else { throw CancellationError() }
            if snapshot.ranged {
                let expected = "bytes \(piece.start+existing)-\(piece.end)/\(snapshot.total)"
                let responseValidator = snapshot.validator.hasPrefix("\"") ? r.value(forHTTPHeaderField:"ETag") : r.value(forHTTPHeaderField:"Last-Modified")
                if r.statusCode != 206 || r.value(forHTTPHeaderField:"Content-Range") != expected || responseValidator != snapshot.validator {
                    await MainActor.run {
                        guard self.generation[id] == g else { return }
                        self.stopStreams(id)
                        if let i = self.jobs.firstIndex(where:{$0.id==id}) { self.jobs[i].forceSingle = true; self.jobs[i].status = "已暂停"; self.start(id) }
                    }
                    return
                }
            } else if r.statusCode != 200 { throw DownloadError(text:"服务器返回 HTTP \(r.statusCode)") }
            let encoding = r.value(forHTTPHeaderField:"Content-Encoding")?.lowercased() ?? "identity"
            guard encoding == "identity" || encoding.isEmpty else { throw DownloadError(text:"服务器返回压缩传输，无法安全核对长度。") }
            if !snapshot.ranged && response.expectedContentLength>0 { await MainActor.run { if self.generation[id]==g, let i=self.jobs.firstIndex(where:{$0.id==id}) { self.jobs[i].total=response.expectedContentLength } } }
            let file = try FileHandle(forWritingTo:pieceFile(id,index)); handle = file; try file.seekToEnd()
            var buffer = Data(); buffer.reserveCapacity(32768)
            var count:Int64=0; let began=Date()
            func flush() async throws {
                guard !buffer.isEmpty else { return }
                try Task.checkCancellation(); guard await MainActor.run(body:{self.generation[id]==g}) else { throw CancellationError() }
                if snapshot.ranged && existing+count+Int64(buffer.count) > piece.end-piece.start+1 { throw DownloadError(text:"分段响应超过预期长度。") }
                if snapshot.limitKB>0 {
                    let due=Double(count+Int64(buffer.count))/(Double(snapshot.limitKB*1024)/Double(snapshot.pieces.count))-Date().timeIntervalSince(began)
                    if due>0 { try await Task.sleep(nanoseconds:UInt64(min(due,3600)*1_000_000_000)) }
                }
                try Task.checkCancellation(); guard await MainActor.run(body:{self.generation[id]==g}) else { throw CancellationError() }
                let chunk = buffer
                try await MainActor.run {
                    guard self.generation[id]==g else { throw CancellationError() }
                    try file.write(contentsOf:chunk)
                    if let i=self.jobs.firstIndex(where:{$0.id==id}) { self.jobs[i].received += Int64(chunk.count) }
                }
                count += Int64(chunk.count); buffer.removeAll(keepingCapacity:true)
            }
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count>=32768 { try await flush() }
            }
            try await flush(); try Task.checkCancellation(); try file.close(); handle=nil
            if snapshot.ranged && length(pieceFile(id,index)) != piece.end-piece.start+1 { throw DownloadError(text:"分段长度不完整，可以继续重试。") }
            await MainActor.run {
                guard self.generation[id]==g else { return }
                self.remaining[id,default:1] -= 1
                if self.remaining[id]==0 { self.finish(id) } else { self.save() }
            }
        } catch {
            try? handle?.close()
            await MainActor.run { if self.generation[id]==g { self.fail(id,error.localizedDescription) } }
        }
    }
    private func finish(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].status = "合并中"
        do {
            let merged = directory(id).appendingPathComponent("complete.tmp")
            if FileManager.default.fileExists(atPath: merged.path) { try FileManager.default.removeItem(at: merged) }
            guard FileManager.default.createFile(atPath: merged.path, contents: nil) else { throw DownloadError(text: "无法创建合并文件。") }
            let out = try FileHandle(forWritingTo: merged)
            do {
                for j in jobs[i].pieces.indices {
                    let input = try FileHandle(forReadingFrom: pieceFile(id, j))
                    do { while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try out.write(contentsOf: data) }; try input.close() }
                    catch { try? input.close(); throw error }
                }
                try out.close()
            } catch { try? out.close(); throw error }
            if jobs[i].total > 0 && length(merged) != jobs[i].total { throw DownloadError(text: "下载文件长度不匹配，未保存为完成文件。") }
            let target = URL(fileURLWithPath: jobs[i].folder).appendingPathComponent(jobs[i].filename)
            // moveItem refuses an existing target; never overwrite user files.
            try FileManager.default.moveItem(at: merged, to: target)
            jobs[i].received = length(target); jobs[i].total = jobs[i].received; jobs[i].status = "已完成"; jobs[i].detail = "已保存到 \(jobs[i].folder)"; generation[id] = nil; workers[id] = nil; remaining[id] = nil
            do { try FileManager.default.removeItem(at: directory(id)) } catch { notice = "下载完成，临时文件清理失败：\(error.localizedDescription)" }
            save()
        } catch { fail(id, error.localizedDescription) }
    }
}
