// FadeForge: entirely local barber reel editor for macOS.
// Original source written independently for this repository, MIT licensed.
import Foundation
import AVFoundation
import AppKit
import CoreGraphics
import QuartzCore
import CryptoKit

struct FadeForgeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct BrandLogo: Codable {
    let file: String
    let sha256: String
    let imported: String
}

struct VideoInput {
    let url: URL
    let asset: AVURLAsset
    let track: AVAssetTrack
    let seconds: Double
    let transform: CGAffineTransform
    let naturalSize: CGSize
}

struct VideoSegment {
    let phase: String
    let input: VideoInput
    let sourceStart: Double
    let sourceDuration: Double
    let outputDuration: Double
}

struct PlacedSegment {
    let phase: String
    let start: Double
    let end: Double
}

struct ReelStyle {
    var duration = 24.0
    var width = 1080
    var height = 1920
    var fps: Int32 = 30
    var transition = "dissolve"
    var dissolve = 0.22
    var processSpeed = 2.0
    var logoPosition = "top-right"
    var logoWidth = 0.19
    var showLabels = true

    init(_ url: URL) throws {
        guard let source = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw FadeForgeError("STYLE.md must use UTF-8 text.")
        }
        var values: [String: String] = [:]
        for originalLine in source.components(separatedBy: .newlines) {
            let line = originalLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("<!--") { continue }
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { values[key] = value }
        }
        if let x = Double(values["duration_seconds"] ?? "") { duration = min(60, max(8, x)) }
        if let value = values["resolution"], value == "720x1280" { width = 720; height = 1280 }
        if let value = values["resolution"], value == "1080x1920" { width = 1080; height = 1920 }
        if let x = Int32(values["fps"] ?? "") { fps = min(60, max(24, x)) }
        if let x = values["transition"], ["cut", "dissolve"].contains(x) { transition = x }
        if let x = Double(values["transition_seconds"] ?? "") { dissolve = min(0.5, max(0.05, x)) }
        if let x = Double(values["process_speed"] ?? "") { processSpeed = min(4, max(1, x)) }
        if let x = values["logo_position"], ["top-left", "top-right", "bottom-left", "bottom-right"].contains(x) { logoPosition = x }
        if let x = Double(values["logo_width_percent"] ?? "") { logoWidth = min(0.32, max(0.08, x / 100)) }
        if let x = values["show_before_after_labels"] { showLabels = ["yes", "true", "1"].contains(x.lowercased()) }
    }
}

