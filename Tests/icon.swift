import AppKit
let image=NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let box=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:205,yRadius:205)
NSGradient(colors:[NSColor(calibratedRed:0.02,green:0.70,blue:0.96,alpha:1),NSColor(calibratedRed:0.07,green:0.23,blue:0.78,alpha:1)])!.draw(in:box,angle:-55)
NSGraphicsContext.saveGraphicsState();box.addClip()
let glow=NSBezierPath(ovalIn:NSRect(x:370,y:470,width:730,height:650));NSColor.white.withAlphaComponent(0.09).setFill();glow.fill()
NSGraphicsContext.restoreGraphicsState()
let wind=NSBezierPath();wind.lineWidth=38;wind.lineCapStyle = .round
for (x,y,w) in [(230.0,692.0,142.0),(180.0,582.0,176.0),(242.0,472.0,108.0)] {wind.move(to:NSPoint(x:x,y:y));wind.line(to:NSPoint(x:x+w,y:y))}
NSColor.white.withAlphaComponent(0.70).setStroke();wind.stroke()
let arrow=NSBezierPath();arrow.move(to:NSPoint(x:527,y:803));arrow.line(to:NSPoint(x:756,y:803));arrow.line(to:NSPoint(x:624,y:590));arrow.line(to:NSPoint(x:775,y:590));arrow.line(to:NSPoint(x:483,y:288));arrow.line(to:NSPoint(x:526,y:501));arrow.line(to:NSPoint(x:397,y:501));arrow.close();NSColor.white.setFill();arrow.fill()
let tray=NSBezierPath();tray.lineWidth=47;tray.lineCapStyle = .round;tray.lineJoinStyle = .round
tray.move(to:NSPoint(x:283,y:309));tray.line(to:NSPoint(x:283,y:234));tray.line(to:NSPoint(x:758,y:234));tray.line(to:NSPoint(x:758,y:309));NSColor.white.setStroke();tray.stroke()
image.unlockFocus()
let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
