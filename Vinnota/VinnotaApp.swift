import SwiftData
import SwiftUI

@main
struct VinnotaApp: App {
    @State private var auth = AuthController()
    /// The cellar is opened per account — see `CellarStore`. It starts
    /// detached, so a launch that has not yet resolved a session shows nothing.
    @State private var store = CellarStore()

    init() {
        Typo.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailure: store.failure)
                .environment(auth)
                .modelContainer(store.container)
                // Rebuilds the tree when the account changes, so every `@Query`
                // re-runs against the new store rather than serving rows it
                // already fetched from the previous account's.
                .id(store.identity)
                .task { await auth.restore() }
                .onChange(of: auth.state) { _, new in
                    store.open(for: new.accountID)
                }
        }
    }
}