func at(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60000) }
func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func home(_ part: String) -> URL { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(part) }
func argValues(_ args: [String], _ name: String) -> [String] {
    var values: [String] = []
    for i in 0..<args.count where args[i] == name && i + 1 < args.count { values.append(args[i + 1]) }
    return values
}
func oneArg(_ args: [String], _ name: String) -> String? { argValues(args, name).last }
func readManifest() throws -> BrandLogo? {
    let file = home("brand/logo.json")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    return try JSONDecoder().decode(BrandLogo.self, from: Data(contentsOf: file))
}
func logoFile() throws -> URL? {
    guard let logo = try readManifest() else { return nil }
    guard logo.file.range(of: #"^[a-f0-9]{64}\.(png|jpg|jpeg|webp)$"#, options: .regularExpression) != nil else {
        throw FadeForgeError("Invalid saved logo path in brand/logo.json")
    }
    let url = home("brand/originals/") .appendingPathComponent(logo.file)
    let bytes = try Data(contentsOf: url)
    guard sha256Hex(bytes) == logo.sha256 else { throw FadeForgeError("Stored original logo was altered. Refusing to render.") }
    return url
}
func saveLogo(_ path: String, replacing: Bool) throws {
    let from = URL(fileURLWithPath: path)
    let ext = from.pathExtension.lowercased()
    guard ["png", "jpg", "jpeg", "webp"].contains(ext) else { throw FadeForgeError("Logo must be PNG, JPG, or WebP.") }
    guard let ns = NSImage(contentsOf: from), ns.size.width > 0, ns.size.height > 0 else { throw FadeForgeError("Cannot open image file as a logo.") }
    let original = try Data(contentsOf: from)
    guard !original.isEmpty && original.count <= 20 * 1024 * 1024 else { throw FadeForgeError("Logo must be 20 MB or smaller.") }
    let sum = sha256Hex(original)
    if let old = try readManifest() {
        if old.sha256 == sum { print("Already saved: exact original logo is unchanged."); return }
        if !replacing { throw FadeForgeError("A logo is already saved. To change it, explicitly ask Codex to replace the logo.") }
    }
    let folder = home("brand/originals")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let filename = "\(sum).\(ext)"
    let destination = folder.appendingPathComponent(filename)
    if !FileManager.default.fileExists(atPath: destination.path) { try original.write(to: destination, options: .atomic) }
    let manifest = BrandLogo(file: filename, sha256: sum, imported: ISO8601DateFormatter().string(from: Date()))
    let encoded = try JSONEncoder().encode(manifest)
    try encoded.write(to: home("brand/logo.json"), options: .atomic)
    print(replacing ? "Logo replaced at owner's explicit request." : "Original logo stored. Future edits reuse it unchanged.")
    print("SHA-256: \(sum)")
}
func getInput(_ path: String) async throws -> VideoInput {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { throw FadeForgeError("Video file not found: \(path)") }
    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = tracks.first else { throw FadeForgeError("No video track in \(path)") }
    let seconds = CMTimeGetSeconds(try await asset.load(.duration))
    guard seconds.isFinite && seconds > 0.15 else { throw FadeForgeError("Video is too short or has invalid duration: \(path)") }
    let transform = try await track.load(.preferredTransform)
    let size = try await track.load(.naturalSize)
    guard size.width > 0 && size.height > 0 else { throw FadeForgeError("Invalid video dimensions: \(path)") }
    return VideoInput(url: url, asset: asset, track: track, seconds: seconds, transform: transform, naturalSize: size)
}
func cropTransform(for input: VideoInput, width: Int, height: Int) -> CGAffineTransform {
    let bounds = CGRect(origin: .zero, size: input.naturalSize).applying(input.transform)
    let iw = max(1, abs(bounds.width))
    let ih = max(1, abs(bounds.height))
    let factor = max(CGFloat(width) / iw, CGFloat(height) / ih)
    return input.transform
        .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        .concatenating(CGAffineTransform(scaleX: factor, y: factor))
        .concatenating(CGAffineTransform(translationX: (CGFloat(width) - iw * factor) / 2,
                                        y: (CGFloat(height) - ih * factor) / 2))
}
func logoLayer(_ url: URL, _ style: ReelStyle) throws -> CALayer {
    guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw FadeForgeError("Could not read stored logo without changing it.")
    }
    let layer = CALayer()
    let w = CGFloat(style.width) * style.logoWidth
    let h = min(CGFloat(style.height) * 0.22, w * CGFloat(cg.height) / CGFloat(cg.width))
    let margin = CGFloat(style.width) * 0.045
    let x = style.logoPosition.hasSuffix("right") ? CGFloat(style.width) - w - margin : margin
    let y = style.logoPosition.hasPrefix("top") ? CGFloat(style.height) - h - margin : margin
    layer.frame = CGRect(x: x, y: y, width: w, height: h)
    layer.contents = cg
    layer.contentsGravity = .resizeAspect
    layer.masksToBounds = false
    return layer
}
func addLabel(_ title: String, start: Double, end: Double, total: Double, style: ReelStyle, to parent: CALayer) {
    guard end - start > 0.2 else { return }
    let text = CATextLayer()
    text.string = title
    text.fontSize = CGFloat(style.width) * 0.046
    text.alignmentMode = .center
    text.foregroundColor = NSColor.white.cgColor
    text.shadowColor = NSColor.black.cgColor
    text.shadowOpacity = 0.85
    text.shadowRadius = 9
    text.shadowOffset = CGSize(width: 1, height: 2)
    text.contentsScale = 1
    text.frame = CGRect(x: CGFloat(style.width) * 0.12, y: CGFloat(style.height) * 0.10,
                        width: CGFloat(style.width) * 0.76, height: CGFloat(style.height) * 0.055)
    text.opacity = 0
    let anim = CAKeyframeAnimation(keyPath: "opacity")
    let fade = min(0.15, (end - start) / 4)
    anim.values = [0, 1, 1, 0]
    anim.keyTimes = [NSNumber(value: max(0, start / total)), NSNumber(value: min(1, (start + fade) / total)),
                     NSNumber(value: min(1, (end - fade) / total)), NSNumber(value: min(1, end / total))]
    anim.duration = total
    anim.beginTime = AVCoreAnimationBeginTimeAtZero
    anim.isRemovedOnCompletion = false
    anim.fillMode = .forwards
    text.add(anim, forKey: "fade")
    parent.addSublayer(text)
}

