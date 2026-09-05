import AuthenticationServices
import Foundation
import ObjectiveC
import Security
import SwiftData
import Testing
import UIKit

@testable import Vinnota

// MARK: - The storage contract, restated

/// `AuthController` keeps every one of these private, which is right for the
/// app and useless for a test: an assertion against `auth.displayName` proves
/// only that a getter agrees with its own setter. These literals are the real
/// on-disk contract — the keychain account, the two `UserDefaults` key *shapes*,
/// the avatar's filename *shape*, and the user ID that marks a session as
/// stubbed — so the tests below read and write *storage* and let the controller
/// observe it.
///
/// The identity keys and the avatar filename are no longer global: each carries
/// the account's token, so a second Apple ID on this device reads a different
/// set. The store file is scoped the same way — see `CellarStore`.
///
/// A change to any of them is a migration: the old values keep living on the
/// device, and these tests are meant to fail when that happens.
private enum Storage {
    static let keychainAccount = "com.vinnota.appleUserID"
    static let stubUserID = "stub.local.account"

    static let nameKeyPrefix = "com.vinnota.displayName."
    static let emailKeyPrefix = "com.vinnota.email."
    static let avatarPrefix = "avatar-"
    static let avatarSuffix = ".jpg"
    static let storePrefix = "cellar-"

    /// The bucket a signed-out app resolves to. Nothing is ever written here —
    /// which is exactly why a signed-out controller reads no identity at all.
    static let signedOutToken = "signed-out"

    static func nameKey(_ token: String) -> String { nameKeyPrefix + token }
    static func emailKey(_ token: String) -> String { emailKeyPrefix + token }
    static func avatarFilename(_ token: String) -> String { avatarPrefix + token + avatarSuffix }

    static var supportDirectory: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    static func avatarURL(_ token: String) -> URL? {
        supportDirectory?.appendingPathComponent(avatarFilename(token))
    }

    /// Every avatar file belonging to any account, however many there are.
    static func avatarFiles() -> [URL] {
        guard let dir = supportDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names
            .filter { $0.hasPrefix(avatarPrefix) && $0.hasSuffix(avatarSuffix) }
            .map { dir.appendingPathComponent($0) }
    }

    /// The identity keys currently present for any account.
    static func identityKeys() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(nameKeyPrefix) || $0.hasPrefix(emailKeyPrefix)
        }
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
/// `xcodebuild … CODE_SIGNING_ALLOWED=NO` produces an unsigned application. An
/// unsigned process has no `application-identifier` entitlement, and the
/// simulator keychain answers every request from one with
/// `errSecMissingEntitlement` (-34018). `AuthController`'s own `SecItemAdd`
/// fails there too, silently: it ignores the status, so in this configuration
/// the app signs in and then forgets the session at the next launch.
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

/// Whether a session can be established without Apple's UI.
///
/// Identity and the profile picture are now resolved against the *signed-in*
/// account, so a test that wants to read either has to be signed in as
/// somebody. The only way to do that from a test is the debug stub, which a
/// Release compile does not contain.
#if DEBUG
private let canSignInLocally = true
#else
private let canSignInLocally = false
#endif

/// A session that can be established *and* survives a relaunch.
private let localSessionAvailable = keychainAvailable && canSignInLocally

private let localSessionSkipReason = Comment(
    rawValue: "identity and the profile picture are read for the signed-in account only, "
        + "and a Release compile has no way to establish a local session — "
        + "the debug sign-in stub is compiled out")

/// Establishes a local session the way the app does, and returns the token the
/// identity of that session is filed under.
///
/// In DEBUG that is the stub itself. The stub does not exist in a Release
/// compile, so the credential is planted directly there — which keeps this file
/// compiling in both configurations, as the app target does. The returned token
/// is whatever the controller actually ended up on, so seeding identity through
/// it stays truthful in either configuration.
@MainActor
@discardableResult
private func establishLocalSession(_ auth: AuthController) -> String {
    #if DEBUG
    auth.signInStubbed()
    #else
    keychainWrite(Storage.stubUserID)
    #endif
    return CellarStore.token(for: auth.state.accountID)
}

/// Writes name and/or email into one account's bucket, from outside the app.
private func seedIdentity(token: String, name: String? = nil, email: String? = nil) {
    if let name { UserDefaults.standard.set(name, forKey: Storage.nameKey(token)) }
    if let email { UserDefaults.standard.set(email, forKey: Storage.emailKey(token)) }
}

/// Puts a picture in one account's avatar slot without going through the
/// controller — the only way to give an account a photo it is not signed in as.
private func plantAvatar(_ data: Data, token: String) -> URL? {
    guard let url = Storage.avatarURL(token) else { return nil }
    try? data.write(to: url, options: .atomic)
    return url
}

// MARK: - Global state, saved and put back

