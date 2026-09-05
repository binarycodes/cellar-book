import SwiftData
import SwiftUI

@main
struct VinnotaApp: App {
    @State private var auth = AuthController()

    /// The book starts empty — a new account has scanned nothing yet.
    ///
    /// A store that will not open must not brick the app permanently: the
    /// on-disk file is moved aside once and a fresh store is opened in its
    /// place. The damaged file is kept rather than deleted, so nothing is
    /// destroyed and it can still be recovered by hand.
    private let container: ModelContainer
    private let storeFailure: String?

    init() {
        Typo.registerFonts()

        let schema = Schema([Wine.self, TastingNote.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        if let opened = try? ModelContainer(for: schema, configurations: [config]) {
            container = opened
            storeFailure = nil
            return
        }

        Self.quarantineStore(at: config.url)

        if let recovered = try? ModelContainer(for: schema, configurations: [config]) {
            container = recovered
            storeFailure = "The cellar could not be opened and has been reset. "
                + "The previous file was kept alongside it."
            return
        }

        // Disk is unusable. An in-memory store keeps the app running for this
        // session instead of crash-looping on every launch.
        container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        storeFailure = "The cellar cannot be saved on this device right now. "
            + "Anything added this session will not be kept."
    }

    /// Renames the store and its SQLite sidecars out of the way.
    private static func quarantineStore(at url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-shm", "-wal"] {
            let from = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            let to = URL(fileURLWithPath: url.path + ".damaged-" + stamp + suffix)
            try? FileManager.default.moveItem(at: from, to: to)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailure: storeFailure)
                .environment(auth)
                .task { await auth.restore() }
        }
        .modelContainer(container)
    }
}
