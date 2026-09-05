import CryptoKit
import Foundation
import Observation
import SwiftData

/// The cellar on disk, scoped to one account.
///
/// Every account gets its own store file. Isolation is by construction — a
/// signed-in account cannot reach another's bottles because the container it
/// holds is not attached to their file at all. The alternative, one shared
/// store filtered by an owner column, is one forgotten predicate away from
/// showing someone else's cellar; this codebase already has a guard that was
/// only skin deep (`canDelete`), so the weaker design was not worth the risk.
///
/// Signing out does not delete anything. The file stays exactly where it is and
/// is picked up again when that account signs back in.
@Observable
@MainActor
final class CellarStore {
    /// The container the view tree is currently bound to.
    private(set) var container: ModelContainer
    /// Set when the store had to be reset or could not be opened at all.
    private(set) var failure: String?
    /// Changes whenever the container does, so the view tree can be rebuilt and
    /// every `@Query` re-run against the new store rather than serving rows it
    /// already fetched from the previous account's.
    private(set) var identity: String

    private static let schema = Schema([Wine.self, TastingNote.self])

    /// Opens with no account attached: a signed-out app shows an empty cellar,
    /// not the last account's.
    init() {
        let opened = Self.open(for: nil)
        container = opened.container
        failure = opened.failure
        identity = Self.token(for: nil)
    }

    /// Points the app at `accountID`'s cellar, or at an empty one when signed
    /// out. A no-op when already on that account, so an unrelated auth change
    /// does not tear down the view tree.
    func open(for accountID: String?) {
        let wanted = Self.token(for: accountID)
        guard wanted != identity else { return }
        let opened = Self.open(for: accountID)
        container = opened.container
        failure = opened.failure
        identity = wanted
    }

    // MARK: - Naming

    /// A stable, filesystem-safe, non-reversible name for an account's store.
    ///
    /// Apple's user identifier is hashed rather than used directly: it is an
    /// account identifier, and it has no business sitting in a filename that
    /// shows up in backups, crash reports and file listings.
    static func token(for accountID: String?) -> String {
        guard let accountID, !accountID.isEmpty else { return "signed-out" }
        let digest = SHA256.hash(data: Data(accountID.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static func storeURL(for accountID: String) -> URL? {
        guard let dir = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true) else { return nil }
        return dir.appendingPathComponent("cellar-\(token(for: accountID)).store")
    }

    // MARK: - Opening

    private static func open(for accountID: String?) -> (container: ModelContainer, failure: String?) {
        // No account, or nowhere to write: keep everything in memory. Signed
        // out there is nothing to show, and nothing entered can leak to disk.
        guard let accountID, let url = storeURL(for: accountID) else {
            return (inMemory(), nil)
        }

        let config = ModelConfiguration(schema: schema, url: url)

        if let opened = try? ModelContainer(for: schema, configurations: [config]) {
            return (opened, nil)
        }

        // A store that will not open must not brick the app permanently. The
        // damaged file is moved aside rather than deleted, so nothing is
        // destroyed and it can still be recovered by hand.
        quarantineStore(at: url)

        if let recovered = try? ModelContainer(for: schema, configurations: [config]) {
            return (recovered, "The cellar could not be opened and has been reset. "
                    + "The previous file was kept alongside it.")
        }

        return (inMemory(), "The cellar cannot be saved on this device right now. "
                + "Anything added this session will not be kept.")
    }

    private static func inMemory() -> ModelContainer {
        // Force-try is deliberate: an in-memory store has no disk to fail on,
        // and there is no remaining fallback if the schema itself is invalid.
        try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    /// Renames the store and its SQLite sidecars out of the way.
    static func quarantineStore(at url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        for suffix in ["", "-shm", "-wal"] {
            let from = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            let to = URL(fileURLWithPath: url.path + ".damaged-" + stamp + suffix)
            try? FileManager.default.moveItem(at: from, to: to)
        }
    }
}

extension AuthController.State {
    /// The account whose cellar should be open, or nil when signed out.
    var accountID: String? {
        switch self {
        case .signedOut: return nil
        case .signedIn(let userID, _): return userID
        }
    }
}