/// Everything below writes the real `UserDefaults`, the real keychain and real
/// files in Application Support — the same ones the running app uses. Each test
/// starts from a clean slate and hands back exactly what it found.
///
/// The sweep is by prefix rather than by a fixed pair of keys: identity is now
/// filed per account, so how many keys and how many avatar files exist depends
/// on how many accounts have ever used this device.
@MainActor
private func withCleanAuthState(_ body: () async throws -> Void) async throws {
    let defaults = UserDefaults.standard

    var savedIdentity: [String: Any] = [:]
    for key in Storage.identityKeys() {
        if let value = defaults.object(forKey: key) { savedIdentity[key] = value }
    }
    let savedSession = keychainRead()
    var savedAvatars: [String: Data] = [:]
    for url in Storage.avatarFiles() {
        if let data = try? Data(contentsOf: url) { savedAvatars[url.lastPathComponent] = data }
    }

    for key in savedIdentity.keys { defaults.removeObject(forKey: key) }
    keychainDelete()
    for url in Storage.avatarFiles() { try? FileManager.default.removeItem(at: url) }

    defer {
        for key in Storage.identityKeys() { defaults.removeObject(forKey: key) }
        for (key, value) in savedIdentity { defaults.set(value, forKey: key) }

        if let savedSession { keychainWrite(savedSession) } else { keychainDelete() }

        for url in Storage.avatarFiles() { try? FileManager.default.removeItem(at: url) }
        if let dir = Storage.supportDirectory {
            for (name, data) in savedAvatars {
                try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
            }
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
            // It invents no identity — a stub account is nameless, and it reads
            // its own bucket rather than whatever the last account left behind.
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
    /// `#if DEBUG`. Test bundles compile in DEBUG, so only the DEBUG arm is
    /// ever built here — the `#else` arm that destroys a stale stub in a
    /// shipped build is not merely unasserted, it is not compiled. Confirmed by
    /// mutation: replacing that arm's `deleteKeychain(); state = .signedOut`
    /// with `state = .signedIn(userID: stored, stubbed: true)` — a shipped
    /// build admitting a dev build's session with no credential at all — leaves
    /// the whole run green.
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

    /// Was: `rejectedSessionLeavesResidualIdentity`, a FINDING (medium)
    /// asserting the leak as it stood. Two things closed it: identity and the
    /// picture are now resolved against the *signed-in* account, so a
    /// signed-out controller has no bucket to read from; and `restore()` calls
    /// `loadAvatar()` after the session has been settled rather than before, so
    /// a credential that is about to be thrown out never gets its photo decoded
    /// into memory in the first place.
    ///
    /// The data itself deliberately stays on disk — see `signOut()`. What is
    /// asserted here is that none of it is *reachable* once the session is
    /// refused.
    @Test("A rejected session at launch leaves nothing readable — no name, no email, no photo",
          .enabled(if: keychainAvailable, keychainSkipReason))
    func rejectedSessionLeavesNoReadableIdentity() async throws {
        try await withCleanAuthState {
            // The account whose credential is about to be refused, with a full
            // set of leavings: name, email, profile photograph.
            let rejectedID = "001234.9f8e7d6c5b4a39281706abcdef012345.1122"
            let token = CellarStore.token(for: rejectedID)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            let avatarURL = try #require(plantAvatar(jpegFixture(200, 200), token: token))
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))

            // The credential is no longer good, so launch throws the session
            // out. This is the same branch a Release build takes when it finds
            // a stub session left behind by a dev build.
            keychainWrite(rejectedID)
            let auth = AuthController()
            await auth.restore()

            #expect(auth.state == .signedOut)
            #expect(keychainRead() == nil)

            // The leak, closed. Nothing of the refused account is readable:
            // not through the controller's accessors, and not in memory.
            #expect(auth.avatar == nil, "restore() must settle the session before loading a photo")
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(auth.initials == nil)

            // The bytes are still on disk, and that is deliberate: Apple hands
            // over a name and an email exactly once, so throwing them away on a
            // refused launch would make the account permanently nameless if the
            // refusal was a transient daemon failure. `forgetThisAccount()` is
            // the erase, and it is a separate intention.
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(token)) == "Marie Kondo")
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))
            // But they are filed under that account's token, not somewhere a
            // different account would find them.
            #expect(Storage.nameKey(token) != Storage.nameKey(Storage.signedOutToken))
        }
    }
}

// MARK: - Session persistence

@Suite("Session persistence · what is stored, what sign-out ends, what it keeps", .serialized)
@MainActor
struct SessionPersistenceTests {

    @Test("displayName and email read the signed-in account's keys, not some other pair",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func identityIsReadFromTheAccountScopedKeys() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)

            UserDefaults.standard.set("Marie Kondo", forKey: Storage.nameKey(token))
            UserDefaults.standard.set("marie@example.com", forKey: Storage.emailKey(token))

            // Written to storage from outside, read back through the app.
            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")

