// Native WebKit fixture: compare stitched pixels with one full-height rendering.
// Build against PinSnipCore.framework, then run with an optional output directory.
import AppKit
import WebKit
import PinSnipCore

@MainActor final class Loader: NSObject, WKNavigationDelegate {
    var ready: CheckedContinuation<Void, Never>?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready?.resume(); ready = nil
    }
}
@MainActor func run() async throws {
    let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/previews", isDirectory: true)
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    let blocks = (0..<20).map { i in
        "<div class='row' style='background:hsl(\(i * 17),35%,\(92 - i % 3 * 5)%)'><b>\(String(format:"%02d",i + 1))</b> Continuous content · row \(i + 1)<span>pixel boundaries</span></div>"
    }.joined()
    let html = """
    <style>*{box-sizing:border-box}html,body{margin:0;height:100%;overflow:hidden;font:14px -apple-system}header,footer{position:absolute;left:0;right:0;display:flex;align-items:center;justify-content:center;background:#f7ead2;color:#63362d;font-weight:600;z-index:2}header{top:0;height:62px;border-bottom:2px solid #ae795a}footer{bottom:0;height:48px;border-top:2px solid #ae795a}#viewport{position:absolute;top:62px;bottom:48px;left:0;right:0;overflow-y:scroll;scrollbar-width:none}.row{height:50px;padding:6px 18px;border-bottom:1px solid #bac0c5}.row b{margin-right:14px;font-size:20px}.row span{display:block;font-size:10px;margin-left:39px}</style><header>Fixed header · Search / Profile</header><div id='viewport'>\(blocks)</div><footer>History · Articles · Personal profile</footer>
    """
    let loader = Loader()
    let web = WKWebView(frame: CGRect(x:0,y:0,width:420,height:420))
    web.navigationDelegate = loader
    let window = NSWindow(contentRect:web.frame,styleMask:.borderless,backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    window.contentView = web
    window.orderBack(nil)
    await withCheckedContinuation { continuation in loader.ready = continuation; web.loadHTMLString(html,baseURL:nil) }
    try await Task.sleep(for:.milliseconds(300))
    func snapshot() async throws -> CGImage {
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with:nil) { image, error in
                if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: error ?? NSError(domain:"Snapshot",code:1)) }
            }
        }
        return image.cgImage(forProposedRect:nil,context:nil,hints:nil)!
    }
    func save(_ image:CGImage, _ name:String) throws {
        try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to: outputDirectory.appendingPathComponent("scroll-\(name).png"))
    }
    let cases:[(String,CGFloat,CGFloat)] = [("full",0,420),("loose",58,318),("tight",66,302)]
    let assemblers = cases.map { _ in ScrollingCaptureAssembler() }
    var scale:CGFloat = 1
    for offset in [0,80,160,240,320,400,480,560,640,689,690] {
        _ = try await web.evaluateJavaScript("document.getElementById('viewport').scrollTop=\(offset)")
        try await Task.sleep(for:.milliseconds(90))
        let frame = try await snapshot()
        scale = CGFloat(frame.width)/420
        for (i,item) in cases.enumerated() {
            let crop = frame.cropping(to:CGRect(x:0,y:item.1*scale,width:CGFloat(frame.width),height:item.2*scale))!
            let start = Date()
            let result = assemblers[i].append(crop)
            print("\(item.0) offset=\(offset) \(result) \(Date().timeIntervalSince(start))s")
        }
    }
    window.setContentSize(CGSize(width:420,height:1110))
    web.frame = CGRect(x:0,y:0,width:420,height:1110)
    _ = try await web.evaluateJavaScript("document.getElementById('viewport').scrollTop=0")
    try await Task.sleep(for:.milliseconds(200))
    let expected = try await snapshot()
    try save(expected,"expected")
    for (i,item) in cases.enumerated() {
        let output = assemblers[i].makeImage()!
        let target = expected.cropping(to:CGRect(x:0,y:item.1*scale,width:CGFloat(expected.width),height:(item.2+690)*scale))!
        let actualPixels = ScrollingCaptureFrame(image:output)!
        let expectedPixels = ScrollingCaptureFrame(image:target)!
        let different = zip(actualPixels.rgbaPixels,expectedPixels.rgbaPixels).filter { $0 != $1 }.count
        print("RESULT \(item.0) height=\(output.height) expected=\(target.height) differingChannels=\(different)")
        try save(output,item.0)
        if output.height != target.height || different != 0 { throw NSError(domain:"PixelMismatch",code:1) }
    }
    window.close()
}
_ = NSApplication.shared
Task { @MainActor in
    do { try await run(); exit(0) }
    catch { print("ERROR \(error)"); exit(1) }
}
NSApp.run()
