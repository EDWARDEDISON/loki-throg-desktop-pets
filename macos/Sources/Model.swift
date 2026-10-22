import Foundation

struct Point: Equatable { var x: Double; var y: Double }
struct WorkArea: Equatable {
    var x: Double; var y: Double; var width: Double; var height: Double
    var right: Double { x + width }; var bottom: Double { y + height }
    func contains(_ p: Point) -> Bool { p.x >= x && p.x < right && p.y >= y && p.y < bottom }
    func distanceSquared(_ p: Point) -> Double {
        let dx = max(x - p.x, 0, p.x - right), dy = max(y - p.y, 0, p.y - bottom)
        return dx * dx + dy * dy
    }
}
enum PetID: String { case loki, thor }
final class Pet {
    let id: PetID
    init(_ id: PetID) { self.id = id }
    var frog: Bool { id == .thor }; var width: Double { frog ? 128 : 200 }
    var x = 0.0, ground = 0.0, age = 0.0, until = 0.0, nextSoloAt = 0.0
    var left = false, dragging = false, menuHeld = false
    var state = "idle", hasRoute = false, roamTarget = 0.0
    var roamArea: WorkArea?
}
struct ActionInfo: Decodable {
    let title: String; let seconds: Int; let actor: String; let fps: Int
    var width: Double { actor == "both" && key == "flight" ? 512 : 384 }
    var key = ""
    enum CodingKeys: String, CodingKey { case title, seconds, actor, fps }
}
struct Cue { let at: Double; let sound: String }
struct Catalog {
    var actions: [String: ActionInfo]; var cues: [String: [Cue]]
    static let pairs = ["hammer","ride","cozy","mimic","zap","jar","snake","flight","duobath","swing","reconcile","snackshare"]
    static let loki = ["heart","bath","venom","doctor","sun","run","prank","tailchase","horns","snack","laugh","drag"]
    static let thor = ["recall","lightning","thorheart","thorfly","gear","cloud","landing","thorsleep","sparkchase","mirror","beat","greet"]
    static let sounds = ["chime","chirp","croak","drop","giggle","heart","magic","munch","pickup","soft","splash","thud","whoosh","zap"]
    init(resources: URL) throws {
        actions = try JSONDecoder().decode([String: ActionInfo].self, from: Data(contentsOf: resources.appendingPathComponent("actions.json")))
        for key in Array(actions.keys) { actions[key]!.key = key }
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: resources.appendingPathComponent("sound-cues.json"))) as? [String: [[Any]]] ?? [:]
        cues = [:]
        for (key, rows) in data { cues[key] = rows.compactMap { row in
            guard row.count == 2, let at = row[0] as? Double, let sound = row[1] as? String else { return nil }
            return Cue(at: at, sound: sound)
        } }
        guard Set(actions.keys) == Set(Self.pairs + Self.loki + Self.thor), actions.values.allSatisfy({ $0.fps == 24 }),
              actions.allSatisfy({ key, value in value.actor == (Self.pairs.contains(key) ? "both" : Self.thor.contains(key) ? "thor" : "loki") }),
              Set(cues.keys) == Set(actions.keys), cues.allSatisfy({ key, value in value.allSatisfy { $0.at > 0 && $0.at < Double(actions[key]!.seconds) && Self.sounds.contains($0.sound) } }) else {
            throw NSError(domain: "Catalog", code: 1, userInfo: [NSLocalizedDescriptionKey: "Animation catalog or sound cues are invalid."])
        }
    }
}
// SplitMix64 with rejection sampling: all twelve interactions have the same probability.
struct RandomSource {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15; var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9; z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func int(_ count: Int) -> Int {
        let bound = UInt64(count), threshold = (0 &- bound) % bound
        while true { let n = next(); if n >= threshold { return Int(n % bound) } }
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}

// Positions use top-down desktop coordinates in points; Cocoa conversion is confined to the UI.
final class Engine {
    let catalog: Catalog; let loki = Pet(.loki), thor = Pet(.thor)
    var pets: [Pet] { [loki, thor] }
    var areas: [WorkArea]; var scale = 2.0
    var autoWalk = true, autoPair = true, autoSolo = true, paused = false
    var time = 0.0, ticks = 0, pairCooldownUntil = 0.0, contactLatched = false
    var pair = "", solo = "", gathering = false, seeking = false, soloGathering = false
    var pairAge = 0.0, soloAge = 0.0
    var stage = Point(x: 0, y: 0), soloStage = Point(x: 0, y: 0)
    var lokiTarget = Point(x: 0, y: 0), thorTarget = Point(x: 0, y: 0), soloTarget = Point(x: 0, y: 0)
    var soloActor: Pet?, seeker: Pet?, seekPartner: Pet?
    var onSound: ((String, Double) -> Void)?
    private var random: RandomSource
    init(catalog: Catalog, areas: [WorkArea], seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        precondition(!areas.isEmpty); self.catalog = catalog; self.areas = areas; random = RandomSource(state: seed)
        scale = min(2, maxScale(in: areas[0])); let a = areas[0]
        loki.x = a.right - 680; thor.x = a.right - 240
        for p in pets { p.ground = a.bottom; p.state = "walk"; p.until = 18 + Double(random.int(13)); scheduleSolo(p); clamp(p); ensureRoute(p) }
    }
    func pet(_ id: PetID) -> Pet { id == .loki ? loki : thor }
    func area(_ p: Pet) -> WorkArea { area(at: Point(x: p.x + p.width * scale / 2, y: p.ground - 40)) }
    func area(at point: Point) -> WorkArea { areas.first(where: { $0.contains(point) }) ?? areas.min(by: { $0.distanceSquared(point) < $1.distanceSquared(point) })! }
    func maxScale(in a: WorkArea) -> Double { max(1, min(3, floor(a.width / 512), floor(a.height / 256))) }
    func clamp(_ p: Pet) { let a = area(p); p.x = max(a.x, min(a.right - p.width * scale, p.x)); p.ground = max(a.y + 120 * scale, min(a.bottom, p.ground)) }
    func updateAreas(_ values: [WorkArea]) { guard !values.isEmpty else { return }; cancelSolo(); cancelPair(); areas = values; scale = min(scale, maxScale(in: values[0])); for p in pets { p.hasRoute = false; clamp(p) } }
    func reset(at point: Point? = nil) {
        cancelSolo(); cancelPair(); let a = point.map { area(at: $0) } ?? areas[0]; scale = min(scale, maxScale(in: a))
        loki.x = a.right - 680; thor.x = a.right - 240
        for p in pets { p.ground = a.bottom; p.state = "idle"; p.age = 0; p.until = time + 3; p.hasRoute = false; clamp(p) }
        contactLatched = false
    }
    func setScale(_ value: Double) { cancelSolo(); cancelPair(); scale = max(1, min(value, areas.map { maxScale(in: $0) }.min() ?? 2)); for p in pets { p.hasRoute = false; clamp(p) } }
    func scheduleSolo(_ p: Pet) { p.nextSoloAt = time + 180 + Double(random.int(121)) }
    func ready(_ p: Pet) -> Bool { !p.dragging && !p.menuHeld && ["idle","walk"].contains(p.state) }
    func near() -> Bool {
        guard area(loki) == area(thor), abs(loki.ground - thor.ground) <= 24 * scale else { return false }
        let ll = loki.x + (loki.left ? 0 : 32) * scale, lr = ll + 168 * scale, tl = thor.x + 20 * scale, tr = tl + 88 * scale
        return max(ll, tl) - min(lr, tr) <= 16 * scale
    }
    func choosePair() -> String { Catalog.pairs[random.int(Catalog.pairs.count)] }
    func requestPair(_ key: String) { guard Catalog.pairs.contains(key) else { return }; cancelSolo(); cancelPair(); pair = key; beginStaging(loki) }
    func seek(_ actor: Pet, kind: String) {
        guard Catalog.pairs.contains(kind) else { return }; cancelSolo(); cancelPair(); pair = kind; gathering = true; seeking = true; pairAge = 0
        seeker = actor; seekPartner = actor === loki ? thor : loki
        actor.dragging = false; seekPartner!.dragging = false; actor.state = "walk"; actor.age = 0; seekPartner!.state = "idle"; seekPartner!.age = 0
        if near() { beginStaging(seekPartner!) }
    }
    func seekTarget() -> Point {
        let p = seeker!, q = seekPartner!, a = area(q)
        var x = p.x < q.x ? q.x - p.width * scale + 20 * scale : q.x + q.width * scale - 20 * scale
        if x < a.x { x = q.x + q.width * scale - 20 * scale }
        if x + p.width * scale > a.right { x = q.x - p.width * scale + 20 * scale }
        return Point(x: max(a.x, min(a.right - p.width * scale, x)), y: q.ground)
    }
    func beginStaging(_ anchor: Pet) {
        let a = area(anchor); scale = min(scale, maxScale(in: a)); let width = catalog.actions[pair]!.width * scale
        let center = (loki.x + loki.width * scale / 2 + thor.x + thor.width * scale / 2) / 2
        let left = max(a.x, min(a.right - width, center - width / 2)), ground = max(a.y + 214 * scale, min(a.bottom, anchor.ground))
        stage = Point(x: left, y: ground - 214 * scale)
        lokiTarget = Point(x: left + (214 - loki.width) * scale, y: ground); thorTarget = Point(x: left + (296 - thor.width / 2) * scale, y: ground)
        seeking = false; gathering = true; pairAge = 0; for p in pets { p.state = "walk"; p.age = 0 }
    }
    func cancelPair() {
        guard !pair.isEmpty else { return }; pair = ""; gathering = false; seeking = false; seeker = nil; seekPartner = nil; pairCooldownUntil = time + 30
        for p in pets { p.state = "idle"; p.age = 0; p.until = time + 3; scheduleSolo(p) }
        loki.left = false; thor.left = true; contactLatched = near()
    }
    func requestSolo(_ key: String) {
        guard Catalog.loki.contains(key) || Catalog.thor.contains(key) else { return }; cancelSolo(); cancelPair()
        let p = Catalog.thor.contains(key) ? thor : loki; soloActor = p; let a = area(p); scale = min(scale, maxScale(in: a))
        let anchor = p.frog ? 192 - p.width / 2 : 256 - p.width
        let x = max(a.x, min(a.right - 384 * scale, p.x - anchor * scale)), ground = max(a.y + 214 * scale, min(a.bottom, p.ground))
        soloStage = Point(x: x, y: ground - 214 * scale); soloTarget = Point(x: x + anchor * scale, y: ground)
        solo = key; soloGathering = true; soloAge = 0; p.state = "walk"; p.age = 0; p.dragging = false
    }
    func cancelSolo() { guard !solo.isEmpty, let p = soloActor else { return }; p.state = "idle"; p.age = 0; p.until = time + 3; p.left = false; scheduleSolo(p); solo = ""; soloGathering = false }
    func approach(_ p: Pet, target: Point, dt: Double) -> Bool {
        let dx = target.x - p.x, dy = target.y - p.ground, distance = hypot(dx, dy), step = 100 * scale * dt; p.left = dx < 0; p.age += dt
        if distance <= step { p.x = target.x; p.ground = target.y; return true }
        p.x += dx / distance * step; p.ground += dy / distance * step; return false
    }
    func evaluateAutonomy() {
        guard pair.isEmpty && solo.isEmpty else { return }; let close = near(); if !close { contactLatched = false }
        if autoPair && close && !contactLatched && time >= pairCooldownUntil && ready(loki) && ready(thor) { contactLatched = true; requestPair(choosePair()); return }
        guard autoSolo else { return }; let l = ready(loki) && time >= loki.nextSoloAt, t = ready(thor) && time >= thor.nextSoloAt
        let actor: Pet? = l && t ? (loki.nextSoloAt < thor.nextSoloAt ? loki : thor) : l ? loki : t ? thor : nil
        if let p = actor { let choices = p.frog ? Catalog.thor : Catalog.loki; requestSolo(choices[random.int(choices.count)]) }
    }
    func step(_ dt: Double) {
        precondition(dt >= 0); ticks += 1; if paused { return }; time += dt
        if !solo.isEmpty, let p = soloActor {
            update(p === loki ? thor : loki, dt: dt); if p.menuHeld { return }
            if soloGathering { if approach(p, target: soloTarget, dt: dt) { soloGathering = false; soloAge = 0; p.left = false }; return }
            let prior = soloAge; soloAge += dt; playCues(solo, before: prior, after: soloAge)
            if soloAge >= Double(catalog.actions[solo]!.seconds) { cancelSolo() }; return
        }
        if !pair.isEmpty {
            if loki.menuHeld || thor.menuHeld { return }
            if seeking { seekPartner!.age += dt; seekPartner!.left = seeker!.x < seekPartner!.x; if approach(seeker!, target: seekTarget(), dt: dt) { beginStaging(seekPartner!) }; return }
            if gathering {
                let a = approach(loki, target: lokiTarget, dt: dt), b = approach(thor, target: thorTarget, dt: dt)
                if a && b { gathering = false; pairAge = 0; loki.left = false; thor.left = true }; return
            }
            let prior = pairAge; pairAge += dt; playCues(pair, before: prior, after: pairAge)
            if pairAge >= Double(catalog.actions[pair]!.seconds) {
                loki.x = stage.x + (214 - loki.width) * scale; thor.x = stage.x + (296 - thor.width / 2) * scale
                loki.ground = stage.y + 214 * scale; thor.ground = loki.ground; cancelPair(); for p in pets { clamp(p) }
            }; return
        }
        for p in pets { update(p, dt: dt) }; evaluateAutonomy()
    }
    func setRoamTarget(_ p: Pet, left: Bool) { let a = area(p); p.roamTarget = left ? a.x : max(a.x, a.right - p.width * scale); p.roamArea = a; p.hasRoute = true; p.left = left }
    func ensureRoute(_ p: Pet) {
        let a = area(p), right = max(a.x, a.right - p.width * scale)
        if !p.hasRoute || a != p.roamArea || p.roamTarget < a.x || p.roamTarget > right { setRoamTarget(p, left: p.x > (a.x + right) / 2) }
    }
    func beginDrag(_ p: Pet) { cancelSolo(); cancelPair(); p.dragging = true; p.hasRoute = false; p.age = 0; p.state = "idle"; onSound?(p.frog ? "croak" : "pickup", time) }
    func endDrag(_ p: Pet) { guard p.dragging else { return }; p.dragging = false; p.hasRoute = false; p.state = "drop"; p.age = 0; p.until = time + 0.45; onSound?("drop", time) }
    func click(_ p: Pet) { p.state = "react"; p.age = 0; p.until = time + 1.4; onSound?(p.frog ? "croak" : "chirp", time) }
    func sleep(_ p: Pet) { cancelSolo(); cancelPair(); p.state = p.state == "sleep" ? "wake" : "settle"; p.until = time + (p.state == "wake" ? 1 : 2); p.age = 0 }
    func update(_ p: Pet, dt: Double) {
        if p.menuHeld { return }; if p.dragging { p.age += dt; return }; p.age += dt
        if p.state == "sleep" { return }
        if p.state == "settle" { if p.age >= 2 { p.state = "sleep"; p.age = 0; p.until = .greatestFiniteMagnitude }; return }
        if p.state == "wake" && p.age >= 1 { p.state = "idle"; p.age = 0; p.until = time + 2; return }
        if p.state == "walk" {
            if !autoWalk { p.state = "idle"; p.until = time + 2; return }
            ensureRoute(p); let dx = p.roamTarget - p.x, step = (p.frog ? 30.0 : 24.0) * scale * dt; p.left = dx < 0
            if abs(dx) <= step { p.x = p.roamTarget; p.hasRoute = false; p.state = "idle"; p.age = 0; p.until = time + 1.5 + random.unit() * 2; return }
            p.x += (dx < 0 ? -1 : 1) * step
            if time >= p.until { p.state = "idle"; p.age = 0; p.until = time + 0.7 + random.unit() * 1.1 }; return
        }
        if time >= p.until { p.age = 0; if autoWalk { ensureRoute(p); p.state = "walk"; p.left = p.roamTarget < p.x; p.until = time + 18 + Double(random.int(13)) } else { p.state = "idle"; p.until = time + 2 } }
    }
    func playCues(_ key: String, before: Double, after: Double) { for c in catalog.cues[key] ?? [] where c.at > before && c.at <= after { onSound?(c.sound, time) } }
}
