import AuthenticationServices
import Foundation
import ObjectiveC
import Security
import Testing
import UIKit

@testable import Vinnota

// MARK: - The storage contract, restated

/// `AuthController` keeps every one of these private, which is right for the
/// app and useless for a test: an assertion against `auth.displayName` proves
/// only that a getter agrees with its own setter. These literals are the real
/// on-disk contract — the keychain account, the two `UserDefaults` keys, the
/// avatar's filename, and the user ID that marks a session as stubbed — so the
/// tests below read and write *storage* and let the controller observe it.
///
/// A change to any of them is a migration: the old values keep living on the
/// device, and these tests are meant to fail when that happens.
private enum Storage {
    static let keychainAccount = "com.vinnota.appleUserID"
    static let stubUserID = "stub.local.account"
    static let nameKey = "com.vinnota.displayName"
    static let emailKey = "com.vinnota.email"
    static let avatarFilename = "avatar.jpg"

    static var avatarURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent(avatarFilename)
    }
}

// MARK: - Keychain, driven directly

/// The same generic-password item `AuthController` writes, reached from the
/// outside. Planting a value here is how "a previous launch left a session
/// behind" is simulated without going through Apple's UI.
private func keychainWrite(_ value: String) {
    keychainDelete()
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: Storage.keychainAccount,
        kSecValueData as String: Data(value.utf8),
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
    ]
    SecItemAdd(query as CFDictionary, nil)
}

private func keychainRead() -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: Storage.keychainAccount,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

private func keychainDelete() {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: Storage.keychainAccount,
    ]
    SecItemDelete(query as CFDictionary)
}

/// Whether this build can use the keychain at all.
///
/// `xcodebuild … CODE_SIGNING_ALLOWED=NO` — what CI runs, and what the command
/// in TESTING.md runs — produces an unsigned application. An unsigned process
/// has no `application-identifier` entitlement, and the simulator keychain
/// answers every request from one with `errSecMissingEntitlement` (-34018).
/// `AuthController`'s own `SecItemAdd` fails there too, silently: it ignores
/// the status, so in this configuration the app signs in and then forgets the
/// session at the next launch.
///
/// The tests that need a working keychain therefore say so and are skipped
/// rather than passing vacuously against a store that swallows everything.
/// Run the suite from Xcode, or with signing enabled, to exercise them.
private let keychainAvailable: Bool = {
    // A private account name, so probing can never disturb the app's item.
    let account = "com.vinnota.tests.keychainProbe"
    let base: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrAccount as String: account,
    ]
    SecItemDelete(base as CFDictionary)
    var add = base
    add[kSecValueData as String] = Data("probe".utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(add as CFDictionary, nil)
    SecItemDelete(base as CFDictionary)
    return status == errSecSuccess
}()

private let keychainSkipReason = Comment(
    rawValue: "the keychain refuses unsigned builds with errSecMissingEntitlement; "
        + "build with code signing enabled to exercise session persistence")

/// Establishes a local session the way the app does.
///
/// In DEBUG that is the stub itself. The stub does not exist in a Release
/// compile, so the credential is planted directly there — which keeps this
/// file compiling in both configurations, as the app target does.
@MainActor
private func establishLocalSession(_ auth: AuthController) {
    #if DEBUG
    auth.signInStubbed()
    #else
    keychainWrite(Storage.stubUserID)
    #endif
}

// MARK: - Global state, saved and put back

/// Everything below writes the real `UserDefaults`, the real keychain and a
/// real file in Application Support — the same ones the running app uses. Each
/// test starts from a clean slate and hands back exactly what it found.
@MainActor
private func withCleanAuthState(_ body: () async throws -> Void) async throws {
    let defaults = UserDefaults.standard
    let savedName = defaults.object(forKey: Storage.nameKey)
    let savedEmail = defaults.object(forKey: Storage.emailKey)
    let savedSession = keychainRead()
    let savedAvatar = Storage.avatarURL.flatMap { try? Data(contentsOf: $0) }

    defaults.removeObject(forKey: Storage.nameKey)
    defaults.removeObject(forKey: Storage.emailKey)
    keychainDelete()
    if let url = Storage.avatarURL { try? FileManager.default.removeItem(at: url) }

    defer {
        if let savedName { defaults.set(savedName, forKey: Storage.nameKey) }
        else { defaults.removeObject(forKey: Storage.nameKey) }
        if let savedEmail { defaults.set(savedEmail, forKey: Storage.emailKey) }
        else { defaults.removeObject(forKey: Storage.emailKey) }

        if let savedSession { keychainWrite(savedSession) } else { keychainDelete() }

        if let url = Storage.avatarURL {
            if let savedAvatar { try? savedAvatar.write(to: url, options: .atomic) }
            else { try? FileManager.default.removeItem(at: url) }
        }
    }

    try await body()
}

// MARK: - Image fixtures

/// A JPEG at a known pixel size, drawn at scale 1 so its pixel dimensions and
/// its point dimensions are the same number. A renderer left on the device's
/// default scale would make every size assertion below three times ambiguous.
@MainActor
private func jpegFixture(_ width: Int, _ height: Int) -> Data {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let size = CGSize(width: width, height: height)
    let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
        UIColor.systemPink.setFill()
        ctx.fill(CGRect(origin: .zero, size: size))
        // Structure, so a mangled or truncated file is not mistaken for a
        // successful round trip.
        UIColor.systemBlue.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    }
    return image.jpegData(compressionQuality: 1.0) ?? Data()
}

