import SwiftUI

#if os(iOS)

@main
struct AudioLivenessDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

#else

@main
enum AudioLivenessDemoStub {
    static func main() {
        print("AudioLivenessDemo requires iOS. Open Package.swift in Xcode and run on an iPhone simulator.")
    }
}

#endif
