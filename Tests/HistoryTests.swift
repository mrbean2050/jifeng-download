import Foundation
@main struct HistoryTests {
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let engine=DownloadEngine(root:root)
  let file=root.appendingPathComponent("saved.mp4");try Data("keep".utf8).write(to:file)
  for status in ["已完成","已取消","下载中","已暂停","失败","检查链接","等待中"] {
   var job=Download(url:"https://example.com/file",filename:"saved.mp4",folder:root.path,connections:1,limitKB:0);job.status=status;engine.jobs.append(job)
  }
  engine.save();engine.clearHistory()
  precondition(engine.jobs.map(\.status)==["下载中","已暂停","失败","检查链接","等待中"])
  let disk=try JSONDecoder().decode([Download].self,from:Data(contentsOf:root.appendingPathComponent("history.json")))
  precondition(disk.count==5);precondition(try! Data(contentsOf:file)==Data("keep".utf8))
  print("PASS history clearing persists, preserves unfinished jobs and downloaded files")
 }
}