            // The keys really are the account-scoped ones: the old global pair
            // is not consulted, so a device upgraded from that layout does not
            // hand one account the previous global identity.
            UserDefaults.standard.set("Someone Else", forKey: "com.vinnota.displayName")
            UserDefaults.standard.set("someone@example.com", forKey: "com.vinnota.email")
            defer {
                UserDefaults.standard.removeObject(forKey: "com.vinnota.displayName")
                UserDefaults.standard.removeObject(forKey: "com.vinnota.email")
            }
            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
        }
    }

    @Test("Signed out, there is no identity to read at all")
    func signedOutReadsNoIdentity() async throws {
        try await withCleanAuthState {
            // Seed every bucket a device could plausibly hold: two real
            // accounts and the signed-out one nothing ever writes to.
            seedIdentity(token: CellarStore.token(for: "account.one"),
                         name: "Marie Kondo", email: "marie@example.com")
            seedIdentity(token: CellarStore.token(for: "account.two"),
                         name: "Jean Peridot", email: "jean@example.com")

            let auth = AuthController()
            #expect(auth.state == .signedOut)
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(auth.initials == nil)
            auth.loadAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("The identity is not held in memory — a second controller on the same account agrees",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func identityIsSharedThroughStorage() async throws {
        try await withCleanAuthState {
            let first = AuthController()
            let token = establishLocalSession(first)
            seedIdentity(token: token, name: "Jean Peridot", email: "jean@example.com")

            let second = AuthController()
            establishLocalSession(second)

            #expect(first.displayName == second.displayName)
            #expect(first.email == second.email)
            #expect(second.email == "jean@example.com")
        }
    }

    /// Was: `signOutClearsTheIdentityAndThePicture`. Sign-out deliberately no
    /// longer destroys anything — Apple supplies `fullName` and `email` on the
    /// first authorization only, so erasing them at sign-out made a returning
    /// user permanently nameless. What sign-out ends is the *session*.
    @Test("Sign-out ends the session and keeps the account's name, email and picture",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func signOutKeepsTheAccountsIdentityAndPicture() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            auth.setAvatar(jpegFixture(300, 300))

            let avatarURL = try #require(Storage.avatarURL(token))
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))
            #expect(auth.displayName == "Marie Kondo")

            auth.signOut()

            // In memory: the session is over and nothing of it is reachable.
            #expect(auth.state == .signedOut)
            #expect(auth.isStubbedSession == false)
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(auth.avatar == nil)

            // On disk: the account's own data is untouched, under its own keys.
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(token)) == "Marie Kondo")
            #expect(UserDefaults.standard.string(forKey: Storage.emailKey(token)) == "marie@example.com")
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))
        }
    }

    @Test("Signing back in as the same account finds its name, email and picture again",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func signingBackInRestoresTheIdentity() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            auth.setAvatar(jpegFixture(300, 300))
            auth.signOut()

            // A whole new launch, signing in as the same account.
            let returning = AuthController()
            let sameToken = establishLocalSession(returning)
            #expect(sameToken == token, "the same account resolves to the same bucket")
            returning.loadAvatar()

            #expect(returning.displayName == "Marie Kondo")
            #expect(returning.email == "marie@example.com")
            #expect(returning.initials == "MK")
            #expect(returning.avatar != nil)
        }
    }

    /// Was part of `signOutClearsTheIdentityAndThePicture`. The destructive
    /// erase now lives in its own method, because signing out and deleting your
    /// data are different intentions.
    @Test("forgetThisAccount erases the name, the email and the picture",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func forgetThisAccountErasesEverythingItOwns() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            auth.setAvatar(jpegFixture(300, 300))

            let avatarURL = try #require(Storage.avatarURL(token))
            #expect(FileManager.default.fileExists(atPath: avatarURL.path))

            auth.forgetThisAccount()

            #expect(auth.state == .signedOut)
            #expect(auth.avatar == nil)
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(UserDefaults.standard.object(forKey: Storage.nameKey(token)) == nil)
            #expect(UserDefaults.standard.object(forKey: Storage.emailKey(token)) == nil)
            #expect(FileManager.default.fileExists(atPath: avatarURL.path) == false)

            // And it ends the session too, so nothing is left signed in to a
            // account that no longer has any data.
            #expect(keychainRead() == nil)
        }
    }

    @Test("forgetThisAccount touches only the signed-in account",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func forgetThisAccountLeavesOtherAccountsAlone() async throws {
        try await withCleanAuthState {
            let otherToken = CellarStore.token(for: "some.other.apple.id")
            seedIdentity(token: otherToken, name: "Jean Peridot", email: "jean@example.com")
            let otherAvatar = try #require(plantAvatar(jpegFixture(120, 120), token: otherToken))

            let auth = AuthController()
            let token = establishLocalSession(auth)
            #expect(token != otherToken)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            auth.setAvatar(jpegFixture(120, 120))

            auth.forgetThisAccount()

            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(otherToken)) == "Jean Peridot")
            #expect(UserDefaults.standard.string(forKey: Storage.emailKey(otherToken)) == "jean@example.com")
            #expect(FileManager.default.fileExists(atPath: otherAvatar.path))
        }
    }

    @Test("forgetThisAccount while signed out does nothing and does not crash")
    func forgetThisAccountFromASignedOutStateIsSafe() async throws {
        try await withCleanAuthState {
            let strangerToken = CellarStore.token(for: "someone.else")
            seedIdentity(token: strangerToken, name: "Jean Peridot")

            let auth = AuthController()
            auth.forgetThisAccount()

            #expect(auth.state == .signedOut)
            // There is no signed-in account to erase, so nothing is erased —
            // in particular it does not fall through to the signed-out bucket
            // and start deleting whatever it finds.
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(strangerToken)) == "Jean Peridot")
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

    /// Was: `signOutReachesThePreferencesStore`, which asserted that sign-out
    /// removed the email from the preferences daemon. Sign-out no longer
    /// deletes anything, so the same technique is pointed at the method that
    /// does — and at proving the address really is persisted in the clear.
    @Test("forgetThisAccount reaches the preferences store, not only the in-process cache",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func forgetThisAccountReachesThePreferencesStore() async throws {
        try await withCleanAuthState {
            let address = "marie.kondo.private@example.com"

            let auth = AuthController()
            let token = establishLocalSession(auth)
            let key = Storage.emailKey(token) as CFString
            UserDefaults.standard.set(address, forKey: Storage.emailKey(token))
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)

            // `CFPreferencesCopyAppValue` goes to the preferences daemon, so
            // it sees what was actually persisted rather than what
            // `UserDefaults` is holding in this process. (The .plist on disk
            // is not usable for this: cfprefsd writes it back on its own
            // schedule, and it is still 42 bytes long moments after a write.)
            // The precondition is an assertion too — if the address never
            // reached the store, the check afterwards would prove nothing.
            let before = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? String
            #expect(before == address, "the email is persisted in the clear, unencrypted")

            // Sign-out is not what removes it, deliberately.
            auth.signOut()
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
            #expect(CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? String == address,
                    "sign-out keeps the account's data on purpose")

            // Erasing the account is.
            establishLocalSession(auth)
            auth.forgetThisAccount()
            CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)

            let after = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? String
            #expect(after == nil, "the address outlives account erasure in the preferences store")
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

    @Test("After sign-out a fresh launch finds no session and reads no identity",
          .enabled(if: localSessionAvailable, localSessionSkipReason))
    func noResidualSessionAfterSignOut() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            auth.setAvatar(jpegFixture(150, 150))
            auth.signOut()

            let relaunched = AuthController()
            await relaunched.restore()
            #expect(relaunched.state == .signedOut)
            #expect(relaunched.isStubbedSession == false)
            // The account's data is still on disk — it is simply nobody's to
            // read until that account signs in again.
            #expect(relaunched.avatar == nil)
            #expect(relaunched.displayName == nil)
            #expect(relaunched.email == nil)
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(token)) == "Marie Kondo")
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

    @Test("A stored identity survives a later sign-in that carries no name or email",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func aLaterSignInDoesNotWipeTheStoredIdentity() async throws {
        try await withCleanAuthState {
            // The first authorization: Apple hands the name and email over
            // once, and they are written to that account's bucket at that one
            // opportunity.
            let token = CellarStore.token(for: Storage.stubUserID)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")

            // Every later sign-in arrives with both fields nil. The identity
            // must not be cleared to match, or a returning user is nameless
            // forever — Apple never offers those fields again.
            let auth = AuthController()
            let signedInToken = establishLocalSession(auth)
            #expect(signedInToken == token)

            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(token)) == "Marie Kondo")
            #expect(UserDefaults.standard.string(forKey: Storage.emailKey(token)) == "marie@example.com")
        }
    }

    @Test("A relaunch does not disturb the stored identity either",
          .enabled(if: localSessionAvailable, localSessionSkipReason))
    func restoreDoesNotWipeTheStoredIdentity() async throws {
        try await withCleanAuthState {
            let token = CellarStore.token(for: Storage.stubUserID)
            seedIdentity(token: token, name: "Marie Kondo", email: "marie@example.com")
            keychainWrite(Storage.stubUserID)

            let auth = AuthController()
            await auth.restore()

            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == "marie@example.com")
        }
    }

    @Test("Half an identity is kept as half, not discarded",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func nameWithoutEmailIsStillAName() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, name: "Marie Kondo")

            #expect(auth.displayName == "Marie Kondo")
            #expect(auth.email == nil)
            // `AccountSheet.identityIsPartial` turns exactly this into the
            // "Apple shares a name and email only the first time" line.
            #expect(auth.isStubbedSession == canSignInLocally)
        }
    }

    @Test("An email without a name is kept too",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func emailWithoutNameIsStillAnEmail() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, email: "marie@example.com")

            #expect(auth.email == "marie@example.com")
            #expect(auth.displayName == nil)
            #expect(auth.initials == nil)
        }
    }

    @Test("A Hide-My-Email relay address is stored verbatim",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func relayAddressIsNotRewritten() async throws {
        try await withCleanAuthState {
            let relay = "a1b2c3d4e5@privaterelay.appleid.com"
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, email: relay)
            #expect(auth.email == relay)
        }
    }

    @Test("No credential, name, email or user ID reaches the console",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func nothingSensitiveIsLogged() async throws {
        try await withCleanAuthState {
            let secrets = ["Marie Kondo", "marie.secret@example.com", Storage.stubUserID]
            let picture = jpegFixture(120, 120)

            let output = await capturingConsole {
                let auth = AuthController()
                let token = establishLocalSession(auth)
                seedIdentity(token: token, name: secrets[0], email: secrets[1])
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
            // The account token derived from the user ID must not be printed
            // either — it names a file that is one hash away from the ID.
            #expect(output.contains(CellarStore.token(for: Storage.stubUserID)) == false)
        }
    }
}

// MARK: - Avatar storage

@Suite("Avatar storage · where it lives and how it fails", .serialized)
@MainActor
struct AvatarStorageTests {

    @Test("The picture is written to Application Support under this account's name",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func avatarLivesInApplicationSupport() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            auth.setAvatar(jpegFixture(300, 200))

            let url = try #require(Storage.avatarURL(token))
            #expect(url.lastPathComponent == "avatar-\(token).jpg")
            // The filename carries the account token, not the Apple user ID.
            #expect(url.lastPathComponent.contains(Storage.stubUserID) == false)
            #expect(url.path.contains("/Library/Application Support"))
            // Not Caches, which the system may evict, and not Documents,
            // which is user-visible through the Files app.
            #expect(url.path.contains("/Caches/") == false)
            #expect(url.path.contains("/Documents/") == false)
            #expect(FileManager.default.fileExists(atPath: url.path))
            #expect(auth.avatar != nil)
        }
    }

    @Test("Nothing is written while signed out — there is no account to write for")
    func settingAPictureWhileSignedOutIsANoOp() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            #expect(auth.state == .signedOut)

            auth.setAvatar(jpegFixture(200, 200))

            #expect(auth.avatar == nil)
            #expect(Storage.avatarFiles().isEmpty, "a signed-out app wrote a photo to disk")
        }
    }

    @Test("A stored picture is loaded again on the next launch",
          .enabled(if: localSessionAvailable, localSessionSkipReason))
    func avatarSurvivesRelaunch() async throws {
        try await withCleanAuthState {
            let seeder = AuthController()
            establishLocalSession(seeder)
            seeder.setAvatar(jpegFixture(300, 200))

            let relaunched = AuthController()
            establishLocalSession(relaunched)
            #expect(relaunched.avatar == nil, "nothing is read until loadAvatar runs")
            relaunched.loadAvatar()
            #expect(relaunched.avatar != nil)

            // And `restore()` is what calls it in the app — after the session
            // has been settled, never before.
            let launched = AuthController()
            await launched.restore()
            #expect(launched.avatar != nil)
        }
    }

    @Test("An oversized picture is downscaled before it is kept in memory",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func oversizedPictureIsDownscaledInMemory() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            auth.setAvatar(jpegFixture(1024, 768))

            let image = try #require(auth.avatar)
            #expect(image.size.width == 512)
            #expect(image.size.height == 384)  // the aspect ratio is preserved
        }
    }

    @Test("A picture already smaller than the cap is stored untouched",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func smallPictureIsNotUpscaled() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            auth.setAvatar(jpegFixture(100, 80))

            let image = try #require(auth.avatar)
            #expect(image.size.width == 100)
            #expect(image.size.height == 80)
        }
    }

    @Test("FINDING (low): the file on disk is the device scale larger than the 512pt cap",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func writtenFileIsLargerThanTheCapSuggests() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            auth.setAvatar(jpegFixture(1024, 768))

            let url = try #require(Storage.avatarURL(token))
            let data = try Data(contentsOf: url)
            let written = try #require(UIImage(data: data))

            // FINDING (low): AuthController's `downscale` renders through a
            // `UIGraphicsImageRenderer` with no explicit format, so it inherits
            // the device scale. `scaled.size` is 512pt as intended, but
            // `jpegData` writes 512 × scale *pixels*: 1536 px on a 3x phone,
            // nine times the pixel count the comment on `setAvatar` sets out to
            // avoid. Visually harmless; the file is simply much bigger than the
            // code says it is. A format with `scale = 1` would fix it.
            #expect(written.size.width == 512 * rendererScale)
            if rendererScale > 1 {
                #expect(written.size.width > 512)
                #expect(data.count > 0)
            }
        }
    }

    @Test("A file that is not an image loads as no avatar instead of crashing",
          .enabled(if: localSessionAvailable, localSessionSkipReason),
          arguments: ["not an image at all",
                      "<?xml version=\"1.0\"?><plist/>",
                      "\u{0}\u{1}\u{2}\u{3}",
                      "GIF89a"])
    func corruptAvatarFileLoadsAsNil(_ junk: String) async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            let url = try #require(Storage.avatarURL(token))
            try Data(junk.utf8).write(to: url, options: .atomic)

            auth.loadAvatar()
            #expect(auth.avatar == nil)

            // And the launch path walks over it without trouble either.
            await auth.restore()
            #expect(auth.avatar == nil)
        }
    }

    @Test("A truncated JPEG does not crash the loader",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func truncatedJpegIsSurvivable() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            let full = jpegFixture(400, 400)
            let url = try #require(Storage.avatarURL(token))
            try full.prefix(full.count / 3).write(to: url, options: .atomic)

            auth.loadAvatar()
            // UIImage may decode a partial JPEG or refuse it — either is
            // acceptable, a crash is not. Whichever it does, it must do it
            // consistently: a loader that returned an image once and nil the
            // next time would make the header avatar flicker between a picture
            // and a placeholder across launches.
            let first = auth.avatar != nil
            let second = AuthController()
            establishLocalSession(second)
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

    @Test("An empty avatar file loads as no avatar",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func emptyAvatarFileIsNil() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            let url = try #require(Storage.avatarURL(token))
            try Data().write(to: url, options: .atomic)

            auth.loadAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("Loading with no file at all is not an error",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func missingAvatarFileIsNil() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            establishLocalSession(auth)
            auth.loadAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("Setting a non-image keeps the picture that was already there",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func settingJunkDoesNotDestroyTheStoredPicture() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            auth.setAvatar(jpegFixture(200, 200))
            let url = try #require(Storage.avatarURL(token))
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

    @Test("Clearing removes the file, and clearing again is harmless",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func clearAvatarDeletesTheFile() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            auth.setAvatar(jpegFixture(200, 200))
            let url = try #require(Storage.avatarURL(token))
            #expect(FileManager.default.fileExists(atPath: url.path))

            auth.clearAvatar()
            #expect(auth.avatar == nil)
            #expect(FileManager.default.fileExists(atPath: url.path) == false)

            auth.clearAvatar()
            #expect(auth.avatar == nil)
        }
    }

    @Test("Replacing a picture leaves one file, holding the newer image",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func replacingAPictureOverwritesInPlace() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            auth.setAvatar(jpegFixture(200, 200))
            auth.setAvatar(jpegFixture(400, 100))

            let url = try #require(Storage.avatarURL(token))
            let stored = try #require(UIImage(data: try Data(contentsOf: url)))
            #expect(stored.size.width > stored.size.height, "the second picture is the wide one")

            let files = Storage.avatarFiles().map(\.lastPathComponent).sorted()
            #expect(files == ["avatar-\(token).jpg"], "no orphaned copies accumulate")
        }
    }
}

// MARK: - Initials

/// `initials` renders inside `AvatarView`, on the header and on the account
/// sheet. A trap here is a crash on a screen the user reaches by tapping their
/// own face, so the inputs below are deliberately unpleasant.
///
/// Every case needs a signed-in account: the name is read from that account's
/// bucket, so a signed-out controller would answer nil to all of them and the
/// whole suite would pass without touching the logic.
@Suite("Initials · derived from whatever name is on file", .serialized)
@MainActor
struct InitialsTests {

    private func initials(for name: String?) -> String? {
        let auth = AuthController()
        let token = establishLocalSession(auth)
        if let name { UserDefaults.standard.set(name, forKey: Storage.nameKey(token)) }
        else { UserDefaults.standard.removeObject(forKey: Storage.nameKey(token)) }
        return auth.initials
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
            // FINDING (low): AuthController's `initials` splits the name on the
            // literal " " only, and the emptiness test is `letters.isEmpty`, so
            // a name made of a tab, a newline or a non-breaking space produces
            // a non-nil string holding one whitespace character. `AvatarView`
            // (Views/Components/Avatar.swift:16) checks `!initials.isEmpty`,
            // which that passes, so the avatar draws an empty tinted circle
            // instead of falling back to the neutral person symbol. Splitting
            // on `.whitespacesAndNewlines` and rejecting a blank result would
            // close it.
            let result = initials(for: name)
            #expect(result != nil, "asserted as it is: whitespace survives as an initial")
            #expect(result?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true)
        }
    }

    @Test("FINDING (low): a name beginning with ß yields three characters, not two")
    func sharpSUppercasesToTwoLetters() async throws {
        try await withCleanAuthState {
            // FINDING (low): AuthController's `initials` — `prefix(2)` caps the
            // number of *source* letters, then `.uppercased()` runs on the
            // joined string. German ß uppercases to "SS", so two name parts
            // can produce a three- or four-character initial inside a fixed
            // 32pt circle sized for two.
            #expect(initials(for: "ßeta Gamma") == "SSG")
            #expect(initials(for: "ßruno ßauer") == "SSSS")
        }
    }

    @Test("The initials follow the stored name, and are unreadable once signed out",
          .enabled(if: canSignInLocally, localSessionSkipReason))
    func initialsTrackTheStoredName() async throws {
        try await withCleanAuthState {
            let auth = AuthController()
            let token = establishLocalSession(auth)
            seedIdentity(token: token, name: "Marie Kondo")
            #expect(auth.initials == "MK")

            auth.signOut()
            // The name is still on disk — sign-out keeps it — but there is no
            // signed-in account to read it for.
            #expect(auth.initials == nil, "no initials are readable while signed out")
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(token)) == "Marie Kondo")
        }
    }
}

