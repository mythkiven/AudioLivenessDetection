import Foundation

enum LivenessLogger {
    static var isEnabled = true

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[AudioLiveness] \(message())")
    }
}