/// The scale `AuthController.downscale` renders at — it builds a
/// `UIGraphicsImageRenderer` with no format, so it inherits the device's.
@MainActor
private var rendererScale: CGFloat { UIGraphicsImageRendererFormat.default().scale }

// MARK: - The app bundle, as shipped

/// The host application, not the test bundle. `AuthController` is compiled into
/// the app, so the bundle that contains it is the one that ships.
private var appBundle: Bundle { Bundle(for: AuthController.self) }

// MARK: - Output capture

/// Runs `body` with `stdout` and `stderr` pointed at a file, and returns what
/// was written. Used to assert a credential never reaches the console — the
/// app has no logger at all, and this is what keeps it that way.
@MainActor
private func capturingConsole(_ body: () async -> Void) async -> String {
    let path = NSTemporaryDirectory() + "auth-console-\(UUID().uuidString).log"
    FileManager.default.createFile(atPath: path, contents: nil)
    guard let sink = FileHandle(forWritingAtPath: path) else {
        await body()
        return ""
    }
    let savedOut = dup(STDOUT_FILENO)
    let savedErr = dup(STDERR_FILENO)
    dup2(sink.fileDescriptor, STDOUT_FILENO)
    dup2(sink.fileDescriptor, STDERR_FILENO)

    defer {
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        close(savedOut)
        close(savedErr)
        try? sink.close()
        try? FileManager.default.removeItem(atPath: path)
    }

    await body()

    fflush(stdout)
    fflush(stderr)
    return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
}

// MARK: - The debug stub

/// The app once shipped a sign-in stub that let anyone past authentication.
/// It now lives behind `#if DEBUG`, and CI greps the Release binary for its
/// symbol. Tests compile in DEBUG, so the stub is *present here* — which is
/// the only configuration in which its blast radius can actually be measured.
@Suite("Debug sign-in stub · blast radius", .serialized)
@MainActor
struct DebugStubTests {

