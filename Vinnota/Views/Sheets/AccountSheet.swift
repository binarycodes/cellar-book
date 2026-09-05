import PhotosUI
import SwiftData
import SwiftUI

/// The account sheet behind the header avatar — where signing out lives.
///
/// The design leaves the avatar decorative, so this is an addition rather than
/// a transcription. It follows the design's own bottom-sheet vocabulary, and
/// is the natural home for the preferences in `Settings` if they ever surface.
struct AccountSheet: View {
    @Environment(AppState.self) private var app
    @Environment(AuthController.self) private var auth
    @Query private var wines: [Wine]
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        // `PhotosPicker`'s label closure is not main-actor isolated, so these
        // are read here and captured as plain values rather than touched from
        // inside it.
        let avatar = auth.avatar
        let initials = auth.initials

        return BottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Account").eyebrow(0.5)
                    .padding(.bottom, 16)

                HStack(spacing: 13) {
                    // Apple supplies no picture, so the user provides one.
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            AvatarView(image: avatar, initials: initials, size: 52)
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 18, height: 18)
                                .background(Palette.burgundy, in: Circle())
                                .overlay(Circle().stroke(Palette.surface, lineWidth: 2))
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(auth.displayName ?? "No name on file")
                            .font(Typo.serif(21))
                            .tracking(-21 * 0.005)
                            .foregroundStyle(auth.displayName == nil ? Palette.textTertiary : Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(auth.email ?? "No email on file")
                            .font(Typo.sans(13))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(providerLine)
                            .font(Typo.sans(11))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                .padding(.bottom, 20)

                // A local session is never allowed to look like a real one.
                if auth.isStubbedSession {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 14))
                        Text("Sign in with Apple is not provisioned on this build, "
                             + "so this is a local account on this device only.")
                            .font(Typo.sans(12))
                            .lineSpacing(12 * 0.4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.rosePink)
                    .padding(.bottom, 20)
                }

                if identityIsPartial {
                    Text("Apple shares a name and email only the first time you "
                         + "sign in, and only if you allow it. Anything missing "
                         + "here was not shared.")
                        .font(Typo.sans(12))
                        .lineSpacing(12 * 0.45)
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 16)
                }

                Text("The cellar stays on this device. Signing out leaves "
                     + "\(wines.count == 1 ? "1 bottle" : "\(wines.count) bottles") in the book.")
                    .font(Typo.sans(12))
                    .lineSpacing(12 * 0.45)
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                pickerHandler.frame(height: 0)

                SplitActionRow(secondaryTitle: "Close", primaryTitle: "Sign out") {
                    app.closeSheet()
                } primary: {
                    app.closeSheet()
                    app.reset()
                    auth.signOut()
                }
            }
        }
    }

    private var pickerHandler: some View {
        Color.clear.onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    auth.setAvatar(data)
                }
                pickerItem = nil
            }
        }
    }

    private var providerLine: String {
        auth.isStubbedSession ? "Local account" : "Signed in with Apple"
    }

    /// Apple hands over name and email only at the first authorization, and
    /// "Hide My Email" substitutes a private relay address. When either is
    /// absent the reason is explained rather than left looking broken.
    private var identityIsPartial: Bool {
        !auth.isStubbedSession && (auth.displayName == nil || auth.email == nil)
    }
}
