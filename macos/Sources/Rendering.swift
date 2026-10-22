import AppKit
import ImageIO

final class Sprite {
    let image: CGImage
    private var bitmap: NSBitmapImageRep?
    var width: Int { image.width }; var height: Int { image.height }
    init(_ image: CGImage) { self.image = image }
    func alpha(x: Int, y: Int) -> Double {
        guard x >= 0 && y >= 0 && x < width && y < height else { return 0 }
        if bitmap == nil { bitmap = NSBitmapImageRep(cgImage: image) }
        return Double(bitmap?.colorAt(x: x, y: y)?.alphaComponent ?? 0)
    }
}
final class SpriteStore {
    let root: URL
    private var poses: [String: Sprite] = [:]
    private var atlasKey = "", frameKey = ""
    private var atlas: CGImage?, lastFrame: Sprite?
    init(root: URL) throws {
        self.root = root
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("assets"), includingPropertiesForKeys: nil)
        guard files.filter({ $0.pathExtension == "png" }).count == 454 else { throw Self.error("Expected 454 PNG resources.") }
    }
    static func error(_ message: String) -> NSError { NSError(domain: "Sprites", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func load(_ key: String) throws -> CGImage {
        let url = root.appendingPathComponent("assets/\(key).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: true] as CFDictionary) else { throw Self.error("Missing sprite: \(key)") }
        return image
    }
    func pose(_ key: String) throws -> Sprite { if let p = poses[key] { return p }; let value = Sprite(try load(key)); poses[key] = value; return value }
    func action(_ key: String, age: Double, info: ActionInfo) throws -> Sprite {
        if atlasKey != key { atlas = nil; lastFrame = nil; frameKey = ""; atlas = try load(key + "-atlas"); atlasKey = key }
        let index = max(0, min(info.seconds * 24 - 1, Int(age * 24))), id = "\(key):\(index)"
        if frameKey == id, let last = lastFrame { return last }
        guard let source = atlas, let cut = source.cropping(to: CGRect(x: Double(index % 12) * info.width, y: Double(index / 12) * 256, width: info.width, height: 256)) else { throw Self.error("Atlas crop failed: \(id)") }
        let result = Sprite(cut); lastFrame = result; frameKey = id; return result
    }
    func releaseAtlas() { atlas = nil; atlasKey = ""; lastFrame = nil; frameKey = "" }
}
struct DisplayFrame {
    let sprite: Sprite; let width: Double; let height: Double; let x: Double; let y: Double; let flip: Bool
    func opaque(at p: Point) -> Bool {
        guard p.x >= 0 && p.y >= 0 && p.x < width && p.y < height else { return false }
        let px = flip ? width - 1 - floor(p.x) : floor(p.x)
        return sprite.alpha(x: Int(px - x), y: Int(floor(p.y) - y)) > 0.1
    }
}
func petFrame(_ p: Pet, art: SpriteStore) throws -> DisplayFrame {
    var key: String; var offset = 0.0
    if p.dragging {
        let cycle = [2,3,2,4,2,5,6,2], n = p.age < 0.22 ? 1 : cycle[Int((p.age - 0.22) * 7) % cycle.count]
        key = p.frog ? "u10-thordrag-\(n)" : Int(p.age * 6) % 2 == 0 ? "u8-ld-11" : "u8-lx-6"
    } else if p.state == "drop" { key = p.frog ? (p.age < 0.2 ? "u10-thordrag-7" : "thor-crouch-low") : (p.age < 0.2 ? "loki-lower" : "loki-idle")
    } else if p.state == "walk" {
        if p.frog {
            let phase = (p.age * 1.5).truncatingRemainder(dividingBy: 1)
            key = phase < 0.18 ? "thor-crouch-low" : phase > 0.84 ? "u7-tb-4" : "thor-air-low"
            if phase >= 0.18 && phase <= 0.84 { offset = Double(Int(sin((phase - 0.18) / 0.66 * .pi) * 16) / 2 * 2) }
        } else { key = "loki-walk-\(Int(p.age * 12) % 8)" }
    } else if p.state == "settle" {
        key = p.frog ? (p.age < 0.5 ? "thor-crouch-low" : "throg-sleep") : (p.age < 0.6 ? "loki-lower" : p.age < 1.2 ? "loki-lie" : "loki-sleep-natural")
    } else if p.state == "wake" { key = p.frog ? "thor-crouch-low" : p.age < 0.5 ? "loki-rise" : "loki-lower"
    } else if p.state == "sleep" { key = p.frog ? "throg-sleep" : "loki-sleep-natural"
    } else if p.state == "react" { key = p.frog ? "throg-laugh" : "loki-flat"
    } else { key = p.frog ? "thor-idle-low" : "loki-idle" }
    let s = try art.pose(key), x = p.frog ? (p.width - Double(s.width)) / 2 : p.width - Double(s.width)
    return DisplayFrame(sprite: s, width: p.width, height: 120, x: x, y: p.frog && p.dragging ? 10 : 120 - Double(s.height) - offset, flip: p.left)
}
func actionFrame(_ key: String, age: Double, catalog: Catalog, art: SpriteStore) throws -> DisplayFrame {
    let info = catalog.actions[key]!
    return DisplayFrame(sprite: try art.action(key, age: age, info: info), width: info.width, height: 256, x: 0, y: 0, flip: false)
}

final class SpriteView: NSView {
    var frameToDraw: DisplayFrame?
    var onClick: (() -> Void)?, onContext: ((NSEvent) -> Void)?, onBeginDrag: (() -> Void)?, onDrag: ((Point) -> Void)?, onEndDrag: (() -> Void)?
    var displayScale = 2.0
    private var mouseStart = NSPoint.zero, windowStart = NSPoint.zero
    private var moved = false, contextClick = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let f = frameToDraw, let c = NSGraphicsContext.current?.cgContext else { return }
        c.clear(bounds); c.saveGState(); c.interpolationQuality = .none; c.setShouldAntialias(false)
        c.scaleBy(x: displayScale, y: displayScale)
        if f.flip { c.translateBy(x: f.width, y: 0); c.scaleBy(x: -1, y: 1) }
        // NSView is top-down; CGImage needs its own local vertical inversion.
        c.translateBy(x: f.x, y: f.y + Double(f.sprite.height)); c.scaleBy(x: 1, y: -1)
        c.draw(f.sprite.image, in: CGRect(x: 0, y: 0, width: f.sprite.width, height: f.sprite.height)); c.restoreGState()
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let f = frameToDraw else { return nil }; let local = convert(point, from: superview)
        return f.opaque(at: Point(x: local.x / displayScale, y: local.y / displayScale)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { contextClick = true; onContext?(event); return }
        contextClick = false
        mouseStart = NSEvent.mouseLocation; windowStart = window?.frame.origin ?? .zero; moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard onDrag != nil else { return }; let now = NSEvent.mouseLocation, dx = now.x - mouseStart.x, dy = now.y - mouseStart.y
        if !moved && abs(dx) + abs(dy) > 5 { moved = true; onBeginDrag?() }
        if moved { onDrag?(Point(x: windowStart.x + dx, y: -(windowStart.y + dy) - bounds.height)) }
    }
    override func mouseUp(with event: NSEvent) {
        if contextClick { contextClick = false; return }
        if moved { onEndDrag?() } else { onClick?() }; moved = false
    }
    override func rightMouseDown(with event: NSEvent) { onContext?(event) }
    func exportPNG(_ url: URL) throws {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { throw SpriteStore.error("Unable to capture sprite view.") }
        cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw SpriteStore.error("Unable to encode sprite view.") }
        try png.write(to: url)
    }
}
final class PetPanel: NSPanel {
    let spriteView = SpriteView()
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false; isReleasedWhenClosed = false; animationBehavior = .none
        contentView = spriteView; ignoresMouseEvents = true
    }
    func show(_ frame: DisplayFrame, at point: Point, scale: Double) {
        let rect = NSRect(x: point.x, y: -point.y - frame.height * scale, width: frame.width * scale, height: frame.height * scale)
        if self.frame != rect { setFrame(rect, display: false) }
        spriteView.displayScale = scale; spriteView.frameToDraw = frame; spriteView.needsDisplay = true
        if !isVisible { orderFrontRegardless() }
    }
    func routePointer(held: Bool = false) {
        guard isVisible, let f = spriteView.frameToDraw else { ignoresMouseEvents = true; return }
        let cursor = NSEvent.mouseLocation, x = (cursor.x - frame.minX) / spriteView.displayScale, y = (frame.maxY - cursor.y) / spriteView.displayScale
        ignoresMouseEvents = !held && !f.opaque(at: Point(x: x, y: y))
    }
}