// MARK: - Account isolation

/// The point of the per-account store: one Apple ID's cellar, name, email and
/// photograph are not merely hidden from another's, they are in different files
/// and different keys. A shared store filtered by an owner column would be one
/// forgotten predicate away from showing someone else's bottles; these tests
/// assert the stronger property, that the container a signed-in account holds
/// is not attached to anyone else's file at all.
///
/// Every account used here is invented for the test and its store is removed
/// afterwards — nothing is left in Application Support.
@Suite("Account isolation · one cellar, one identity, per account", .serialized)
@MainActor
struct AccountIsolationTests {

    private static let schema = Schema([Wine.self, TastingNote.self])

    /// An account ID no real device could produce, unique per call so two runs
    /// never collide over the same file.
    private func temporaryAccountID(_ label: String) -> String {
        "vinnota.tests.\(label).\(UUID().uuidString)"
    }

    /// Removes an account's store and everything SwiftData put beside it: the
    /// SQLite sidecars, any quarantined copy, and the hidden
    /// `.cellar-<token>.store_SUPPORT` directory the coordinator creates for
    /// external-storage blobs. Matching on the bare `cellar-` prefix alone
    /// leaves that directory behind, which is how this suite would slowly fill
    /// Application Support with debris.
    private func removeStore(for accountID: String) {
        let token = CellarStore.token(for: accountID)
        let stem = Storage.storePrefix + token
        guard let dir = Storage.supportDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return }
        for name in names where name.hasPrefix(stem) || name.hasPrefix("." + stem) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Everything in Application Support belonging to this account, by any
    /// name — used to prove the cleanup above actually cleans up.
    private func residue(of accountID: String) -> [String] {
        let token = CellarStore.token(for: accountID)
        guard let dir = Storage.supportDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names.filter { $0.contains(token) }.sorted()
    }

