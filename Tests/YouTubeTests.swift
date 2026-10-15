import Foundation
@main struct YouTubeTests {
 @MainActor static func main() async throws {
  assert(youtubeURL("https://youtube.com.evil.example/watch?v=jNQXAC9IVRw") == nil)
  assert(youtubeURL("https://youtu.be/jNQXAC9IVRw?list=unrelated")?.absoluteString == "https://www.youtube.com/watch?v=jNQXAC9IVRw")
  let root=URL(fileURLWithPath:CommandLine.arguments[1]); let engine=DownloadEngine(root:root)
  let target = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "https://www.youtube.com/watch?v=jNQXAC9IVRw"
  let id=try engine.add(url:target,name:"视频验证.mp4",folder:root.appendingPathComponent("Saved"),referer:CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil)
  for _ in 0..<360 {
   try await Task.sleep(nanoseconds:500_000_000)
   let j=engine.jobs.first(where:{$0.id==id})!
   if j.status == "已完成" { print("PASS video engine completed: \(j.filename) \(j.received) bytes"); return }
   if j.status == "失败" { throw DownloadError(text:j.detail) }
  }
  engine.pause(id); throw DownloadError(text:"YouTube test timed out")
 }
}
