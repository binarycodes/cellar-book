import AuthenticationServices
import Observation
import Security
import SwiftUI

/// Sign in with Apple.
///
/// The entitlement requires a paid Apple Developer Program membership. Without
/// it `ASAuthorizationController` fails with `ASAuthorizationError.unknown`
/// (code 1000), which would leave a development build unusable.
///
/// In DEBUG only, that specific failure falls through to a local account so the
/// app can be exercised before an account exists. **That path is compiled out
/// of release builds** — shipping it would let anyone in without authenticating.
/// A release build surfaces the error and stays signed out.
@Observable
@MainActor
final class AuthController: NSObject {
    enum State: Equatable {
        case signedOut
        case signedIn(userID: String, stubbed: Bool)
    }

    private(set) var state: State = .signedOut
    private(set) var lastError: String?
    /// Surfaced in the UI so a stubbed session is never mistaken for a real one.
    var isStubbedSession: Bool {
        if case .signedIn(_, let stubbed) = state { return stubbed }
        return false
    }

    private static let keychainAccount = "com.vinnota.appleUserID"
    private static let stubUserID = "stub.local.account"

    /// Apple returns `fullName` and `email` only on the FIRST authorization for
    /// a given Apple ID — every later sign-in leaves them nil. They are stored
    /// here at that one opportunity, or the account is nameless forever after.
    private static let nameKey = "com.vinnota.displayName"
    private static let emailKey = "com.vinnota.email"

    var displayName: String? { UserDefaults.standard.string(forKey: Self.nameKey) }
    var email: String? { UserDefaults.standard.string(forKey: Self.emailKey) }

    /// A profile picture the user chose.
    ///
    /// Sign in with Apple does NOT supply one — `ASAuthorizationAppleIDCredential`
    /// carries only the user ID, name and email, and Apple deliberately keeps the
    /// Apple ID photo away from third-party apps. So the picture is the user's
    /// own, stored on this device beside the session and cleared with it.
    private(set) var avatar: UIImage?

    private static var avatarURL: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("avatar.jpg")
    }

    func loadAvatar() {
        guard let url = Self.avatarURL, let data = try? Data(contentsOf: url) else {
            avatar = nil
            return
        }
        avatar = UIImage(data: data)
    }

    /// Stores a chosen picture, downscaled — a full camera frame is orders of
    /// magnitude larger than a 44pt circle can show.
    func setAvatar(_ data: Data) {
        guard let image = UIImage(data: data),
              let scaled = Self.downscale(image, to: 512),
              let jpeg = scaled.jpegData(compressionQuality: 0.85),
              let url = Self.avatarURL else { return }
        try? jpeg.write(to: url, options: .atomic)
        avatar = scaled
    }

    func clearAvatar() {
        if let url = Self.avatarURL { try? FileManager.default.removeItem(at: url) }
        avatar = nil
    }

    private static func downscale(_ image: UIImage, to maxEdge: CGFloat) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Initials for the header avatar, used until a picture is chosen.
    /// Returns nil when the account has no name — the design's "MK" was a
    /// mockup literal, and inventing initials for a real user is worse than
    /// showing a neutral symbol.
    var initials: String? {
        guard let name = displayName, !name.isEmpty else { return nil }
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? nil : String(letters).uppercased()
    }

    // MARK: - Lifecycle

    /// Re-establishes the session on launch. Apple can revoke a credential out
    /// of band, so a stored ID is verified before it is trusted.
    func restore() async {
        loadAvatar()
        guard let stored = Self.readKeychain() else { return }

        if stored == Self.stubUserID {
            #if DEBUG
            state = .signedIn(userID: stored, stubbed: true)
            #else
            // A stub session left by a development build is not a real one.
            Self.deleteKeychain()
            state = .signedOut
            #endif
            return
        }
        let provider = ASAuthorizationAppleIDProvider()
        let credentialState = try? await provider.credentialState(forUserID: stored)
        switch credentialState {
        case .authorized:
            state = .signedIn(userID: stored, stubbed: false)
        default:
            Self.deleteKeychain()
            state = .signedOut
        }
    }

    func signOut() {
        Self.deleteKeychain()
        // The name and email are dropped with the session. Apple will not hand
        // them over again on a later sign-in, so a returning user shows as
        // nameless — that is Apple's behaviour, not a bug here.
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        clearAvatar()
        state = .signedOut
    }

    /// Captures whatever Apple chose to share, at the only moment it is offered.
    private static func storeIdentity(from credential: ASAuthorizationAppleIDCredential) {
        if let name = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .default
            let formatted = formatter.string(from: name).trimmingCharacters(in: .whitespaces)
            if !formatted.isEmpty { UserDefaults.standard.set(formatted, forKey: nameKey) }
        }
        if let email = credential.email, !email.isEmpty {
            UserDefaults.standard.set(email, forKey: emailKey)
        }
    }

    // MARK: - Sign in with Apple

    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func signInWithApple() async {
        lastError = nil
        do {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]

            let auth = try await withCheckedThrowingContinuation { (c: CheckedContinuation<ASAuthorization, Error>) in
                self.continuation = c
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                controller.performRequests()
            }

            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                throw ASAuthorizationError(.invalidResponse)
            }
            Self.writeKeychain(credential.user)
            Self.storeIdentity(from: credential)
            state = .signedIn(userID: credential.user, stubbed: false)

        } catch let error as ASAuthorizationError where Self.isUnprovisioned(error) {
            #if DEBUG
            // Development convenience only — never in a shipped build.
            lastError = "Sign in with Apple is not provisioned on this build — signed in locally instead."
            signInStubbed()
            #else
            lastError = "Sign in with Apple is unavailable right now. Please try again."
            #endif

        } catch let error as ASAuthorizationError where error.code == .canceled {
            lastError = nil

        } catch {
            lastError = error.localizedDescription
        }
    }

    /// `.unknown` is what an unprovisioned entitlement reports; `.notHandled`
    /// covers a simulator with no iCloud account signed in.
    private static func isUnprovisioned(_ error: ASAuthorizationError) -> Bool {
        error.code == .unknown || error.code == .notHandled || error.code == .failed
    }

    // MARK: - Stub

    #if DEBUG
    /// A local-only session for development. No credential, no server, no
    /// password. Compiled out of release builds so it cannot be reached in
    /// a shipped app.
    func signInStubbed() {
        Self.writeKeychain(Self.stubUserID)
        state = .signedIn(userID: Self.stubUserID, stubbed: true)
    }
    #endif

    // MARK: - Keychain

    private static func writeKeychain(_ value: String) {
        deleteKeychain()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension AuthController: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            continuation?.resume(returning: authorization)
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AuthController: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