func selectSegments(_ inputs: [VideoInput], phase: String, count: Int,
                    groupDuration: Double, extraOverlap: Double, speed: Double) -> [VideoSegment] {
    let allotted = (groupDuration + extraOverlap) / Double(count)
    return (0..<count).map { i in
        let input = inputs[i % inputs.count]
        let sourceWanted = allotted * speed
        let sourceAvailable = max(0.2, input.seconds - 0.05)
        let sourceDuration = min(sourceWanted, sourceAvailable)
        let availableStart = max(0, input.seconds - sourceDuration - 0.03)
        let fraction = Double((i / inputs.count) % 3) / 2.0
        return VideoSegment(phase: phase, input: input,
                            sourceStart: availableStart * fraction,
                            sourceDuration: sourceDuration, outputDuration: allotted)
    }
}
func exportVideo(_ composition: AVMutableComposition, videoComp: AVMutableVideoComposition,
                 destination: URL) async throws {
    guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
        throw FadeForgeError("Cannot create the macOS video export session.")
    }
    guard exporter.supportedFileTypes.contains(.mp4) else { throw FadeForgeError("MP4 export is not supported for this input.") }
    exporter.outputURL = destination
    exporter.outputFileType = .mp4
    exporter.videoComposition = videoComp
    exporter.shouldOptimizeForNetworkUse = true
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        exporter.exportAsynchronously { continuation.resume() }
    }
    switch exporter.status {
    case .completed: return
    case .failed: throw FadeForgeError("AVFoundation export failed: \(exporter.error?.localizedDescription ?? "unknown error")")
    case .cancelled: throw FadeForgeError("Export was cancelled")
    default: throw FadeForgeError("Export did not finish: \(exporter.status.rawValue)")
    }
}
func render(_ args: [String]) async throws {
    let beforePaths = argValues(args, "--before")
    let processPaths = argValues(args, "--process")
    let afterPaths = argValues(args, "--after")
    guard !beforePaths.isEmpty, !processPaths.isEmpty, !afterPaths.isEmpty else {
        throw FadeForgeError("Provide at least one --before, --process, and --after video. Repeat flags for more clips.")
    }
    let style = try ReelStyle(home("brand/STYLE.md"))
    let duration: Double = {
        if let custom = oneArg(args, "--duration"), let d = Double(custom) { return max(8, min(60, d)) }
        return style.duration
    }()
    let before = try await loadInputs(beforePaths)
    let process = try await loadInputs(processPaths)
    let after = try await loadInputs(afterPaths)
    let nb = min(2, max(1, before.count))
    let np = min(7, max(4, process.count * 2))
    let na = min(2, max(1, after.count))
    let totalCount = nb + np + na
    let dissolve = style.transition == "cut" ? 0 : min(style.dissolve, duration / Double(totalCount * 5))
    // Add overlap time to each phase's allocated output duration so that final
    // running time still equals exactly the requested duration.
    let beforeBase = duration * 0.16
    let processBase = duration * 0.55
    let afterBase = duration - beforeBase - processBase
    let segments = selectSegments(before, phase: "before", count: nb, groupDuration: beforeBase,
                                  extraOverlap: dissolve * Double(nb) / Double(totalCount) * Double(totalCount - 1), speed: 1)
                 + selectSegments(process, phase: "process", count: np, groupDuration: processBase,
                                  extraOverlap: dissolve * Double(np) / Double(totalCount) * Double(totalCount - 1), speed: style.processSpeed)
                 + selectSegments(after, phase: "after", count: na, groupDuration: afterBase,
                                  extraOverlap: dissolve * Double(na) / Double(totalCount) * Double(totalCount - 1), speed: 1)
    // A reel should never silently omit this owner's logo.
    guard let storedLogo = try logoFile() else {
        throw FadeForgeError("Please upload your barbershop logo once before rendering. Ask Codex to save your logo.")
    }
    let composition = AVMutableComposition()
    guard let a = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
          let b = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw FadeForgeError("Unable to create composition video tracks.")
    }
    let layers = [AVMutableVideoCompositionLayerInstruction(assetTrack: a), AVMutableVideoCompositionLayerInstruction(assetTrack: b)]
    let tracks = [a, b]
    var placed: [PlacedSegment] = []
    var cursor = 0.0
    for (idx, s) in segments.enumerated() {
        let track = tracks[idx % 2]
        let instruction = layers[idx % 2]
        let time = at(cursor)
        try track.insertTimeRange(CMTimeRange(start: at(s.sourceStart), duration: at(s.sourceDuration)),
                                  of: s.input.track, at: time)
        track.scaleTimeRange(CMTimeRange(start: time, duration: at(s.sourceDuration)), toDuration: at(s.outputDuration))
        instruction.setTransform(cropTransform(for: s.input, width: style.width, height: style.height), at: time)
        let end = cursor + s.outputDuration
        if dissolve > 0 && idx > 0 {
            instruction.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1,
                                       timeRange: CMTimeRange(start: time, duration: at(dissolve)))
        } else {
            instruction.setOpacity(1, at: time)
        }
        if dissolve > 0 && idx < segments.count - 1 {
            instruction.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0,
                                       timeRange: CMTimeRange(start: at(end - dissolve), duration: at(dissolve)))
        }
        placed.append(PlacedSegment(phase: s.phase, start: cursor, end: end))
        cursor = end - (idx < segments.count - 1 ? dissolve : 0)
    }
    let totalSeconds = placed.last?.end ?? duration
    let videoComp = AVMutableVideoComposition()
    videoComp.renderSize = CGSize(width: style.width, height: style.height)
    videoComp.frameDuration = CMTime(value: 1, timescale: style.fps)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: at(totalSeconds))
    instruction.layerInstructions = layers
    videoComp.instructions = [instruction]

    let canvas = CALayer()
    canvas.frame = CGRect(x: 0, y: 0, width: style.width, height: style.height)
    canvas.backgroundColor = NSColor.black.cgColor
    let videoLayer = CALayer()
    videoLayer.frame = canvas.bounds
    canvas.addSublayer(videoLayer)
    canvas.addSublayer(try logoLayer(storedLogo, style))
    if style.showLabels {
        if let lastBefore = placed.last(where: { $0.phase == "before" }) {
            addLabel("BEFORE", start: 0, end: lastBefore.end,
                     total: totalSeconds, style: style, to: canvas)
        }
        if let firstAfter = placed.first(where: { $0.phase == "after" }) {
            addLabel("AFTER", start: firstAfter.start, end: totalSeconds,
                     total: totalSeconds, style: style, to: canvas)
        }
    }
    videoComp.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: canvas)
    let outputs = home("outputs")
    try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)
    let output: URL
    if let requested = oneArg(args, "--output") {
        output = URL(fileURLWithPath: requested).standardizedFileURL
        guard output.pathExtension.lowercased() == "mp4" else { throw FadeForgeError("Output must end in .mp4") }
        guard output.path.hasPrefix(outputs.standardizedFileURL.path + "/") else {
            throw FadeForgeError("For privacy, output files must stay inside this project's outputs/ folder")
        }
    } else {
        let safeTime = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        output = outputs.appendingPathComponent("barber-reel-\(safeTime)-\(UUID().uuidString.prefix(6)).mp4")
    }
    guard !FileManager.default.fileExists(atPath: output.path) else { throw FadeForgeError("Refusing to overwrite existing file: \(output.path)") }
    print("Editing \(segments.count) segments locally. No audio. \(style.width)x\(style.height). Target: \(Int(duration)) sec")
    try await exportVideo(composition, videoComp: videoComp, destination: output)
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: output.path),
          let bytes = attrs[.size] as? NSNumber, bytes.intValue > 1000 else {
        throw FadeForgeError("Export finished without a valid-sized MP4 output file.")
    }
    print("SUCCESS: \(output.path)")
    print("Output bytes: \(bytes)")
}
func loadInputs(_ paths: [String]) async throws -> [VideoInput] {
    var sources: [VideoInput] = []
    for path in paths { sources.append(try await getInput(path)) }
    return sources
}