    @Test("The keychain answers, so every keychain assertion below means something",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func keychainWorks() async throws {
        try await withCleanAuthState {
            // Without this, `keychainRead()` would return nil everywhere and
            // half of this file would pass by accident.
            let probe = "keychain-probe-\(UUID().uuidString)"
            keychainWrite(probe)
            #expect(keychainRead() == probe)
            keychainDelete()
            #expect(keychainRead() == nil)
        }
    }

    #if DEBUG
    @Test("The stub signs in with no credential at all, and says so in the state")
    func stubSignsInWithoutACredential() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            #expect(auth.state == .signedOut)

            auth.signInStubbed()

            // The whole blast radius, stated exactly: a session exists, it is
            // the one fixed local user ID, and it is flagged as not real.
            #expect(auth.state == .signedIn(userID: Storage.stubUserID, stubbed: true))
            #expect(auth.isStubbedSession)
            // It invents no identity — a stub account is nameless.
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(auth.avatar == nil)
        }
    }

    @Test("The stub writes its fixed user ID to the same keychain item a real session uses",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func stubPersistsToTheKeychain() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.signInStubbed()

            // This is the discriminator the release build keys off. It is a
            // constant, not a random or per-device value, so a release build
            // can recognise a stub left behind by a dev build with certainty.
            #expect(keychainRead() == Storage.stubUserID)
        }
    }

    @Test("Signing out destroys the stub session rather than hiding it",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func signOutDestroysTheStub() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.signInStubbed()
            #expect(keychainRead() == Storage.stubUserID)

            auth.signOut()

            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
            #expect(keychainRead() == nil)

            // And a fresh launch does not find it again.
            let relaunched = AuthController()
            await relaunched.restore()
            #expect(relaunched.state == .signedOut)
        }
    }
    #endif

    @Test("A stubbed session and a real session with the same user ID are not equal")
    func theStubbedFlagIsPartOfTheSessionIdentity() {
        let stubbed = AuthController.State.signedIn(userID: Storage.stubUserID, stubbed: true)
        let real = AuthController.State.signedIn(userID: Storage.stubUserID, stubbed: false)
        // `AccountSheet` shows its "local account on this device only" warning
        // off this flag. If equality ignored it, a stub could be assigned over
        // a real session, or the reverse, without the UI noticing.
        #expect(stubbed != real)
        #expect(stubbed != .signedOut)
        #expect(real != .signedOut)
    }

    /// **The Release rejection branch is NOT covered by this suite.**
    ///
    /// `AuthController.restore()` handles a stub credential in two arms of an
    /// `#if DEBUG` (AuthController.swift:111-120). Test bundles compile in
    /// DEBUG, so only the DEBUG arm is ever built here — the `#else` arm that
    /// destroys a stale stub in a shipped build is not merely unasserted, it is
    /// not compiled. Confirmed by mutation: replacing that arm's
    /// `deleteKeychain(); state = .signedOut` with
    /// `state = .signedIn(userID: stored, stubbed: true)` — a shipped build
    /// admitting a dev build's session with no credential at all — leaves the
    /// whole 302-test run green.
    ///
    /// The `#else` block below is therefore a latent assertion, correct but
    /// unreachable under `xcodebuild test`. What actually guards the release
    /// build today is CI's `nm | grep signInStubbed` check, and
    /// `theCIGuardStillHasSomethingToFind` below keeps that grep's needle
    /// honest. Closing the gap properly means running this target against a
    /// Release compile of the app; until then the name of this test claims
    /// only what a DEBUG run really proves.
    @Test("A stale stub credential is restored as a live session in DEBUG (Release arm not compiled here)",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func stubSessionAtLaunch() async throws {
        try await withCleanAuthState {
            // A stale stub left behind by a development build.
            keychainWrite(Storage.stubUserID)

            let auth = AuthController()
            await auth.restore()

            #if DEBUG
            // Compiled here: the stub is a persistent session, not merely an
            // in-memory convenience. That is its blast radius — it outlives
            // the process that created it.
            #expect(auth.state == .signedIn(userID: Storage.stubUserID, stubbed: true))
            #expect(auth.isStubbedSession)
            #expect(keychainRead() == Storage.stubUserID)
            #else
            // The release path. Rejection alone is not enough: the stored
            // credential has to be destroyed, or the next launch meets it
            // again. Never reached by a standard test run — see above.
            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
            #expect(keychainRead() == nil)
            #endif
        }
    }

    @Test("A near-miss of the stub user ID is not treated as a stub in any configuration",
          .enabled(if: keychainAvailable, keychainSkipReason),
          arguments: ["Stub.Local.Account",
                      "stub.local.account ",
                      " stub.local.account",
                      "stub.local.accounts",
                      "stub.local.accoun",
                      "xstub.local.account",
                      "stub·local·account"])
    func theStubIsMatchedExactly(_ planted: String) async throws {
        try await withCleanAuthState {
            keychainWrite(planted)

            let auth = AuthController()
            await auth.restore()

            // The comparison is `==`, not a prefix or a case-insensitive
            // match. Anything that is not exactly the stub goes down the real
            // path, where an unverifiable ID is rejected — so the answer is
            // the same in Debug and in Release.
            #expect(auth.isStubbedSession == false)
            #expect(auth.state == .signedOut)
            #expect(keychainRead() == nil)
        }
    }

    @Test("An unverifiable Apple user ID is rejected and its credential destroyed",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func revokedCredentialIsNotTrusted() async throws {
        try await withCleanAuthState {
            // Shaped like a real Apple ID, belonging to nobody.
            keychainWrite("001234.9f8e7d6c5b4a39281706abcdef012345.1122")

            let auth = AuthController()
            await auth.restore()

            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
            // `credentialState` is read through `try?`, so a thrown error and
            // a genuine revocation land in the same branch. It fails closed,
            // which is the safe direction — worth knowing that it also means
            // a transient failure of the authorization daemon signs the user
            // out for good rather than for one launch.
            #expect(keychainRead() == nil)
        }
    }

    @Test("The symbol CI greps for in Release is present in this Debug build")
    func theCIGuardStillHasSomethingToFind() throws {
        // `.github/workflows/ci.yml` fails the Release build when
        // `nm -a <binary> | grep signInStubbed` matches. That guard is only
        // meaningful while the name it looks for is the name the stub has:
        // rename the method and the grep passes forever, silently.
        //
        // The image is asked for by way of the runtime rather than taken as
        // `Bundle.executableURL`, because Xcode 16 splits a Debug build into a
        // 40 KB launcher and a `Vinnota.debug.dylib` holding all of the code.
        // A Release build has no such split, which is why CI's simpler lookup
        // is right for the binary it inspects.
        let image = try #require(class_getImageName(AuthController.self))
        let path = String(cString: image)
        let binary = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        let present = binary.range(of: Data("signInStubbed".utf8)) != nil

        #if DEBUG
        #expect(present, "CI's Release guard greps for a symbol that no longer exists")
        #else
        #expect(present == false, "the debug sign-in stub leaked into a Release build")
        #endif
    }

    @Test("FINDING (medium): rejecting a session at launch leaves the identity and photo on disk",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func rejectedSessionLeavesResidualIdentity() async throws {
        try await withCleanAuthState {
            // A previous session's leavings: name, email, profile photograph.
            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey)
            let seeder = AuthController()
            seeder.setAvatar(jpegFixture(200, 200))
            let avatarURL = try #require(Storage.avatarURL)
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))

            // The credential is no longer good, so launch throws the session
            // out. This is the same branch a Release build takes when it finds
            // a stub session left behind by a dev build.
            keychainWrite("001234.9f8e7d6c5b4a39281706abcdef012345.1122")
            let auth = AuthController()
            await auth.restore()

            #expect(auth.state == .signedOut)
            #expect(keychainRead() == nil)

            // FINDING (medium): AuthController.swift:126-129 (the `default:`
            // branch of `restore()`) and :114-118 (the Release stub branch)
            // both delete the keychain item and return; neither calls
            // `signOut()`. So the display name, the email address and the
            // profile photograph outlive the session that produced them.
            // In the shipped app: a device that ran a dev build and is then
            // given a Release build shows the login screen while the dev
            // account's email and photo are still on disk — and `restore()`
            // has already loaded that photo into memory, because
            // `loadAvatar()` runs at :108 before the session is checked at
            // all. Asserted here as it is, not as it should be.
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey) == "Marie Kondo")
            #expect(UserDefaults.standard.string(forKey: Storage.emailKey) == "marie@example.com")
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))
            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
            #expect(auth.avatar != nil, "restore() loads the avatar before it checks the session")
        }
    }
}

