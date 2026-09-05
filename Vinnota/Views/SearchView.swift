import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(AppState.self) private var app
    @Query(sort: \Wine.createdAt, order: .reverse) private var wines: [Wine]
    @FocusState private var focused: Bool

    private var results: [Wine] {
        wines.filter { $0.matches(query: app.query) && app.searchFilter.matches($0) }
    }

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17))
                            .foregroundStyle(Palette.textMuted)
                            .padding(.leading, 12)
                            .padding(.trailing, 8)
                        TextField("", text: $app.query, prompt:
                            Text("Producer, region, grape").foregroundStyle(Palette.rose(0.40))
                        )
                        .font(Typo.sans(16))
                        .foregroundStyle(.white)
                        .autocorrectionDisabled()
                        // Search fields do not autocapitalise; matching is
                        // case-insensitive, so a forced capital is only noise.
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                        .padding(.trailing, 12)
                    }
                    .frame(height: 46)
                    .background(Palette.fieldFill)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))

                    Button {
                        focused = false
                        app.go(.cellar)
                    } label: {
                        Text("Done")
                            .font(Typo.sans(15, 500))
                            .foregroundStyle(Palette.rosePink)
                            .frame(height: 44)
                    }
                }
                .padding(.bottom, 14)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 18) {
                        ForEach(WineFilter.allCases) { f in
                            FilterChip(label: f.label, active: app.searchFilter == f) {
                                app.searchFilter = f
                            }
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.borderHair).frame(height: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 54)

            ScrollView {
                Text(results.count == 1 ? "1 bottle" : "\(results.count) bottles")
                    .sectionLabel()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                if results.isEmpty {
                    Text(wines.isEmpty ? "The book is empty." : "No bottle matches that.")
                        .font(Typo.sans(14))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 56)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(results) { wine in
                        SearchRow(wine: wine) {
                            focused = false
                            app.selected = wine
                            app.go(.detail)
                        }
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .background(Palette.ground)
        .onAppear { focused = true }
    }
}

/// A dense list row with the status rail down its leading edge.
struct SearchRow: View {
    let wine: Wine
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 13) {
                Text(wine.displayVintage)
                    .font(Typo.sans(15, 500).monospacedDigit())
                    .foregroundStyle(Palette.rose(0.55))
                    .frame(width: 42, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(wine.producer)
                        .font(Typo.sans(15, 600))
                        .tracking(-15 * 0.01)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if !wine.subtitle.isEmpty {
                        Text(wine.subtitle)
                            .font(Typo.sans(13))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TagPill(text: wine.verdict?.label ?? wine.statusLabel)
            }
            .padding(.leading, 17)
            .padding(.trailing, 20)
            .padding(.vertical, 15)
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3)
                    .fill(wine.accent)
                    .frame(width: 3)
                    .padding(.vertical, 11)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.borderFaint).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
