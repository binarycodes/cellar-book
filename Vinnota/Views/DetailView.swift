import SwiftData
import SwiftUI

struct DetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    let wine: Wine

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    content(wine: wine)
                }
            }
            .ignoresSafeArea(edges: .top)

            if !wine.isTasted { actionBar }
        }
        .background(Palette.ground)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            // A clear box fixes the hero at screen width x 330. Sizing the
            // image directly would let a landscape photo's intrinsic width leak
            // into layout and shove the whole screen sideways — `.clipped()`
            // hides the pixels but not the frame.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: heroHeight)
                .overlay {
                    // The pour wins over the label once the bottle has been
                    // opened — the design's hero is the photo of the glass.
                    if let image = heroImage {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Palette.surface
                    }
                }
                .clipped()
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .black.opacity(0.10), location: 0.32),
                        .init(color: Palette.ground.opacity(0.86), location: 0.78),
                        .init(color: Palette.ground, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            VStack(alignment: .leading, spacing: 0) {
                if !wine.eyebrow.isEmpty {
                    Text(wine.eyebrow).eyebrow(0.6)
                        .padding(.bottom, 8)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    if wine.hasVintage {
                        Text(wine.displayVintage)
                            .font(Typo.serif(68).monospacedDigit())
                            .tracking(-68 * 0.02)
                            .foregroundStyle(Palette.rose(0.92))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(wine.producer)
                            .font(Typo.serif(wine.hasVintage ? 27 : 34))
                            .tracking(-27 * 0.005)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !wine.displayName.isEmpty {
                            Text(wine.displayName)
                                .font(Typo.serif(15, italic: true))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .padding(.bottom, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Clears the back/edit/delete row, so a producer long enough to
            // wrap grows the hero instead of sliding under the buttons.
            .padding(.top, heroImage == nil ? 96 : 0)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(minHeight: heroHeight, alignment: .bottom)
        .overlay(alignment: .top) {
            HStack {
                CircleGlassButton(systemName: "chevron.left") { app.go(.cellar) }
                Spacer()
                HStack(spacing: 10) {
                    CircleGlassButton(systemName: "pencil", size: 18) {
                        app.form = WineForm(editing: wine)
                        app.editing = wine
                        app.go(.review)
                    }
                    if wine.canDelete {
                        CircleGlassButton(systemName: "trash", size: 18) { app.present(.delete) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 50)
        }
    }

    /// The hero is sized for a photograph. With no photo there is nothing to
    /// show at that size, so the screen gets the space back instead.
    private var heroHeight: CGFloat { heroImage == nil ? 178 : 330 }

    private var heroImage: UIImage? {
        if let data = wine.pourPhoto, let image = UIImage(data: data) { return image }
        if let data = wine.labelPhoto, let image = UIImage(data: data) { return image }
        return nil
    }

    // MARK: - Body

    @ViewBuilder
    private func content(wine: Wine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                TagPill(text: wine.statusLabel, foreground: Palette.rose(0.72))
                if let verdict = wine.verdict {
                    TagPill(text: verdict.label,
                            foreground: verdict.foreground,
                            background: verdict.background)
                }
            }
            .padding(.bottom, 24)

            if wine.showKeen { keenness.padding(.bottom, 28) }

            Text("The bottle").sectionLabel().padding(.bottom, 12)
            factGrid.padding(.bottom, 28)

            Text("Provenance").sectionLabel().padding(.bottom, 14)
            timeline.padding(.bottom, 30)

            Text("Before opening").sectionLabel().padding(.bottom, 14)
            preNotes

            OutlineButton(title: "Add a note", icon: "square.and.pencil", height: 42, fillsWidth: false) {
                app.voiceTarget = .detail
                app.present(.voice)
            }
            .padding(.bottom, 30)

            if wine.isTasted { inTheGlass }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 130)
    }

    private var keenness: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("How keen are you").sectionLabel()
            HStack(spacing: 7) {
                SegmentButton(title: "Want to try", active: wine.status == .want) {
                    set(.want, toast: "On the want-to-try list")
                }
                SegmentButton(title: "Undecided", active: wine.status == .maybe || wine.status == .new) {
                    set(.maybe, toast: nil)
                }
                SegmentButton(title: "Pass", active: wine.status == .not) {
                    set(.not, toast: "Passed")
                }
            }
        }
    }

    /// The design pads the grid to an even count so no cell is left orphaned.
    private var facts: [(String, String)] {
        var out: [(String, String)] = [
            ("Region", wine.region.isEmpty ? "—" : wine.region),
            ("Grape",  wine.grape.isEmpty  ? "—" : wine.grape),
            ("Found at", wine.shop.isEmpty ? "—" : wine.shop),
        ]
        if Settings.showShelfPrice {
            out.append(("Shelf price", wine.currency.format(wine.price)))
        }
        if wine.boughtPrice != nil {
            let paid = wine.boughtCurrency.format(wine.boughtPrice) + (wine.qty > 1 ? " ×\(wine.qty)" : "")
            out.append(("Paid", paid))
        }
        if out.count % 2 == 1 { out.append(("Bottles", "\(wine.qty)")) }
        return out
    }

    private var factGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 1), GridItem(.flexible(), spacing: 1)], spacing: 1) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.0).font(Typo.sans(11)).foregroundStyle(Palette.textMuted)
                    Text(fact.1).font(Typo.sans(14, 500)).foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Cells must fill the row, or a neighbour that wraps to two
                // lines leaves the grid's divider colour showing through.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Palette.ground)
            }
        }
        .background(Palette.rose(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    /// Provenance events, assembled in the same order as the design.
    private var events: [(what: String, when: String, detail: String, dot: Color)] {
        var out: [(String, String, String, Color)] = [
            (wine.addedByHand ? "Entered by hand" : "Scanned in the shop", wine.scannedAt, wine.shop, wine.status.rail)
        ]
        if wine.status == .want {
            out.append(("Tagged want to try", wine.scannedAt, "", Palette.rose(1.0)))
        }
        if wine.status == .not {
            out.append(("Passed on it", wine.scannedAt, "", Palette.rose(0.25)))
        }
        if let date = wine.boughtDate {
            // A bottle can be marked bought without recording what it cost;
            // the formatter returns an em dash for that, which read as a
            // stray "—" sitting under the event.
            var parts: [String] = []
            let price = wine.boughtCurrency.format(wine.boughtPrice)
            if !price.isBlank && price != "—" { parts.append(price) }
            if wine.qty > 1 { parts.append("\(wine.qty) bottles") }
            out.append(("Bought", date, parts.joined(separator: " · "), Palette.green))
        }
        if let opened = wine.openedAt {
            out.append(("Opened", opened, wine.verdict?.label ?? "", wine.verdict?.dot ?? .white))
        }
        return out
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.offset) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Dot(color: event.dot, size: 9).padding(.top, 4)
                        if index < events.count - 1 {
                            Rectangle().fill(Palette.rose(0.16))
                                .frame(width: 1)
                                .padding(.vertical, 4)
                        }
                    }
                    .frame(width: 10)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(event.what).font(Typo.sans(14, 500)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            Text(event.when)
                                .font(Typo.sans(12).monospacedDigit())
                                .foregroundStyle(Palette.textMuted)
                        }
                        if !event.detail.isEmpty {
                            Text(event.detail).font(Typo.sans(13)).foregroundStyle(Palette.rose(0.55))
                        }
                    }
                    .padding(.bottom, 18)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var preNotes: some View {
        if wine.preNotes.isEmpty {
            Text("No notes from the shop.")
                .font(Typo.sans(14))
                .foregroundStyle(Palette.textMuted)
                .padding(.bottom, 16)
        } else {
            ForEach(wine.preNotes) { note in
                NoteBlock(icon: note.kind == .voice ? "mic" : "pencil",
                          label: note.label, text: note.text)
                    .padding(.bottom, 18)
            }
        }
    }

    private var inTheGlass: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("In the glass").sectionLabel().padding(.bottom, 14)

            ForEach(wine.postNotes) { note in
                NoteBlock(icon: note.kind == .voice ? "mic" : "pencil",
                          label: note.label, text: note.text,
                          rule: wine.verdict?.dot ?? Palette.rose(0.35),
                          textOpacity: 0.92)
                    .padding(.bottom, 18)
            }

            Text("Tasted bottles stay on the record. Only untasted ones can be deleted.")
                .font(Typo.sans(11))
                .lineSpacing(11 * 0.5)
                .foregroundStyle(Palette.rose(0.4))
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack {
            PrimaryButton(
                title: wine.isBought ? "Open the bottle" : "I bought it",
                icon: wine.isBought ? "wineglass" : "cart"
            ) {
                if wine.isBought {
                    app.tasting.reset()
                    app.go(.tasting)
                } else {
                    app.currencyTarget = .buy
                    app.buy = BuyForm(
                        date: Formatters.today(),
                        qty: "1",
                        price: wine.price ?? "",
                        currency: wine.currency,
                        shop: wine.shop
                    )
                    app.present(.bought)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 40)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Palette.ground.opacity(0), location: 0),
                    .init(color: Palette.ground, location: 0.42),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .ignoresSafeArea(edges: .bottom)
    }

    private func set(_ status: WineStatus, toast: String?) {
        wine.status = status
        try? context.save()
        if let toast { app.showToast(toast) }
    }
}
