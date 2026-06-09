import SwiftUI

@main
struct TueApp: App {
    @State private var store = HostStore()

    var body: some Scene {
        WindowGroup {
            HostDirectoryView()
                .environment(store)
        }
    }
}