    /// Runs `body` with freshly invented accounts and cleans their files up.
    private func withTemporaryAccounts(
        _ labels: [String], _ body: ([String]) throws -> Void
    ) rethrows {
        let ids = labels.map(temporaryAccountID)
        defer { for id in ids { removeStore(for: id) } }
        try body(ids)
    }

    /// A container opened on one account's real store file, the same way
    /// `CellarStore` opens it.
    private func container(for accountID: String) throws -> ModelContainer {
        let url = try #require(CellarStore.storeURL(for: accountID))
        return try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(schema: Self.schema, url: url)]
        )
    }

    private func bottle(_ name: String) -> Wine {
        Wine(producer: "Giuseppe Rinaldi", name: name, vintage: "2019",
             region: "Barolo", grape: "Nebbiolo", shop: "Enoteca Sciolla")
    }

    private func wines(in container: ModelContainer) throws -> [Wine] {
        // A fresh context, so what comes back is a genuine read of the store
        // rather than the instance a writing context still holds in memory.
        try ModelContext(container).fetch(FetchDescriptor<Wine>())
    }

    // MARK: Naming

    @Test("Two accounts get two tokens, two store files and two sets of identity keys")
    func differentAccountsAreNamedDifferently() throws {
        try withTemporaryAccounts(["a", "b"]) { ids in
            let (a, b) = (ids[0], ids[1])
            let tokenA = CellarStore.token(for: a)
            let tokenB = CellarStore.token(for: b)

            #expect(tokenA != tokenB)

            let urlA = try #require(CellarStore.storeURL(for: a))
            let urlB = try #require(CellarStore.storeURL(for: b))
            #expect(urlA != urlB)
            #expect(urlA.lastPathComponent == "cellar-\(tokenA).store")
            #expect(urlB.lastPathComponent == "cellar-\(tokenB).store")
            // Same directory, different files — the separation is the filename,
            // not a chance difference of location.
            #expect(urlA.deletingLastPathComponent() == urlB.deletingLastPathComponent())

            #expect(Storage.nameKey(tokenA) != Storage.nameKey(tokenB))
            #expect(Storage.emailKey(tokenA) != Storage.emailKey(tokenB))
            #expect(Storage.avatarURL(tokenA) != Storage.avatarURL(tokenB))

            // And none of them collide with the signed-out bucket.
            for token in [tokenA, tokenB] {
                #expect(token != Storage.signedOutToken)
            }
        }
    }

    @Test("The same account always yields the same token, and the token is not the user ID")
    func tokenIsStableAndDoesNotLeakTheAppleIdentifier() throws {
        // Shaped like the identifier Apple actually returns.
        let appleID = "001234.9f8e7d6c5b4a39281706abcdef012345.1122"
        let token = CellarStore.token(for: appleID)

        // Stability: the token is derived, not generated, so a relaunch — or a
        // reinstall that keeps Application Support — finds the same file.
        #expect(CellarStore.token(for: appleID) == token)
        #expect(CellarStore.token(for: appleID) == CellarStore.token(for: appleID))

        // Shape: 16 lowercase hex characters, safe in a filename on any volume.
        #expect(token.count == 16)
        #expect(token.allSatisfy { $0.isHexDigit && !$0.isUppercase })

        // The identifier itself never reaches the filesystem: it is an account
        // identifier, and a filename shows up in backups, crash reports and
        // file listings.
        #expect(token != appleID)
        #expect(appleID.contains(token) == false)
        #expect(token.contains(appleID) == false)
        let url = try #require(CellarStore.storeURL(for: appleID))
        #expect(url.path.contains(appleID) == false)
        #expect(url.lastPathComponent.contains(token))
        #expect(Storage.nameKey(token).contains(appleID) == false)
        #expect(Storage.avatarFilename(token).contains(appleID) == false)

        // A one-character difference gives an unrelated token, so neighbouring
        // Apple IDs cannot land on the same file.
        #expect(CellarStore.token(for: "001234.9f8e7d6c5b4a39281706abcdef012345.1123") != token)

        // No account is its own bucket, and an empty string is not an account.
        #expect(CellarStore.token(for: nil) == Storage.signedOutToken)
        #expect(CellarStore.token(for: "") == Storage.signedOutToken)
        #expect(CellarStore.token(for: appleID) != Storage.signedOutToken)
    }

    @Test("Identity written for one account is invisible to every other account")
    func identityKeysAreScopedPerAccount() async throws {
        try await withCleanAuthState {
            let tokenA = CellarStore.token(for: "isolation.account.a")
            let tokenB = CellarStore.token(for: "isolation.account.b")

            seedIdentity(token: tokenA, name: "Marie Kondo", email: "marie@example.com")
            _ = plantAvatar(jpegFixture(80, 80), token: tokenA)

            // Account B's bucket was never written to.
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(tokenB)) == nil)
            #expect(UserDefaults.standard.string(forKey: Storage.emailKey(tokenB)) == nil)
            let bAvatar = try #require(Storage.avatarURL(tokenB))
            #expect(FileManager.default.fileExists(atPath: bAvatar.path) == false)

            // Nor did the write reach the signed-out bucket, which is what a
            // controller falls back to when no one is signed in.
            #expect(UserDefaults.standard.string(forKey: Storage.nameKey(Storage.signedOutToken)) == nil)

            // A running controller signed in as somebody else entirely sees
            // none of it.
            let auth = AuthController()
            let token = establishLocalSession(auth)
            #expect(token != tokenA)
            #expect(auth.displayName == nil)
            #expect(auth.email == nil)
            #expect(auth.initials == nil)
            auth.loadAvatar()
            #expect(auth.avatar == nil)
        }
    }

    // MARK: The cellar itself

    @Test("Bottles saved under one account's store are not visible from another's")
    func bottlesDoNotCrossBetweenAccounts() throws {
        try withTemporaryAccounts(["owner", "stranger"]) { ids in
            let (owner, stranger) = (ids[0], ids[1])

            let ownersStore = try container(for: owner)
            let strangersStore = try container(for: stranger)

            let write = ModelContext(ownersStore)
            write.insert(bottle("Brunate"))
            write.insert(bottle("Cannubi"))
            try write.save()

            // The owner sees exactly what was written.
            let mine = try wines(in: ownersStore)
            #expect(mine.count == 2)
            #expect(Set(mine.map(\.name)) == ["Brunate", "Cannubi"])

            // The other account's container is attached to a different file, so
            // there is nothing to filter and nothing to leak.
            let theirs = try wines(in: strangersStore)
            #expect(theirs.isEmpty, "another account's bottles are visible")
            #expect(theirs.contains { $0.name == "Brunate" } == false)

            // Both files really exist and really are different files.
            let ownerURL = try #require(CellarStore.storeURL(for: owner))
            let strangerURL = try #require(CellarStore.storeURL(for: stranger))
            #expect(ownerURL != strangerURL)
            #expect(FileManager.default.fileExists(atPath: ownerURL.path))

            // And writing as the stranger does not reach back into the owner's.
            let strangerWrite = ModelContext(strangersStore)
            strangerWrite.insert(bottle("Barbaresco"))
            try strangerWrite.save()
            #expect(try wines(in: ownersStore).count == 2)
            #expect(try wines(in: strangersStore).map(\.name) == ["Barbaresco"])
        }
    }

    @Test("Signing out and back in as the same account still sees its bottles")
    func theSameAccountKeepsItsBottlesAcrossSignOut() throws {
        try withTemporaryAccounts(["returning"]) { ids in
            let account = ids[0]

            let store = CellarStore()
            #expect(store.identity == Storage.signedOutToken)

            store.open(for: account)
            #expect(store.identity == CellarStore.token(for: account))
            #expect(store.failure == nil)

            let write = ModelContext(store.container)
            write.insert(bottle("Brunate"))
            try write.save()

            // Sign out — which is where the old behaviour destroyed things.
            store.open(for: nil)
            #expect(store.identity == Storage.signedOutToken)

            // And back in as the same account.
            store.open(for: account)
            let kept = try wines(in: store.container)
            #expect(kept.count == 1)
            #expect(kept.first?.name == "Brunate")
            #expect(store.failure == nil)
        }
    }

    @Test("The signed-out state opens an empty store, holding nobody's bottles")
    func theSignedOutStoreIsEmpty() throws {
        try withTemporaryAccounts(["first", "second"]) { ids in
            let (first, second) = (ids[0], ids[1])

            let store = CellarStore()
            store.open(for: first)
            let writeFirst = ModelContext(store.container)
            writeFirst.insert(bottle("Brunate"))
            try writeFirst.save()

            store.open(for: second)
            let writeSecond = ModelContext(store.container)
            writeSecond.insert(bottle("Cannubi"))
            try writeSecond.save()

            store.open(for: nil)
            #expect(store.identity == Storage.signedOutToken)
            #expect(try wines(in: store.container).isEmpty,
                    "a signed-out app is showing an account's cellar")

            // Nothing entered while signed out reaches either account's file:
            // the signed-out container is in memory only.
            let orphan = ModelContext(store.container)
            orphan.insert(bottle("Ghost"))
            try orphan.save()

            store.open(for: first)
            #expect(try wines(in: store.container).map(\.name) == ["Brunate"])
            store.open(for: second)
            #expect(try wines(in: store.container).map(\.name) == ["Cannubi"])
        }
    }

    @Test("Re-opening the account already open does not tear the store down")
    func openingTheSameAccountTwiceIsANoOp() {
        withTemporaryAccounts(["stable"]) { ids in
            let account = ids[0]
            let store = CellarStore()
            store.open(for: account)

            let first = store.container
            store.open(for: account)

            // The view tree is rebuilt off `identity`; swapping the container
            // for an identical one would throw away every `@Query` for nothing.
            #expect(store.container === first)
            #expect(store.identity == CellarStore.token(for: account))
        }
    }

    @Test("Every store file these tests create is cleaned up again")
    func temporaryStoresAreRemoved() throws {
        var url: URL?
        var account: String?
        try withTemporaryAccounts(["swept"]) { ids in
            account = ids[0]
            url = CellarStore.storeURL(for: ids[0])
            let write = ModelContext(try container(for: ids[0]))
            write.insert(bottle("Brunate"))
            try write.save()
            #expect(FileManager.default.fileExists(atPath: try #require(url).path))
            #expect(residue(of: ids[0]).isEmpty == false)
        }
        // `withTemporaryAccounts` removed it on the way out — this suite adds
        // nothing permanent to Application Support, sidecars and SwiftData's
        // hidden `_SUPPORT` directory included.
        #expect(FileManager.default.fileExists(atPath: try #require(url).path) == false)
        #expect(residue(of: try #require(account)).isEmpty,
                "a temporary account left files behind in Application Support")
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
