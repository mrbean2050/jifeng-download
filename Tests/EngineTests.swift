import Foundation
@main struct EngineTests {
 static func wait(_ condition:()->Bool, seconds:Double=20) {
    let end = Date().addingTimeInterval(seconds)
    while !condition() && Date() < end { RunLoop.main.run(until:Date().addingTimeInterval(0.015)) }
    precondition(condition(),"Condition timed out")
 }
 static func main() throws {
    setbuf(stdout,nil)
    let base = CommandLine.arguments[1]; let root = URL(fileURLWithPath:CommandLine.arguments[2]); let output = root.appendingPathComponent("Files")
    let engine = DownloadEngine(root:root.appendingPathComponent("State"))
    for invalid in ["file:///etc/passwd","javascript:alert(1)","https://user:password@example.com/x", "not a url"] { do { _ = try validURL(invalid); fatalError("Invalid URL accepted") } catch {} }
    precondition(safeName("../../safe.bin")=="safe.bin")
    let origin=try originReferer("https://example.com/private?token=secret#x");precondition(origin=="https://example.com/")
    let expected = Data((0..<8*1024*1024).map{UInt8($0%256)})
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    try Data("original".utf8).write(to:output.appendingPathComponent("test.bin"))
    let id = try engine.add(url:base+"/range",name:"test.bin",folder:output)
    wait({engine.jobs.first(where:{$0.id==id})!.received>100_000})
    engine.pause(id)
    let paused = engine.jobs.first(where:{$0.id==id})!
    precondition(paused.status=="已暂停" && paused.received>0 && paused.received<expected.count)
    print("PAUSED",paused.status,paused.received)
    let restored = DownloadEngine(root:root.appendingPathComponent("State")); restored.start(id)
    wait({["已完成","失败"].contains(restored.jobs.first(where:{$0.id==id})!.status)})
    print("任务记录重载后已完成")
    let done=restored.jobs.first(where:{$0.id==id})!; precondition(done.status=="已完成",done.detail)
    let actual = try Data(contentsOf:output.appendingPathComponent(done.filename)); precondition(actual==expected)
    let original = try String(contentsOf:output.appendingPathComponent("test.bin")); precondition(original=="original")
    print("PASS segmented + pause + persistent resume + byte equality + collision safety")
    for endpoint in ["single","liar"] {
      let id=try restored.add(url:base+"/"+endpoint,folder:output)
      wait({["已完成","失败"].contains(restored.jobs.first(where:{$0.id==id})!.status)})
      let job=restored.jobs.first(where:{$0.id==id})!;precondition(job.status=="已完成",job.detail)
      let actual = try Data(contentsOf:output.appendingPathComponent(job.filename)); precondition(actual==expected)
      print("PASS",endpoint,"safe single-connection download")
    }
    let begin=Date();let limited=try restored.add(url:base+"/small",folder:output,connections:2,limitKB:256)
    wait({["已完成","失败"].contains(restored.jobs.first(where:{$0.id==limited})!.status)})
    precondition(restored.jobs.first(where:{$0.id==limited})!.status=="已完成")
    precondition(Date().timeIntervalSince(begin)>1.5,"Rate limit was bypassed")
    print("PASS rate limiting",Date().timeIntervalSince(begin))
    let protected=try restored.add(url:base+"/needs-ref",folder:output,referer:"https://example.com/private?token=secret")
    wait({["已完成","失败"].contains(restored.jobs.first(where:{$0.id==protected})!.status)})
    let protectedJob=restored.jobs.first(where:{$0.id==protected})!;precondition(protectedJob.status=="已完成",protectedJob.detail)
    precondition(protectedJob.referer=="https://example.com/")
    print("PASS video-origin Referer without private page paths or query parameters")
    let bad=try restored.add(url:base+"/missing",folder:output)
    wait({restored.jobs.first(where:{$0.id==bad})!.status=="失败"})
    precondition(!FileManager.default.fileExists(atPath:output.appendingPathComponent("missing").path))
    let cancelled=try restored.add(url:base+"/range",name:"cancelled.bin",folder:output);restored.cancel(cancelled)
    RunLoop.main.run(until:Date().addingTimeInterval(0.2));precondition(restored.jobs.first(where:{$0.id==cancelled})!.status=="已取消")
    precondition(!FileManager.default.fileExists(atPath:output.appendingPathComponent("cancelled.bin").path))
    print("PASS HTTP failure + cancellation + URL validation")
    restored.pauseAll(); print("ALL ENGINE CHECKS PASSED")
 }
}