func tinyImage(_ original: CGImage) -> [UInt8]? {
    let w = 16, h = 16
    var result = [UInt8](repeating: 0, count: w * h * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let succeeded = result.withUnsafeMutableBytes { ptr -> Bool in
        guard let context = CGContext(data: ptr.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: 4 * w,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.interpolationQuality = .low
        context.draw(original, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return succeeded ? result : nil
}
func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var total = 0
    for i in stride(from: 0, to: a.count, by: 4) {
        total += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i+1]) - Int(b[i+1])) + abs(Int(a[i+2]) - Int(b[i+2]))
    }
    return Double(total) / Double((a.count / 4) * 3 * 255)
}
func analyzeReference(_ path: String) async throws {
    let input = try await getInput(path)
    let generator = AVAssetImageGenerator(asset: input.asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 160, height: 160)
    let last = min(input.seconds - 0.2, 90)
    let interval = max(0.4, last / 150)
    var times: [Double] = []
    var previous: [UInt8]? = nil
    var point = 0.2
    var samples = 0
    while point < last {
        if let cg = try? generator.copyCGImage(at: at(point), actualTime: nil),
           let sample = tinyImage(cg) {
            samples += 1
            if let prev = previous, difference(prev, sample) > 0.23 { times.append((point * 10).rounded() / 10) }
            previous = sample
        }
        point += interval
    }
    let estimatedSeconds = input.seconds / Double(max(1, times.count + 1))
    let summary: [String: Any] = [
        "file": input.url.lastPathComponent, "source_path": input.url.path,
        "duration_seconds": (input.seconds * 100).rounded() / 100,
        "sampled_frames": samples, "possible_cut_times_seconds": times,
        "rough_average_shot_seconds": (estimatedSeconds * 100).rounded() / 100,
        "note": "Rough visual differences only. Camera movement may look like a cut; shots may be missed."
    ]
    let destination = home("media/reference")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let file = destination.appendingPathComponent("reference-analysis-\(UUID().uuidString.prefix(8)).json")
    let bytes = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    try bytes.write(to: file, options: .atomic)
    print("Reference analyzed locally. Approximate cut timestamps: \(times)")
    print("Analysis written: \(file.path)")
    print("This measures rough visual rhythm only. It cannot understand haircut technique or exactly copy a style.")
}
func help() {
    print("""
    FadeForge | Local Mac-native barber video editor (v0.1 prototype)

    Commands:
      check
      status
      save-logo --file /path/logo.png
      replace-logo --file /path/new-logo.png  [requires owner approval]
      analyze-reference --file /path/old-reel.mov
      render --before /path/before.mov --process /path/during.mov --after /path/after.mov
             [repeat phase flags] [--duration 25] [--output outputs/my-reel.mp4]

    Your saved preferences: brand/STYLE.md
    Exports go to outputs/. Source footage and original logo remain unchanged.
    macOS + free Apple Command Line Tools required. No external APIs.
    """)
}
@main
struct FadeForgeMain {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let action = args.first ?? "help"
            switch action {
            case "help", "--help", "-h": help()
            case "check":
                _ = try ReelStyle(home("brand/STYLE.md"))
                print("PASS: macOS native Swift renderer compiled. STYLE.md parsed. Ready to accept actual media.")
                print("NOTE: Compiling successfully is NOT an end-to-end video export test.")
            case "status":
                let style = try ReelStyle(home("brand/STYLE.md"))
                let logo = try logoFile()
                print("Original logo: \(logo?.path ?? "NOT UPLOADED")")
                print("Style: \(Int(style.duration)) sec, \(style.width)x\(style.height), \(style.transition)")
                print("No external video processing is configured.")
            case "save-logo", "replace-logo":
                guard let file = oneArg(args, "--file") else { throw FadeForgeError("Pass --file /path/to/logo.png") }
                try saveLogo(file, replacing: action == "replace-logo")
            case "analyze-reference":
                guard let file = oneArg(args, "--file") else { throw FadeForgeError("Pass --file /path/to/reference.mov") }
                try await analyzeReference(file)
            case "render": try await render(args)
            default: throw FadeForgeError("Unknown command '\(action)'. Run ./bin/fadeforge help")
            }
        } catch {
            fputs("ERROR: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
