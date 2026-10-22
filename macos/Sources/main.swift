import AppKit
import Darwin

let arguments = CommandLine.arguments
let resources = Bundle.main.resourceURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if arguments.count > 1 && arguments[1] == "--self-test" {
    do { try Tests.run(resources: resources, output: URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "macos-test")); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(1) }
}
let smoke = arguments.count > 1 && arguments[1] == "--smoke-test" ? URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "macos-smoke") : nil
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate(resources: resources, smokeOutput: smoke)
application.delegate = delegate
application.run()
