import AppKit

final class AudioPlayer {
    let root: URL; var sounds: [String: NSSound] = [:]; var last: NSSound?
    let defaults: UserDefaults?; var enabled = true, volume = 25
    var lastPlay = -100.0, accepted = 0
    init(root: URL, persist: Bool = true) {
        self.root = root; defaults = persist ? UserDefaults.standard : nil
        if let d = defaults { enabled = d.object(forKey: "soundEnabled") as? Bool ?? true; volume = max(0, min(100, d.object(forKey: "soundVolume") as? Int ?? 25)) }
    }
    func save() { defaults?.set(enabled, forKey: "soundEnabled"); defaults?.set(volume, forKey: "soundVolume") }
    func stop() { last?.stop() }
    func play(_ key: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, volume > 0, now - lastPlay >= 0.12 else { return }
        let sound: NSSound
        if let s = sounds[key] { sound = s } else {
            guard let s = NSSound(contentsOfFile: root.appendingPathComponent("sounds/\(key).wav").path, byReference: true) else { return }; sounds[key] = s; sound = s
        }
        last?.stop(); sound.volume = Float(volume) / 100; sound.currentTime = 0
        if sound.play() { accepted += 1; lastPlay = now; last = sound }
    }
}
final class MenuItem: NSMenuItem {
    let body: () -> Void
    init(_ title: String, checked: Bool? = nil, body: @escaping () -> Void) {
        self.body = body; super.init(title: title, action: #selector(invoke), keyEquivalent: ""); target = self
        if let checked { state = checked ? .on : .off }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc func invoke() { body() }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let resources: URL
    var engine: Engine!, art: SpriteStore!, audio: AudioPlayer!
    var lokiWindow: PetPanel!, thorWindow: PetPanel!, pairWindow: PetPanel!, soloWindow: PetPanel!
    var status: NSStatusItem!, timer: Timer?, lastTick = 0.0
    var currentContext: NSMenu?, menuOwner: Pet?
    let smokeOutput: URL?
    init(resources: URL, smokeOutput: URL?) { self.resources = resources; self.smokeOutput = smokeOutput }
    static func screens() -> [WorkArea] {
        NSScreen.screens.map { let r = $0.visibleFrame; return WorkArea(x: r.minX, y: -r.maxY, width: r.width, height: r.height) }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            if let id = Bundle.main.bundleIdentifier, NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
            let screens = Self.screens(); guard !screens.isEmpty else { throw SpriteStore.error("No screen is available.") }
            engine = Engine(catalog: try Catalog(resources: resources), areas: screens); art = try SpriteStore(root: resources); audio = AudioPlayer(root: resources, persist: smokeOutput == nil)
            if smokeOutput != nil { audio.enabled = false; engine.autoPair = false; engine.autoSolo = false }
            engine.onSound = { [weak self] key, _ in self?.audio.play(key) }
            lokiWindow = makeWindow(engine.loki); thorWindow = makeWindow(engine.thor)
            pairWindow = PetPanel(); soloWindow = PetPanel()
            pairWindow.spriteView.onClick = { [weak self] in self?.engine.cancelPair() }
            soloWindow.spriteView.onClick = { [weak self] in self?.engine.cancelSolo() }
            pairWindow.spriteView.onContext = { [weak self] e in self?.context(nil, event: e) }
            soloWindow.spriteView.onContext = { [weak self] e in self?.context(self?.engine.soloActor, event: e) }
            status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength); status.button?.title = "🐊🐸"; status.button?.toolTip = "洛基与雷神 · 点击打开设置和退出"
            status.menu = globalMenu(); status.menu?.delegate = self
            NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            lastTick = ProcessInfo.processInfo.systemUptime; try render()
            timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }; RunLoop.main.add(timer!, forMode: .common)
            if let output = smokeOutput { DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.finishSmoke(output) } }
        } catch { fail(error) }
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); audio?.stop(); if let s = status { NSStatusBar.system.removeStatusItem(s) } }
    @objc func screensChanged() { engine.updateAreas(Self.screens()) }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime; engine.step(min(0.25, now - lastTick)); lastTick = now
        do { try render() } catch { fail(error) }
    }
    func makeWindow(_ p: Pet) -> PetPanel {
        let window = PetPanel()
        window.spriteView.onBeginDrag = { [weak self] in self?.engine.beginDrag(p) }
        window.spriteView.onDrag = { [weak self] point in guard let e = self?.engine else { return }; p.x = point.x; p.ground = point.y + 120 * e.scale; e.clamp(p) }
        window.spriteView.onEndDrag = { [weak self] in self?.engine.endDrag(p) }
        window.spriteView.onClick = { [weak self] in self?.engine.click(p) }
        window.spriteView.onContext = { [weak self] e in self?.context(p, event: e) }; return window
    }
    func render() throws {
        let e = engine!
        if !e.pair.isEmpty && !e.gathering {
            lokiWindow.orderOut(nil); thorWindow.orderOut(nil); soloWindow.orderOut(nil)
            pairWindow.show(try actionFrame(e.pair, age: e.pairAge, catalog: e.catalog, art: art), at: e.stage, scale: e.scale); pairWindow.routePointer(held: e.loki.menuHeld || e.thor.menuHeld); return
        }
        pairWindow.orderOut(nil)
        if !e.solo.isEmpty && !e.soloGathering {
            soloWindow.show(try actionFrame(e.solo, age: e.soloAge, catalog: e.catalog, art: art), at: e.soloStage, scale: e.scale); soloWindow.routePointer(held: e.soloActor?.menuHeld ?? false)
        } else { soloWindow.orderOut(nil) }
        for p in e.pets {
            let w = p.frog ? thorWindow! : lokiWindow!
            if !e.solo.isEmpty && !e.soloGathering && p === e.soloActor { w.orderOut(nil) } else {
                w.show(try petFrame(p, art: art), at: Point(x: (p.x / 2).rounded() * 2, y: p.ground - 120 * e.scale), scale: e.scale); w.routePointer(held: p.dragging || p.menuHeld)
            }
        }
        if e.solo.isEmpty { art.releaseAtlas() }
    }
    func context(_ p: Pet?, event: NSEvent) {
        menuOwner = p; let m = p.map { petMenu($0) } ?? globalMenu(); currentContext = m; m.delegate = self
        let w = !engine.pair.isEmpty && !engine.gathering ? pairWindow! : !engine.solo.isEmpty && !engine.soloGathering ? soloWindow! : p?.frog == true ? thorWindow! : lokiWindow!
        NSMenu.popUpContextMenu(m, with: event, for: w.spriteView)
    }
    func menuWillOpen(_ menu: NSMenu) {
        if menu === status.menu { menuOwner = nil; menu.removeAllItems(); fillGlobal(menu) }
        if let p = menuOwner { p.menuHeld = true } else { for p in engine.pets { p.menuHeld = true } }
    }
    func menuDidClose(_ menu: NSMenu) { for p in engine.pets { p.menuHeld = false; p.until = max(p.until, engine.time + 1) }; menuOwner = nil }
    func add(_ menu: NSMenu, _ title: String, checked: Bool? = nil, body: @escaping () -> Void) { menu.addItem(MenuItem(title, checked: checked, body: body)) }
    func sub(_ menu: NSMenu, _ title: String, fill: (NSMenu) -> Void) { let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""), m = NSMenu(title: title); fill(m); item.submenu = m; menu.addItem(item) }
    func petMenu(_ p: Pet) -> NSMenu {
        let m = NSMenu(title: p.frog ? "青蛙雷神" : "鳄鱼洛基"); let title = NSMenuItem(title: m.title, action: nil, keyEquivalent: ""); title.isEnabled = false; m.addItem(title)
        sub(m, "我的单人动作") { n in for key in p.frog ? Catalog.thor : Catalog.loki { add(n, engine.catalog.actions[key]!.title) { self.engine.requestSolo(key) } } }
        sub(m, p.frog ? "去找弟弟互动" : "去找哥哥互动") { n in
            add(n, "随机互动（12 种等概率）") { self.engine.seek(p, kind: self.engine.choosePair()) }; n.addItem(.separator())
            for key in Catalog.pairs { add(n, engine.catalog.actions[key]!.title) { self.engine.seek(p, kind: key) } }
        }
        add(m, "睡觉 / 醒来") { self.engine.sleep(p) }; add(m, "转身") { self.engine.setRoamTarget(p, left: !p.left) }
        add(m, "回到屏幕下方") { self.engine.cancelSolo(); self.engine.cancelPair(); p.ground = self.engine.area(p).bottom; p.hasRoute = false; self.engine.clamp(p) }
        m.addItem(.separator()); sub(m, "全局设置") { fillGlobal($0, includePets: false) }; return m
    }
    func globalMenu() -> NSMenu { let m = NSMenu(title: "洛基与雷神"); fillGlobal(m); return m }
    func fillGlobal(_ m: NSMenu, includePets: Bool = true) {
        if includePets {
            for p in engine.pets { let item = NSMenuItem(title: p.frog ? "雷神动作与互动" : "洛基动作与互动", action: nil, keyEquivalent: ""); item.submenu = petMenu(p); m.addItem(item) }
        }
        add(m, "结束当前动作 / 寻找") { self.engine.cancelSolo(); self.engine.cancelPair() }
        add(m, "两只回到屏幕下方") { let p = NSEvent.mouseLocation; self.engine.reset(at: Point(x: p.x, y: -p.y)) }
        add(m, "各自自由移动", checked: engine.autoWalk) { self.engine.autoWalk.toggle(); if !self.engine.autoWalk { for p in self.engine.pets where p.state == "walk" && self.engine.pair.isEmpty && self.engine.solo.isEmpty { p.state = "idle" } } }
        add(m, "碰面后随机互动（各 1/12）", checked: engine.autoPair) { self.engine.autoPair.toggle(); self.engine.contactLatched = false }
        add(m, "每 3～5 分钟单人表演", checked: engine.autoSolo) { self.engine.autoSolo.toggle(); for p in self.engine.pets { self.engine.scheduleSolo(p) } }
        add(m, "播放像素音效", checked: audio.enabled) { self.audio.enabled.toggle(); if !self.audio.enabled { self.audio.stop() }; self.audio.save() }
        sub(m, "音量") { n in for value in [10,25,50,75,100] { add(n, "\(value)%", checked: audio.volume == value) { self.audio.volume = value; self.audio.enabled = true; self.audio.save(); self.audio.play("chime") } } }
        add(m, "试听：雷神蛙叫") { self.audio.play("croak") }
        add(m, "暂停", checked: engine.paused) { self.engine.paused.toggle(); if self.engine.paused { self.audio.stop() } }
        sub(m, "大小（自动适配当前屏幕）") { n in for value in 1...3 { add(n, "\(value) 倍", checked: engine.scale == Double(value)) { self.engine.setScale(Double(value)) } } }
        add(m, "操作说明") { let a = NSAlert(); a.messageText = "洛基与雷神 · Mac 预览版"; a.informativeText = "轻点角色可回应，按住拖动会拎起。\n两指点按触控板、鼠标右键或按住 Control 点击角色，可选择动作与设置。\n菜单栏 🐊🐸 图标可调声音、暂停和退出。\n两只独立巡游，碰面后随机互动；3～5 分钟未碰面时可单人表演。\n程序不联网，不需要辅助功能或屏幕录制权限。"; a.runModal() }
        m.addItem(.separator()); add(m, "退出桌宠") { NSApp.terminate(nil) }
    }
    func finishSmoke(_ folder: URL) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try lokiWindow.spriteView.exportPNG(folder.appendingPathComponent("loki-window.png")); try thorWindow.spriteView.exportPNG(folder.appendingPathComponent("thor-window.png"))
            guard lokiWindow.isVisible, thorWindow.isVisible, !lokiWindow.isOpaque, !thorWindow.isOpaque, engine.ticks > 30, lokiWindow.canBecomeKey == false else { throw SpriteStore.error("Native panel smoke check failed.") }
            let text = "PASS: four nonactivating transparent Cocoa panels created; two independent pets visible; timer ticks=\(engine.ticks); own views rendered to PNG. Audio muted for CI.\n"
            try text.write(to: folder.appendingPathComponent("startup-check.txt"), atomically: true, encoding: .utf8); NSApp.terminate(nil)
        } catch { fail(error) }
    }
    func fail(_ error: Error) {
        fputs("\(error)\n", stderr)
        if smokeOutput != nil { exit(1) }
        let a = NSAlert(); a.messageText = "桌宠启动失败"; a.informativeText = error.localizedDescription; a.runModal(); NSApp.terminate(nil)
    }
}