// MARK: - Session persistence

@Suite("Session persistence · what is stored and what sign-out clears", .serialized)
@MainActor
struct SessionPersistenceTests {

    @Test("displayName and email read the documented UserDefaults keys, not some other pair")
    func identityIsReadFromTheDocumentedKeys() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)

            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey)

            // Written to storage from outside, read back through the app.
            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
        }
    }

    @Test("The identity is not held in memory — a second controller sees the same values")
    func identityIsSharedThroughStorage() async throws {
        try await withCleanAuthState {
            UserDefaults.standard.set("Jean Peridot", forKey: Storage.nameKey)
            UserDefaults.standard.set("jean@example.com", forKey: Storage.emailKey)

            let first = AuthController()
            let second = AuthController()
            #expect(first.displayName == second.displayName)
            #expect(first.email == second.email)
            #expect(second.email == "jean@example.com")
        }
    }

    @Test("Sign-out clears the name, the email and the avatar from storage")
    func signOutClearsTheIdentityAndThePicture() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey)
            auth.setAvatar(jpegFixture(300, 300))

            let avatarURL = try #require(Storage.avatarURL)
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))

            auth.signOut()

            // In memory.
            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(auth.avatar == nil)

            // And — the part that actually matters — in storage. A residual
            // credential after sign-out is the defect being looked for here.
            #expect(UserDefaults.standard.object(forKey: Storage.nameKey) == nil)
            #expect(UserDefaults.standard.object(forKey: Storage.emailKey) == nil)
            #expect(FileManager.default.fileExists(atPath: avatarURL.path) == false)
        }
    }

    @Test("Sign-out destroys the stored session as well",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func signOutClearsTheStoredSession() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            #expect(keychainRead() != nil)

            auth.signOut()
            #expect(keychainRead() == nil)
        }
    }

    @Test("Sign-out reaches the preferences store, not only the in-process cache")
    func signOutReachesThePreferencesStore() async throws {
        try await withCleanAuthState {
            let key = Storage.emailKey as CFString
            let address = "marie.kondo.private@example.com"

            let auth = AuthController()
            establishLocalSession(auth)
            UserDefaults.standard.set(address, forKey: Storage.emailKey)
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)

            // `CFPreferencesCopyAppValue` goes to the preferences daemon, so
            // it sees what was actually persisted rather than what
            // `UserDefaults` is holding in this process. (The .plist on disk
            // is not usable for this: cfprefsd writes it back on its own
            // schedule, and it is still 42 bytes long moments after a write.)
            // The precondition is an assertion too — if the address never
            // reached the store, the check after sign-out would prove nothing.
            let before = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? String
            #expect(before == address, "the email is persisted in the clear, unencrypted")

            auth.signOut()
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)

            let after = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? String
            #expect(after == nil, "the address outlives sign-out in the preferences store")
        }
    }

    @Test("Signing out twice is harmless and leaves nothing behind the second time")
    func signOutIsIdempotent() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            auth.signOut()
            auth.signOut()

            #expect(auth.state == .signedOut)
            #expect(keychainRead() == nil)
            #expect(auth.avatar == nil)
        }
    }

    @Test("Signing out with nothing stored does not crash")
    func signOutFromASignedOutStateIsSafe() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.signOut()
            #expect(auth.state == .signedOut)
            #expect(keychainRead() == nil)
        }
    }

    @Test("After sign-out a fresh launch finds no session")
    func noResidualSessionAfterSignOut() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            auth.setAvatar(jpegFixture(150, 150))
            auth.signOut()

            let relaunched = AuthController()
            await relaunched.restore()
            #expect(relaunched.state == .signedOut)
            #expect(relaunched.isStubbedSession == false)
            #expect(relaunched.avatar == nil)
            #expect(relaunched.displayName == nil)
            #expect(relaunched.email == nil)
        }
    }

    @Test("A launch with an empty keychain stays signed out")
    func launchWithNoStoredSession() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            await auth.restore()
            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
        }
    }

    @Test("A keychain item holding non-UTF8 bytes is ignored rather than trusted",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func corruptKeychainPayloadIsNotASession() async throws {
        try await withCleanAuthState {
            keychainDelete()
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: Storage.keychainAccount,
                kSecValueData as String: Data([0xFF, 0xFE, 0x00, 0x80, 0x81]),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            ]
            SecItemAdd(query as CFDictionary, nil)

            let auth = AuthController()
            await auth.restore()

            // Undecodable bytes read as no stored ID at all, so `restore()`
            // returns early and the session stays closed.
            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
        }
    }
}

// MARK: - Credential handling

@Suite("Credential handling · Apple's one-shot name and email", .serialized)
@MainActor
struct CredentialHandlingTests {

