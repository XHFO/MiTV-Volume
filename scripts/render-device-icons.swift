// Apple AppKit renders SF Symbols; iconutil builds the Core Audio resources.
import AppKit
let base = URL(fileURLWithPath: CommandLine.arguments[1])
func canvas(_ width: Int, _ height: Int, draw: () -> Void) -> NSBitmapImageRep {
 let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:rep)
 draw(); NSGraphicsContext.restoreGraphicsState(); return rep
}
func save(_ rep:NSBitmapImageRep,_ url:URL) throws {try rep.representation(using:.png,properties:[:])!.write(to:url)}
let devices=[("display","display","显示器"),("speaker","speaker.wave.2.fill","扬声器"),("headphones","headphones","耳机"),("homepod","homepod.fill","HomePod"),("appletv","appletv.fill","Apple TV"),("homepodmini","homepodmini.fill","HomePod mini"),("usb","cable.connector","USB"),("bluetooth","NSBluetoothTemplate","蓝牙"),("airplay","airplayaudio","AirPlay"),("thunderbolt","bolt.fill","Thunderbolt"),("firewire","externaldrive","FireWire"),("mac","laptopcomputer","本机 Mac")]
let resources=base.appendingPathComponent("Resources/DeviceIcons")
try FileManager.default.createDirectory(at:resources,withIntermediateDirectories:true)
let sets=URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("MiTVVolume-DeviceIconsets")
try FileManager.default.createDirectory(at:sets,withIntermediateDirectories:true)
for (key,symbol,_) in devices {
 guard let image = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:200,weight:.regular)) ?? NSImage(named:NSImage.Name(symbol)) else {fatalError("Missing public system artwork: \(symbol)")}
 let dir=sets.appendingPathComponent("Device-\(key).iconset")
 try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
 for size in [16,32,128,256,512] {for scale in [1,2] {
  let pixels=size*scale; let n=CGFloat(pixels)
  let rep=canvas(pixels,pixels) {
   let ratio=min(n*0.78/image.size.width,n*0.78/image.size.height)
   let w=image.size.width*ratio,h=image.size.height*ratio
   image.draw(in:NSRect(x:(n-w)/2,y:(n-h)/2,width:w,height:h))
  }
  try save(rep,dir.appendingPathComponent("icon_\(size)x\(size)\(scale==2 ? "@2x" : "").png"))
 }}
}

for (key, _, _) in devices {
 let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
 task.arguments = ["-c", "icns", sets.appendingPathComponent("Device-\(key).iconset").path,
                   "-o", resources.appendingPathComponent("Device-\(key).icns").path]
 try task.run(); task.waitUntilExit()
 guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
}
