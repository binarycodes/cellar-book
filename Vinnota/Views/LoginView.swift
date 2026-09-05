import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthController.self) private var auth
    @State private var busy = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Palette.ground

                // Cellar photograph occupying the top 56%, fading into the
                // ground. Measured from a GeometryReader at the root so the
                // fraction is of the full screen, not of the safe-area box.
                cellarWall
                    .frame(width: geo.size.width, height: geo.size.height * 0.56)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.35), location: 0),
                                .init(color: Palette.ground.opacity(0.15), location: 0.40),
                                .init(color: Palette.ground, location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                content
                    .padding(.horizontal, 26)
                    .padding(.bottom, 52)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(Palette.ink)
    }

    /// The design's cellar photograph. The asset could not be exported from
    /// the design project (see the imageset's README), so this falls back to a
    /// cellar-dark gradient rather than showing a broken image.
    @ViewBuilder
    private var cellarWall: some View {
        if UIImage(named: "CellarWall") != nil {
            Image("CellarWall")
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 61/255, green: 20/255, blue: 30/255),
                    Color(red: 38/255, green: 12/255, blue: 20/255),
                    Palette.ground,
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Vinnota").eyebrow(0.55)
                .padding(.bottom, 14)

            // The design caps the headline at 15ch and the standfirst at 28ch,
            // which is what puts the line breaks where they belong.
            Text("A book for every bottle you meet.")
                .font(Typo.serif(44))
                .tracking(-44 * 0.015)
                .lineSpacing(44 * 0.02)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330, alignment: .leading)

            Text("Scan it on the shelf, keep the note, record what it did in the glass.")
                .font(Typo.sans(15))
                .lineSpacing(15 * 0.5)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 250, alignment: .leading)
                .padding(.top, 14)
                .padding(.bottom, 30)

            VStack(spacing: 9) {
                Button {
                    Task { busy = true; await auth.signInWithApple(); busy = false }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "apple.logo").font(.system(size: 17, weight: .medium))
                        Text("Continue with Apple").font(Typo.sans(15, 500))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Palette.burgundy)
                    .foregroundStyle(Palette.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
                .disabled(busy)

                Text("Apple sign-in only. No password is created, stored, or ever seen.")
                    .font(Typo.sans(11))
                    .lineSpacing(11 * 0.5)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 12)
                    .padding(.horizontal, 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = auth.lastError {
                    Text(error)
                        .font(Typo.sans(11))
                        .foregroundStyle(Palette.rosePink)
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
