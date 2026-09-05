import SwiftData
import SwiftUI

struct CellarView: View {
    @Environment(AppState.self) private var app
    @Environment(AuthController.self) private var auth
    @Query(sort: \Wine.createdAt, order: .reverse) private var wines: [Wine]

    private var visible: [Wine] { wines.filter { app.filter.matches($0) } }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
        }
        .background(Palette.ground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cellar book").eyebrow()
                Spacer()
                HStack(spacing: 4) {
                    Button { app.go(.search) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Palette.rose(0.75))
                            .frame(width: 44, height: 44)
                    }
                    Button { app.present(.account) } label: {
                        AvatarView(image: auth.avatar, initials: auth.initials)
                    }
                }
            }
            .padding(.bottom, 16)

            Text("Cellar")
                .font(Typo.serif(52))
                .tracking(-52 * 0.015)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 20)

            stats
            filters
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
    }

    private var stats: some View {
        HStack(alignment: .bottom, spacing: 20) {
            stat(wines.count, "bottles in the book")
            stat(wines.filter { $0.status != .tasted }.count, "still unopened")
            stat(wines.filter { $0.verdict == .loved }.count, "loved")
            Spacer(minLength: 0)
        }
        .padding(.bottom, 18)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.borderHair).frame(height: 1)
        }
    }

    private func stat(_ n: Int, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(n)")
                .font(Typo.serif(34).monospacedDigit())
                .tracking(-34 * 0.01)
                .foregroundStyle(Palette.ink)
            Text(caption)
                .font(Typo.sans(11))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(WineFilter.allCases) { f in
                    FilterChip(label: f.label, active: app.filter == f) { app.filter = f }
                }
            }
        }
        .padding(.top, 13)
        .padding(.bottom, 11)
    }

    // MARK: - Grid

    private var list: some View {
        ScrollView {
            if visible.isEmpty {
                Text(wines.isEmpty
                     ? "Nothing in the book yet. Scan a label to begin."
                     : "Nothing filed under this yet.")
                    .font(Typo.sans(14))
                    .lineSpacing(14 * 0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 14, alignment: .top), GridItem(.flexible(), spacing: 14, alignment: .top)],
                    spacing: 22
                ) {
                    ForEach(visible) { wine in
                        WineCard(wine: wine) {
                            app.selected = wine
                            app.go(.detail)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 100)
    }
}

/// One tile in the cellar grid.
struct WineCard: View {
    let wine: Wine
    let open: () -> Void

    var body: some View {
        // The whole tile opens the bottle — photo, caption and the gaps between.
        // Wrapping only the caption left the photo, which is most of the tile,
        // dead to the touch.
        Button(action: open) {
            VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                // A clear 3:4 box sets the cell size; the photo rides on top as
                // an overlay and is clipped to it. Putting aspectRatio on the
                // image itself lets `.fill` expand the cell instead.
                Color.clear
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay {
                        if let data = wine.labelPhoto, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Palette.surface.overlay {
                                Text(wine.producer)
                                    .font(Typo.serif(15))
                                    .foregroundStyle(Palette.rose(0.42))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.7)
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                Dot(color: wine.accent, size: 8)
                    .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 3))
                    .padding(9)
            }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        if wine.hasVintage {
                            Text(wine.displayVintage)
                                .font(Typo.sans(13, 500).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                        if wine.hasPrice {
                            Text(wine.displayPrice)
                                .font(Typo.sans(13).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }

                    Text(wine.producer)
                        .font(Typo.serif(20))
                        .tracking(-20 * 0.005)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .padding(.top, 4)

                    if !wine.subtitle.isEmpty {
                        Text(wine.subtitle)
                            .font(Typo.serif(12.5, italic: true))
                            .foregroundStyle(Palette.rose(0.55))
                            .lineLimit(1)
                            .padding(.top, 3)
                    }

                    HStack(spacing: 6) {
                        Dot(color: wine.accent, size: 7)
                        Text(wine.verdict?.label ?? wine.statusLabel)
                            .font(Typo.sans(11.5))
                            .foregroundStyle(Palette.rose(0.6))
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