    @Test("A stored identity survives a later sign-in that carries no name or email")
    func aLaterSignInDoesNotWipeTheStoredIdentity() async throws {
        try await withCleanAuthState {
            // The first authorization: Apple hands the name and email over
            // once, and they are written to storage at that one opportunity.
            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey)

            // Every later sign-in arrives with both fields nil. The identity
            // must not be cleared to match, or a returning user is nameless
            // forever — Apple never offers those fields again.
            let auth = AuthController()
            establishLocalSession(auth)

            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey) == "Marie Kondo")
            #expect(UserDefaults.standard.string(forKey: Storage.emailKey) == "marie@example.com")
        }
    }

    @Test("A relaunch does not disturb the stored identity either")
    func restoreDoesNotWipeTheStoredIdentity() async throws {
        try await withCleanAuthState {
            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey)
            keychainWrite(Storage.stubUserID)

            let auth = AuthController()
            await auth.restore()

            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
        }
    }

    @Test("Half an identity is kept as half, not discarded")
    func nameWithoutEmailIsStillAName() async throws {
        try await withCleanAuthState {
            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)

            let auth = AuthController()
            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == nil)
            // `AccountSheet.identityIsPartial` turns exactly this into the
            // "Apple shares a name and email only the first time" line.
            #expect(auth.isStubbedSession == false)
        }
    }

    @Test("An email without a name is kept too")
    func emailWithoutNameIsStillAnEmail() async throws {
        try await withCleanAuthState {
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey)

            let auth = AuthController()
            #expect(auth.email == "marie@example.com")
            #expect(auth.displayName == nil)
            #expect(auth.initials == nil)
        }
    }

    @Test("A Hide-My-Email relay address is stored verbatim")
    func relayAddressIsNotRewritten() async throws {
        try await withCleanAuthState {
            let relay = "a1b2c3d4e5@privaterelay.appleid.com"
            UserDefaults.standard.set(relay, forKey: Storage.emailKey)
            #expect(AuthController().email == relay)
        }
    }

    @Test("No credential, name, email or user ID reaches the console")
    func nothingSensitiveIsLogged() async throws {
        try await withCleanAuthState {
            let secrets = ["Marie Kondo", "marie.secret@example.com", Storage.stubUserID]
            let picture = jpegFixture(120, 120)

            let output = await capturingConsole {
                let auth = AuthController()
                UserDefaults.standard.set(secrets[0], forKey: Storage.nameKey)
                UserDefaults.standard.set(secrets[1], forKey: Storage.emailKey)
                establishLocalSession(auth)
                auth.setAvatar(picture)
                await auth.restore()
                _ = auth.initials
                _ = auth.displayName
                _ = auth.email
                auth.signOut()
            }

            for secret in secrets {
                #expect(output.contains(secret) == false,
                        "a credential detail was written to stdout or stderr")
            }
        }
    }
}

// MARK: - Avatar storage

@Suite("Avatar storage · where it lives and how it fails", .serialized)
@MainActor
struct AvatarStorageTests {

