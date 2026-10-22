import AppKit
import ImageIO

enum Tests {
    static func run(resources: URL, output: URL) throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checks = 0
        func check(_ condition: Bool, _ reason: String) throws { checks += 1; if !condition { throw SpriteStore.error("Self-test: \(reason)") } }
        let catalog = try Catalog(resources: resources), art = try SpriteStore(root: resources)
        let area = WorkArea(x: 0, y: -1440, width: 2560, height: 1380)
        let e = Engine(catalog: catalog, areas: [area], seed: 17)
        e.autoPair = false; e.autoSolo = false; e.autoWalk = false; e.scale = 1
        var sounds: [String] = []; e.onSound = { key, _ in sounds.append(key) }
        try check(catalog.actions.count == 36 && Catalog.pairs.count == 12 && Catalog.loki.count == 12 && Catalog.thor.count == 12, "catalog counts")
        for key in Catalog.sounds {
            let data = try Data(contentsOf: resources.appendingPathComponent("sounds/\(key).wav"))
            try check(data.count > 44 && String(data: data.prefix(4), encoding: .ascii) == "RIFF" && String(data: data[8..<12], encoding: .ascii) == "WAVE", "invalid WAV \(key)")
        }
        var atlasFrames = 0
        for key in Catalog.pairs + Catalog.loki + Catalog.thor {
            if Catalog.pairs.contains(key) { e.requestPair(key) } else { e.requestSolo(key) }
            for _ in 0..<1000 { if !(e.gathering || e.soloGathering) { break }; e.step(1.0 / 24) }
            try check(!e.gathering && !e.soloGathering, "staging timeout \(key)")
            let info = catalog.actions[key]!
            for i in 0..<(info.seconds * 24) {
                try autoreleasepool {
                    let frame = try actionFrame(key, age: Double(i) / 24, catalog: catalog, art: art)
                    try check(frame.sprite.width == Int(info.width) && frame.sprite.height == 256, "atlas dimensions \(key) \(i)")
                    var visible = false
                    outer: for y in stride(from: 0, to: 256, by: 12) { for x in stride(from: 0, to: Int(info.width), by: 12) {
                        if frame.sprite.alpha(x: x, y: y) > 0.1 { visible = true; break outer }
                    } }
                    try check(visible, "empty atlas frame \(key) \(i)"); atlasFrames += 1
                }
            }
            e.pairAge = 0; e.soloAge = 0
            for _ in 0..<((info.seconds + 1) * 24) { e.step(1.0 / 24) }
            try check(e.pair.isEmpty && e.solo.isEmpty, "action did not release \(key)")
        }
        try check(atlasFrames == 8736, "wrong retained timeline frame count")
        for p in e.pets {
            for state in ["idle","walk","settle","sleep","wake","react","drop"] {
                p.state = state; p.age = 0.3; let f = try petFrame(p, art: art)
                try check(f.width == p.width && f.sprite.width > 0, "missing independent pose \(state)")
            }
        }
        e.loki.x = 10; e.thor.x = area.right - 138
        for p in e.pets { p.state = "idle"; p.until = .greatestFiniteMagnitude; p.ground = area.bottom; p.menuHeld = false; p.dragging = false }
        e.autoPair = true; e.step(65); try check(e.pair.isEmpty, "forced timer pairing without encounter")
        e.loki.x = 100; e.loki.left = false; e.thor.x = 280; e.thor.left = true; e.pairCooldownUntil = e.time + 30
        e.evaluateAutonomy(); try check(e.pair.isEmpty && e.near(), "cooldown or contact geometry")
        e.step(31); try check(!e.pair.isEmpty, "contact did not begin interaction"); e.cancelPair(); e.autoPair = false
        e.loki.x = 10; e.thor.x = area.right - 138; e.autoSolo = true; e.loki.nextSoloAt = e.time + 180; e.thor.nextSoloAt = e.time + 300
        e.step(179); try check(e.solo.isEmpty, "solo timer early"); e.step(1.1)
        try check(Catalog.loki.contains(e.solo), "wrong actor for solo"); e.cancelSolo()
        try check((180...300).contains(e.loki.nextSoloAt - e.time), "solo interval")
        e.loki.nextSoloAt = e.time; e.thor.nextSoloAt = e.time + 300; e.loki.menuHeld = true; e.evaluateAutonomy(); try check(e.solo.isEmpty, "menu-held solo")
        e.loki.menuHeld = false; e.loki.state = "sleep"; e.evaluateAutonomy(); try check(e.solo.isEmpty, "sleep interrupted by solo"); e.loki.state = "idle"; e.autoSolo = false
        e.seek(e.thor, kind: "snackshare"); try check(e.seeking, "manual seeking skipped")
        for _ in 0..<1500 { if !e.seeking { break }; e.step(1.0 / 24) }
        try check(!e.seeking && e.gathering, "manual seeker failed"); e.cancelPair()
        var counts = Dictionary(uniqueKeysWithValues: Catalog.pairs.map { ($0, 0) })
        for _ in 0..<120000 { counts[e.choosePair()]! += 1 }
        for key in Catalog.pairs { try check((9000...11000).contains(counts[key]!), "biased pair selection \(key)") }
        for scale in [1.0, 2.0] {
            e.scale = scale; e.autoWalk = true
            for p in e.pets { p.x = (area.width - p.width * scale) / 2; p.ground = area.bottom; p.hasRoute = false; p.state = "walk"; p.until = e.time + 20 }
            var lmin = e.loki.x, lmax = lmin, tmin = e.thor.x, tmax = tmin
            for _ in 0..<Int((3.4 * area.width / (24 * scale) + 45) * 12) {
                e.step(1.0 / 12); lmin = min(lmin, e.loki.x); lmax = max(lmax, e.loki.x); tmin = min(tmin, e.thor.x); tmax = max(tmax, e.thor.x)
                for p in e.pets { try check(p.x >= area.x && p.x + p.width * scale <= area.right + 0.01, "escaped work area") }
            }
            try check(lmin <= 2 && lmax >= area.right - e.loki.width * scale - 2, "Loki did not cover both edges")
            try check(tmin <= 2 && tmax >= area.right - e.thor.width * scale - 2, "Thor did not cover both edges")
            e.loki.x = 30; e.loki.state = "walk"; e.setRoamTarget(e.loki, left: false); e.loki.until = e.time + 0.1; e.step(0.11)
            let target = e.loki.roamTarget; try check(e.loki.state == "idle", "no short rest"); e.step(2)
            try check(e.loki.roamTarget == target && e.loki.state == "walk" && !e.loki.left, "rest reversed unfinished route")
        }
        e.autoWalk = false; e.beginDrag(e.thor); var shapes = Set<String>()
        for i in 0..<20 { e.thor.age = Double(i) * 0.13; let f = try petFrame(e.thor, art: art)
            shapes.insert("\(f.sprite.width),\(f.sprite.height)"); try check(f.y >= 0 && f.y + Double(f.sprite.height) <= 120 && f.x >= 0, "clipped pickup")
        }
        try check(shapes.count >= 5, "static pickup"); e.endDrag(e.thor); try check(e.thor.state == "drop", "missing landing"); e.step(0.5); try check(e.thor.state == "idle", "landing stuck")
        e.requestPair("hammer"); while e.gathering { e.step(0.1) }; e.pairAge = 2.3; let before = sounds.count
        e.paused = true; let time = e.time; e.step(1); try check(e.time == time && sounds.count == before, "pause advanced cues"); e.paused = false
        e.thor.menuHeld = true; e.step(0.3); try check(e.pairAge == 2.3 && sounds.count == before, "menu advanced cues"); e.thor.menuHeld = false
        e.step(0.2); try check(sounds.count == before + 1 && sounds.last == "thud", "hammer cue mismatch"); e.step(0.01); try check(sounds.count == before + 1, "cue repeated"); e.cancelPair()
        // Actual AppKit rendering is compared with fixtures rendered from the unchanged Windows assets.
        e.scale = 1; e.loki.state = "idle"; e.loki.left = false; e.loki.dragging = false; e.thor.state = "idle"; e.thor.left = false; e.thor.dragging = false
        let cases: [(String, DisplayFrame)] = try [
            ("loki-idle", petFrame(e.loki, art: art)), ("thor-idle", petFrame(e.thor, art: art)),
            ("hammer-first", actionFrame("hammer", age: 0, catalog: catalog, art: art)),
            ("flight-middle", actionFrame("flight", age: 3.7, catalog: catalog, art: art))]
        for (name, f) in cases {
            let v = SpriteView(frame: NSRect(x: 0, y: 0, width: f.width, height: f.height)); v.frameToDraw = f; v.displayScale = 1
            let url = output.appendingPathComponent(name + ".png"); try v.exportPNG(url)
            // ImageIO interprets untagged PNG as sRGB, just like the runtime loader.
            // NSBitmapImageRep(data:) instead assumes Generic RGB for untagged PNG.
            let fixtureURL = resources.appendingPathComponent("fixtures/\(name).png")
            guard let actual = NSBitmapImageRep(data: try Data(contentsOf: url)), let source = CGImageSourceCreateWithURL(fixtureURL as CFURL, nil), let reference = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw SpriteStore.error("Missing renderer fixture \(name)") }
            let expected = NSBitmapImageRep(cgImage: reference)
            try check(actual.pixelsWide == expected.pixelsWide && actual.pixelsHigh == expected.pixelsHigh, "render dimensions \(name)")
            for y in 0..<expected.pixelsHigh { for x in 0..<expected.pixelsWide {
                let a = actual.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!, b = expected.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                try check(abs(a.alphaComponent - b.alphaComponent) < 0.01, "render alpha/orientation \(name) at \(x),\(y)")
                if b.alphaComponent > 0.99 { try check(max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent)) < 0.035, "render color \(name)") }
                try check(f.opaque(at: Point(x: Double(x), y: Double(y))) == (b.alphaComponent > 0.1), "transparent hit-test \(name)")
            } }
        }
        let multiple = Engine(catalog: catalog, areas: [area, WorkArea(x: -1280, y: -1440, width: 1280, height: 1000)], seed: 1)
        multiple.loki.x = -900; multiple.loki.ground = -500; multiple.clamp(multiple.loki)
        try check(multiple.area(multiple.loki).x == -1280, "negative-coordinate monitor")
        multiple.setScale(3); try check(multiple.scale <= 2, "oversized action on narrow screen")
        let report = "PASS\nAssertions=\(checks)\nTimeline frames=\(atlasFrames); paired=12; solo=24; sounds=14.\nCovered: all atlas frames, staging and release, manual seeking, contact-only pairing, uniform selection, solo timers, sleep/menu/pause guards, long roaming at 1x and 2x, rests, pickup and landing, sparse sound cues, negative monitor coordinates, size fitting, actual AppKit rendering versus Windows fixtures, transparency and pixel hit-testing.\nArchitecture=\(ProcessInfo.processInfo.machineArchitecture)\n"
        try report.write(to: output.appendingPathComponent("self-test.txt"), atomically: true, encoding: .utf8); print(report)
    }
}
extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
