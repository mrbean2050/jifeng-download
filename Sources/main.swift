import AppKit
import SwiftUI
import SafariServices

if CommandLine.arguments.contains("--native-host") { nativeHost(); exit(0) }

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = DownloadEngine(root: supportRoot)
    var window: NSWindow!
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root)
        let appMenu = NSMenu(); appMenu.addItem(withTitle:"退出疾风下载",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q"); root.submenu = appMenu
        let edit = NSMenuItem(); edit.title = "编辑"; menu.addItem(edit); let em = NSMenu(title:"编辑"); edit.submenu = em
        em.addItem(withTitle:"剪切",action:#selector(NSText.cut(_:)),keyEquivalent:"x"); em.addItem(withTitle:"复制",action:#selector(NSText.copy(_:)),keyEquivalent:"c"); em.addItem(withTitle:"粘贴",action:#selector(NSText.paste(_:)),keyEquivalent:"v"); em.addItem(withTitle:"全选",action:#selector(NSText.selectAll(_:)),keyEquivalent:"a"); NSApp.mainMenu = menu
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:740),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "疾风下载 · Apple Silicon"; window.minSize = NSSize(width:820,height:610)
        window.contentView = NSHostingView(rootView: ContentView(engine:engine)); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        consumeInbox()
        timer = Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in self?.consumeInbox() }
    }
    func application(_ application:NSApplication, open urls:[URL]) {
        for link in urls where link.scheme == "swift-download" && link.host == "enqueue" {
            do {
                let items=URLComponents(url:link,resolvingAgainstBaseURL:false)?.queryItems ?? []
                guard let text=items.first(where:{$0.name=="url"})?.value else { throw DownloadError(text:"Safari 下载链接无效") }
                let folder=URL(fileURLWithPath:UserDefaults.standard.string(forKey:"folder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
                _ = try engine.add(url:text,name:items.first(where:{$0.name=="filename"})?.value,folder:folder,connections:UserDefaults.standard.integer(forKey:"connections")==0 ? 4 : UserDefaults.standard.integer(forKey:"connections"),limitKB:UserDefaults.standard.integer(forKey:"limitKB"),referer:items.first(where:{$0.name=="referer"})?.value)
            } catch {engine.notice="Safari 任务：\(error.localizedDescription)"}
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationWillTerminate(_ notification:Notification) { engine.pauseAll() }
    func consumeInbox() {
        guard let files = try? FileManager.default.contentsOfDirectory(at:bridgeInbox(),includingPropertiesForKeys:nil) else { return }
        for file in files where file.pathExtension == "json" {
            do {
                let request = try JSONDecoder().decode(BridgeRequest.self,from:Data(contentsOf:file))
                guard request.command == "enqueue", let url = request.url else { throw DownloadError(text:"扩展任务格式无效") }
                let folder = URL(fileURLWithPath:UserDefaults.standard.string(forKey:"folder") ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path)
                _ = try engine.add(url:url,name:request.filename,folder:folder,connections:UserDefaults.standard.integer(forKey:"connections")==0 ? 4 : UserDefaults.standard.integer(forKey:"connections"),limitKB:UserDefaults.standard.integer(forKey:"limitKB"),bridgeID:request.id,referer:request.referer)
                // Leave the inbox request intact unless the task is confirmed on disk.
                let saved = try JSONDecoder().decode([Download].self,from:Data(contentsOf:supportRoot.appendingPathComponent("history.json")))
                guard saved.contains(where:{$0.bridgeID == request.id}) else { throw DownloadError(text:"任务未能持久保存") }
                try FileManager.default.removeItem(at:file)
            } catch { engine.notice = "浏览器任务：\(error.localizedDescription)" }
        }
    }
}
struct ContentView: View {
    @ObservedObject var engine: DownloadEngine
    @State private var url = ""
    @AppStorage("connections") private var connections = 4
    @AppStorage("limitKB") private var limitKB = 0
    @AppStorage("folder") private var folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path
    @State private var showBrowser = false
    @State private var showClearHistory = false
    @State private var filter = "全部"
    @State private var error = ""
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(spacing:12) {
                Image(systemName:"arrow.down.circle.fill").font(.system(size:42)).foregroundStyle(.blue)
                VStack(alignment:.leading,spacing:3) { Text("疾风下载").font(.system(size:25,weight:.bold)); Text("为 Apple Silicon 打造的原生下载器").foregroundStyle(.secondary) }
                Spacer()
                Button { showBrowser = true } label: { Label("浏览器联动",systemImage:"puzzlepiece.extension") }
            }
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    TextField("粘贴 HTTP / HTTPS 下载链接",text:$url).textFieldStyle(.roundedBorder).accessibilityLabel("下载链接").onSubmit(add)
                    Button(action:add) { Label("新建下载",systemImage:"plus") }.buttonStyle(.borderedProminent).disabled(url.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Text("连接数").foregroundStyle(.secondary)
                    Picker("连接数",selection:$connections) { ForEach([1,2,4,8],id:\.self) { Text("\($0)").tag($0) } }.labelsHidden().frame(width:75)
                    Divider().frame(height:18)
                    Text("每任务限速").foregroundStyle(.secondary)
                    TextField("0",value:$limitKB,format:.number.grouping(.never)).frame(width:75).textFieldStyle(.roundedBorder).accessibilityLabel("限速 KB 每秒，0 不限速")
                    Text("KB/s · 0 不限速").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { chooseFolder() } label: { Label("保存位置",systemImage:"folder") }
                }
                Text(folder).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(16).background(.quaternary.opacity(0.45),in:RoundedRectangle(cornerRadius:14))
            HStack {
                Picker("显示任务",selection:$filter) { ForEach(["全部","进行中","已完成"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(width:270)
                Spacer()
                Text("\(engine.jobs.count) 个任务").foregroundStyle(.secondary)
                Button("清空历史记录") { showClearHistory = true }
                    .disabled(!engine.jobs.contains { ["已完成", "已取消"].contains($0.status) })
                Button("全部暂停") { engine.pauseAll() }
            }
            if engine.jobs.isEmpty {
                Spacer()
                VStack(spacing:12) {
                    Image(systemName:"tray.and.arrow.down").font(.system(size:54,weight:.light)).foregroundStyle(.blue.opacity(0.7))
                    Text("从一个下载链接开始").font(.title3.bold())
                    Text("支持分段下载、暂停续传和浏览器发送链接").foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing:10) {
                        ForEach(engine.jobs.filter { filter == "全部" || (filter == "已完成" ? $0.status == "已完成" : !["已完成","已取消"].contains($0.status)) }) { job in
                            row(job)
                        }
                    }.padding(.vertical,2)
                }
            }
            if !engine.notice.isEmpty { Text(engine.notice).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack { Image(systemName:"lock.shield"); Text("文件与任务保存在本机 · 退出时自动暂停"); Spacer(); Text("arm64 · 1.3.0") }.font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(minWidth:790,minHeight:570)
        .alert("清空历史记录？",isPresented:$showClearHistory) {
            Button("取消",role:.cancel) {}
            Button("清空记录",role:.destructive) { engine.clearHistory() }
        } message: { Text("仅清除已完成和已取消的任务记录，不删除已下载文件。正在下载、已暂停和失败的任务会保留。") }
        .sheet(isPresented:$showBrowser) { browserView }
        .alert("无法开始下载",isPresented:Binding(get:{!error.isEmpty},set:{if !$0 {error = ""}})) { Button("好",role:.cancel) { error = "" } } message: { Text(error) }
    }
    func row(_ job:Download)->some View {
        VStack(alignment:.leading,spacing:9) {
            HStack {
                Image(systemName:job.status == "已完成" ? "checkmark.circle.fill" : "doc.fill").foregroundStyle(job.status == "已完成" ? .green : .blue)
                Text(job.filename).font(.headline).lineLimit(1)
                Spacer()
                Text(job.status).font(.caption.bold()).foregroundStyle(job.status == "失败" ? .red : .secondary)
            }
            if job.total > 0 { ProgressView(value:Double(min(job.received,job.total)),total:Double(job.total)).tint(job.status == "已完成" ? .green : .blue) }
            HStack {
                Text(ByteCountFormatter.string(fromByteCount:job.received,countStyle:.file) + (job.total > 0 ? " / " + ByteCountFormatter.string(fromByteCount:job.total,countStyle:.file) : "" )).font(.caption).monospacedDigit()
                Spacer()
                if ["下载中","检查链接"].contains(job.status) { Button("暂停") { engine.pause(job.id) } }
                if ["已暂停","失败","等待中"].contains(job.status) { Button("继续") { engine.start(job.id) } }
                if job.status == "已完成" { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath:job.folder).appendingPathComponent(job.filename)]) } }
                if !["已完成","已取消"].contains(job.status) { Button("取消",role:.destructive) { engine.cancel(job.id) } }
            }
            Text(job.detail).font(.caption).foregroundStyle(job.status == "失败" ? .red : .secondary).textSelection(.enabled)
        }.padding(14).background(Color(NSColor.controlBackgroundColor),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(.quaternary))
    }
    var browserView:some View {
        VStack(alignment:.leading,spacing:17) {
            Text("连接浏览器").font(.title2.bold())
            Text("1. 将疾风下载 App 拖入“应用程序”，然后打开。\n2. 点击下方“启用本机通信”，为 Chrome、Edge、Brave、Vivaldi、Opera 和 Firefox 添加助手连接配置。\n3. 打开浏览器扩展页，开启开发者模式，选择“加载已解压的扩展程序”。\n4. 选择下方打开的“浏览器助手”文件夹。\n5. 点击浏览器工具栏的疾风下载图标，选择“检查连接”。").lineSpacing(5)
            Text("助手权限：管理下载、右键菜单、本机通信、保存设置。视频按钮只在按网站授权后读取播放器地址，不读取 Cookie。自动接管默认关闭。加载助手后，在视频页打开助手，点击“所有网站显示视频按钮”。").font(.callout).foregroundStyle(.secondary)
            Text("Safari：助手已内置在疾风下载中。点击下方 Safari 设置按钮，勾选疾风助手并允许需要的网站；不必安装第二个 App。").font(.callout)
            Button("Safari 扩展设置") {
                SFSafariApplication.showPreferencesForExtension(withIdentifier:"local.ultra.SwiftDownload.SafariExtension") { error in
                    if let error=error { DispatchQueue.main.async { engine.notice="Safari："+error.localizedDescription } }
                }
            }
            HStack {
                Button("启用本机通信") {
                    do { try registerHosts(); engine.notice = "已启用常见浏览器的本机通信。现在可以加载浏览器助手。" }
                    catch { engine.notice = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
                Button("打开助手文件夹") { NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("浏览器助手")) }
                Button("Firefox 助手文件夹") { NSWorkspace.shared.open(Bundle.main.resourceURL!.appendingPathComponent("Firefox助手")) }
                Button("Chrome 扩展页") { NSWorkspace.shared.open(URL(string:"chrome://extensions")!) }
            }
            Text("扩展 ID：\(extensionID())").font(.caption).textSelection(.enabled)
            Text(engine.notice).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("完成") { showBrowser = false }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width:620)
    }
    func add() { do { _ = try engine.add(url:url,folder:URL(fileURLWithPath:folder),connections:connections,limitKB:limitKB); url = "" } catch { self.error = error.localizedDescription } }
    func chooseFolder() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false; panel.prompt = "选择保存位置"; if panel.runModal() == .OK, let selected = panel.url { folder = selected.path } }
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.run()