    @Test("The picture is written to Application Support, beside the session")
    func avatarLivesInApplicationSupport() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(300, 200))

            let url = try #require(Storage.avatarURL)
            #expect(url.lastPathComponent == "avatar.jpg")
            #expect(url.path.contains("/Library/Application Support"))
            // Not Caches, which the system may evict, and not Documents,
            // which is user-visible through the Files app.
            #expect(url.path.contains("/Caches/") == false)
            #expect(url.path.contains("/Documents/") == false)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(auth.avatar != nil)
        }
    }

    @Test("A stored picture is loaded again on the next launch")
    func avatarSurvivesRelaunch() async throws {
        try await withCleanAuthState {
            AuthController().setAvatar(jpegFixture(300, 200))

            let relaunched = AuthController()
            #expect(relaunched.avatar == nil, "nothing is read until loadAvatar runs")
            relaunched.loadAvatar()
            #expect(relaunched.avatar != nil)

            // And `restore()` is what calls it in the app.
            let launched = AuthController()
            await launched.restore()
            #expect(launched.avatar != nil)
        }
    }

    @Test("An oversized picture is downscaled before it is kept in memory")
    func oversizedPictureIsDownscaledInMemory() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(1024, 768))

            let image = try #require(auth.avatar)
            #expect(image.size.width == 512)
            #expect(image.size.height == 384)  // the aspect ratio is preserved
        }
    }

    @Test("A picture already smaller than the cap is stored untouched")
    func smallPictureIsNotUpscaled() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(100, 80))

            let image = try #require(auth.avatar)
            #expect(image.size.width == 100)
            #expect(image.size.height == 80)
        }
    }

    @Test("FINDING (low): the file on disk is the device scale larger than the 512pt cap")
    func writtenFileIsLargerThanTheCapSuggests() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(1024, 768))

            let url = try #require(Storage.avatarURL)
            let data = try Data(contentsOf: url)
            let written = try #require(UIImage(data: data))

            // FINDING (low): AuthController.swift:88 — `downscale` renders
            // through a `UIGraphicsImageRenderer` with no explicit format, so
            // it inherits the device scale. `scaled.size` is 512pt as
            // intended, but `jpegData` writes 512 × scale *pixels*: 1536 px on
            // a 3x phone, nine times the pixel count the comment at :68-69
            // sets out to avoid. Visually harmless; the file is simply much
            // bigger than the code says it is. A format with `scale = 1`
            // would fix it.
            #expect(written.size.width == 512 * rendererScale)
            if rendererScale > 1 {
                #expect(written.size.width > 512)
                #expect(data.count > 0)
            }
        }
    }

    @Test("A file that is not an image loads as no avatar instead of crashing",
          arguments: ["not an image at all",
                      "<?xml version=\"1.0\"?><plist/>",
                      "\u{0}\u{1}\u{2}\u{3}",
                      "GIF89a"])
    func corruptAvatarFileLoadsAsNil(_ junk: String) async throws {
        try await withCleanAuthState {
            let url = try #require(Storage.avatarURL)
            try Data(junk.utf8).write(to: url, options: .atomic)

            let auth = AuthController()
            auth.loadAvatar()
            #expect(auth.avatar == nil)

            // And the launch path walks over it without trouble either.
            await auth.restore()
            #expect(auth.avatar == nil)
        }
    }

    @Test("A truncated JPEG does not crash the loader")
    func truncatedJpegIsSurvivable() async throws {
        try await withCleanAuthState {
            let full = jpegFixture(400, 400)
            let url = try #require(Storage.avatarURL)
            try full.prefix(full.count / 3).write(to: url, options: .atomic)

            let auth = AuthController()
            auth.loadAvatar()
            // UIImage may decode a partial JPEG or refuse it — either is
            // acceptable, a crash is not. Whichever it does, it must do it
            // consistently: a loader that returned an image once and nil the
            // next time would make the header avatar flicker between a picture
            // and a placeholder across launches.
            let first = auth.avatar != nil
            let second = AuthController()
            second.loadAvatar()
            #expect((second.avatar != nil) == first)

            // The truncated file is really there — otherwise the removal
            // assertion below would pass against nothing.
            #expect(FileManager.default.fileExists(atPath: url.path))
            auth.clearAvatar()
            #expect(auth.avatar == nil)
            #expect(FileManager.default.fileExists(atPath: url.path) == false)
        }
    }

    @Test("An empty avatar file loads as no avatar")
    func emptyAvatarFileIsNil() async throws {
        try await withCleanAuthState {
            let url = try #require(Storage.avatarURL)
            try Data().write(to: url, options: .atomic)

            let auth = AuthController()
            auth.loadAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("Loading with no file at all is not an error")
    func missingAvatarFileIsNil() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.loadAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("Setting a non-image keeps the picture that was already there")
    func settingJunkDoesNotDestroyTheStoredPicture() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(200, 200))
            let url = try #require(Storage.avatarURL)
            let good = try Data(contentsOf: url)

            auth.setAvatar(Data("this is not a picture".utf8))
            auth.setAvatar(Data())

            // Nothing was written, so the previous picture is intact. The
            // failure is silent, which is a UI question rather than a
            // security one.
            #expect(try Data(contentsOf: url) == good)
            #expect(auth.avatar != nil)
        }
    }

    @Test("Clearing removes the file, and clearing again is harmless")
    func clearAvatarDeletesTheFile() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(200, 200))
            let url = try #require(Storage.avatarURL)
            #expect(FileManager.default.fileExists(atPath: url.path))

            auth.clearAvatar()
            #expect(auth.avatar == nil)
            #expect(FileManager.default.fileExists(atPath: url.path) == false)

            auth.clearAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("Replacing a picture leaves one file, holding the newer image")
    func replacingAPictureOverwritesInPlace() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            auth.setAvatar(jpegFixture(200, 200))
            auth.setAvatar(jpegFixture(400, 100))

            let url = try #require(Storage.avatarURL)
            let stored = try #require(UIImage(data: try Data(contentsOf: url)))
            #expect(stored.size.width > stored.size.height, "the second picture is the wide one")

            let directory = url.deletingLastPathComponent()
            let jpegs = try FileManager.default
                .contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasSuffix(".jpg") }
                .sorted()
            #expect(jpegs == ["avatar.jpg"], "no orphaned copies accumulate")
        }
    }
}

// MARK: - Initials

/// `initials` renders inside `AvatarView`, on the header and on the account
/// sheet. A trap here is a crash on a screen the user reaches by tapping their
/// own face, so the inputs below are deliberately unpleasant.
@Suite("Initials · derived from whatever name is on file", .serialized)
@MainActor
struct InitialsTests {

    private func initials(for name: String?) -> String? {
        if let name { UserDefaults.standard.set(name, forKey: Storage.nameKey) }
        else { UserDefaults.standard.removeObject(forKey: Storage.nameKey) }
        return AuthController().initials
    }

    @Test("Two names give two letters, uppercased")
    func twoNames() async throws {
        try await withCleanAuthState {
            #expect(initials(for: "Marie Kondo") == "MK")
            #expect(initials(for: "marie kondo") == "MK")
        }
    }

    @Test("A single name gives one letter")
    func singleName() async throws {
        try await withCleanAuthState {
            #expect(initials(for: "Marie") == "M")
            #expect(initials(for: "x") == "X")
        }
    }

    @Test("More than two names still give two letters — the first two")
    func manyNames() async throws {
        try await withCleanAuthState {
            #expect(initials(for: "Jean Baptiste Grenouille de la Fontaine") == "JB")
            #expect(initials(for: "a b c d e f g h") == "AB")
        }
    }

    @Test("Runs of spaces do not produce empty initials")
    func repeatedAndSurroundingSpaces() async throws {
        try await withCleanAuthState {
            #expect(initials(for: "Marie  Kondo") == "MK")
            #expect(initials(for: " Marie Kondo") == "MK")
            #expect(initials(for: "Marie Kondo ") == "MK")
            #expect(initials(for: "   Marie   Kondo   ") == "MK")
        }
    }

