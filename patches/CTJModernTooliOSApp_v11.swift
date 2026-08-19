import SwiftUI

@main
struct CTJModernTooliOSApp: App {
    @StateObject private var model = CTJModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.keyboard)
        }
    }
}