    @Test("No name on file means no initials, never invented ones")
    func noName() async throws {
        try await withCleanAuthState {
            // The design's "MK" was a mockup literal; a real nameless account
            // gets the neutral person symbol instead.
            #expect(initials(for: nil) == nil)
            #expect(initials(for: "") == nil)
            #expect(initials(for: " ") == nil)
            #expect(initials(for: "          ") == nil)
        }
    }

    @Test("Non-Latin scripts come through as their own letters",
          arguments: zip(["Ольга Смирнова", "梅田 由紀", "김 민준",
                          "Δημήτρης Παπαδόπουλος", "אורי לוי",
                          "Ünsal Çetin", "Ægir Þórsson"],
                         ["ОС", "梅由", "김민", "ΔΠ", "אל", "ÜÇ", "ÆÞ"]))
    func nonLatinNames(_ name: String, _ expected: String) async throws {
        try await withCleanAuthState {
            #expect(initials(for: name) == expected)
        }
    }

    @Test("Right-to-left text yields two characters and does not trap")
    func arabicName() async throws {
        try await withCleanAuthState {
            // Not a rendering claim — only that two characters come out and
            // nothing traps on the bidi run.
            #expect(initials(for: "أحمد الحسن")?.count == 2)
        }
    }

    @Test("Emoji and combining sequences do not crash and stay one grapheme each",
          arguments: ["🍇 Vigneron",
                      "👨‍👩‍👧‍👦 Family",
                      "🇫🇷 Domaine",
                      "e\u{0301}mile Peynaud",
                      "🍷🍇 🥂"])
    func emojiNames(_ name: String) async throws {
        try await withCleanAuthState {
            let result = initials(for: name)
            #expect(result != nil)
            #expect((result?.count ?? 0) <= 2, "at most one grapheme per name part")
        }
    }

    @Test("A very long name is still two letters and does not hang")
    func absurdlyLongName() async throws {
        try await withCleanAuthState {
            #expect(initials(for: String(repeating: "Chateau ", count: 5_000)) == "CC")
            #expect(initials(for: String(repeating: "x", count: 10_000)) == "X")
        }
    }

    @Test("FINDING (low): whitespace that is not an ASCII space becomes an invisible initial",
          arguments: ["\t", "\n", "\u{00A0}", "\u{2007}", "\t\n"])
    func nonAsciiWhitespaceProducesABlankInitial(_ name: String) async throws {
        try await withCleanAuthState {
            // FINDING (low): AuthController.swift:99-100 — the name is split on
            // the literal " " only, and the emptiness test is
            // `letters.isEmpty`, so a name made of a tab, a newline or a
            // non-breaking space produces a non-nil string holding one
            // whitespace character. `AvatarView` (Views/Components/Avatar.swift:16)
            // checks `!initials.isEmpty`, which that passes, so the avatar
            // draws an empty tinted circle instead of falling back to the
            // neutral person symbol. Splitting on `.whitespacesAndNewlines`
            // and rejecting a blank result would close it.
            let result = initials(for: name)
            #expect(result != nil, "asserted as it is: whitespace survives as an initial")
            #expect(result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        }
    }

    @Test("FINDING (low): a name beginning with ß yields three characters, not two")
    func sharpSUppercasesToTwoLetters() async throws {
        try await withCleanAuthState {
            // FINDING (low): AuthController.swift:99-100 — `prefix(2)` caps the
            // number of *source* letters, then `.uppercased()` runs on the
            // joined string. German ß uppercases to "SS", so two name parts
            // can produce a three- or four-character initial inside a fixed
            // 32pt circle sized for two.
            #expect(initials(for: "ßeta Gamma") == "SSG")
            #expect(initials(for: "ßruno ßauer") == "SSSS")
        }
    }

    @Test("The initials follow the stored name, and disappear with it")
    func initialsTrackTheStoredName() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey)
            #expect(auth.initials == "MK")

            auth.signOut()
            #expect(auth.initials == nil, "no initials survive sign-out")
        }
    }
}

// MARK: - Shipped configuration

/// Every permission the app actually asks for. A missing or empty usage string
/// is an automatic App Store rejection, and on device it is worse than that:
/// the API traps the moment it is called.
private let usageDescriptionKeys = [
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
    "NSPhotoLibraryUsageDescription",
]

/// These read the built application bundle rather than the files in the repo:
/// a privacy manifest that is present on disk but never copied into the app is
/// exactly the failure worth catching, and reading `Vinnota/PrivacyInfo.xcprivacy`
/// would not catch it.
@Suite("Shipped configuration · what App Store review looks at")
struct ShippedConfigurationTests {

    @Test("The test really is inspecting the application bundle")
    func bundleIsTheApp() throws {
        let identifier = try #require(appBundle.bundleIdentifier)
        #expect(identifier == "com.vinnota.cellarbook")
        #expect(appBundle.bundlePath.hasSuffix(".app"))
    }

    // MARK: PrivacyInfo.xcprivacy

    private func privacyManifest() throws -> [String: Any] {
        let url = try #require(appBundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
                               "PrivacyInfo.xcprivacy is not in the built app bundle")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any], "the privacy manifest is not a plist dictionary")
    }

    @Test("The privacy manifest ships in the bundle and parses as a plist")
    func privacyManifestExistsAndParses() throws {
        #expect(try privacyManifest().isEmpty == false)
    }

    @Test("The manifest declares no tracking, and no tracking domains to go with it")
    func privacyManifestDeclaresNoTracking() throws {
        let manifest = try privacyManifest()

        let tracking = try #require(manifest["NSPrivacyTracking"] as? Bool,
                                    "NSPrivacyTracking is missing or is not a boolean")
        #expect(tracking == false)

        // Apple rejects a manifest that claims no tracking while listing
        // domains, so the array must be present and empty.
        let domains = try #require(manifest["NSPrivacyTrackingDomains"] as? [String],
                                   "NSPrivacyTrackingDomains is missing")
        #expect(domains.isEmpty)
    }

    @Test("Every required top-level key is present",
          arguments: ["NSPrivacyTracking",
                      "NSPrivacyTrackingDomains",
                      "NSPrivacyCollectedDataTypes",
                      "NSPrivacyAccessedAPITypes"])
    func privacyManifestHasTheRequiredKeys(_ key: String) throws {
        #expect(try privacyManifest()[key] != nil, "the privacy manifest is missing \(key)")
    }

    @Test("Each collected data type is fully described")
    func collectedDataTypesAreWellFormed() throws {
        let types = try #require(try privacyManifest()["NSPrivacyCollectedDataTypes"]
                                 as? [[String: Any]])
        #expect(types.isEmpty == false)

        for entry in types {
            let name = try #require(entry["NSPrivacyCollectedDataType"] as? String)
            #expect(name.hasPrefix("NSPrivacyCollectedDataType"))
            #expect(entry["NSPrivacyCollectedDataTypeLinked"] as? Bool != nil,
                    "\(name) does not say whether it is linked to the user")
            // Nothing may be declared as used for tracking in a manifest that
            // says the app does not track.
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false,
                    "\(name) claims tracking in a manifest that declares none")
            let purposes = try #require(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            #expect(purposes.isEmpty == false, "\(name) declares no purpose")
        }
    }

    @Test("The identity the app actually stores is declared",
          arguments: ["NSPrivacyCollectedDataTypeName",
                      "NSPrivacyCollectedDataTypeEmailAddress",
                      "NSPrivacyCollectedDataTypeUserID"])
    func collectedDataTypesCoverTheStoredIdentity(_ expected: String) throws {
        // AuthController writes a display name, an email address and an Apple
        // user ID. All three have to appear here.
        let types = try #require(try privacyManifest()["NSPrivacyCollectedDataTypes"]
                                 as? [[String: Any]])
        let declared = Set(types.compactMap { $0["NSPrivacyCollectedDataType"] as? String })
        #expect(declared.contains(expected))
    }

    @Test("Each accessed API category carries at least one reason code")
    func accessedAPITypesCarryReasons() throws {
        let apis = try #require(try privacyManifest()["NSPrivacyAccessedAPITypes"]
                                as? [[String: Any]])
        #expect(apis.isEmpty == false)

        for entry in apis {
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            #expect(category.hasPrefix("NSPrivacyAccessedAPICategory"))
            let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            #expect(reasons.isEmpty == false, "\(category) declares no reason code")
            for reason in reasons { #expect(reason.isEmpty == false) }
        }
    }

    @Test("UserDefaults, which holds the account identity, is declared as an accessed API")
    func userDefaultsAccessIsDeclared() throws {
        let apis = try #require(try privacyManifest()["NSPrivacyAccessedAPITypes"]
                                as? [[String: Any]])
        let categories = Set(apis.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        #expect(categories.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
    }

    // MARK: Info.plist

    @Test("Every permission the app requests has a usage string",
          arguments: usageDescriptionKeys)
    func usageDescriptionIsPresentAndUseful(_ key: String) throws {
        let value = try #require(appBundle.object(forInfoDictionaryKey: key) as? String,
                                 "\(key) is missing from the shipped Info.plist")

        #expect(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                "\(key) is empty")
        // A one-word string passes review about as often as a missing one.
        #expect(value.count >= 20, "\(key) does not explain anything")
        #expect(value.hasSuffix("."), "\(key) is not written as a sentence")
        // An unexpanded build setting ships the literal "$(…)" to the user.
        #expect(value.contains("$(") == false, "\(key) contains an unexpanded build setting")
        #expect(value.localizedCaseInsensitiveContains("todo") == false)
    }

    @Test("The usage strings are distinct, so each prompt explains its own permission")
    func usageDescriptionsAreNotCopyPasted() {
        let values = usageDescriptionKeys.compactMap {
            appBundle.object(forInfoDictionaryKey: $0) as? String
        }
        #expect(values.count == usageDescriptionKeys.count)
        #expect(Set(values).count == values.count)
    }

    @Test("The speech prompt is honest about where dictation is processed")
    func speechDescriptionMentionsApple() throws {
        // `SpeechTranscriber` falls back to Apple's servers when no on-device
        // model exists, and this dialog is the only place the user is told.
        let value = try #require(
            appBundle.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String)
        #expect(value.contains("Apple"))
    }

    @Test("Bundle identity and version are real values, not unexpanded settings",
          arguments: ["CFBundleIdentifier", "CFBundleShortVersionString",
                      "CFBundleVersion", "CFBundleName", "CFBundleExecutable"])
    func bundleIdentityIsResolved(_ key: String) throws {
        let value = try #require(appBundle.object(forInfoDictionaryKey: key) as? String,
                                 "\(key) is missing")
        #expect(value.isEmpty == false)
        #expect(value.contains("$(") == false, "\(key) was never expanded")
    }
}
