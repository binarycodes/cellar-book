import PhotosUI
import SwiftData
import SwiftUI

/// "Opened tonight" — the note taken while the bottle is being drunk.
struct TastingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    let wine: Wine

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var app = app

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                scroll(app: app)
            }

            VStack {
                PrimaryButton(title: "Mark as tasted", enabled: app.tasting.verdict != nil) {
                    markTasted()
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
        .background(Palette.ground)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    app.tasting.pourPhoto = data
                }
                pickerItem = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Button { app.go(.detail) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.rose(0.75))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text("Opened tonight").eyebrow(0.6)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.borderHair).frame(height: 1)
        }
    }

    private func scroll(app: AppState) -> some View {
        @Bindable var app = app

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Text(wine.displayVintage)
                        .font(Typo.serif(56).monospacedDigit())
                        .tracking(-56 * 0.02)
                        .foregroundStyle(Palette.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(wine.producer)
                            .font(Typo.serif(23))
                            .tracking(-23 * 0.005)
                            .foregroundStyle(Palette.ink)
                        Text(wine.subtitle)
                            .font(Typo.sans(13))
                            .foregroundStyle(Palette.rose(0.55))
                    }
                    .padding(.bottom, 2)
                }
                .padding(.bottom, 26)

                Text("The pour").sectionLabel().padding(.bottom, 11)
                pourPhoto(app: app).padding(.bottom, 26)

                Text("What it did").sectionLabel().padding(.bottom, 11)
                NoteEditor(placeholder: "Nose, structure, whether the second glass beat the first.",
                           text: $app.tasting.text, minHeight: 100)

                OutlineButton(title: "Add a note as you drink", icon: "square.and.pencil") {
                    app.voiceTarget = .tasting
                    app.present(.voice)
                }
                .padding(.top, 10)

                ForEach(Array(app.tasting.notes.enumerated()), id: \.offset) { _, note in
                    NoteBlock(icon: note.typed ? "text.alignleft" : "mic",
                              label: (note.typed ? "Typed" : "Dictated") + " · \(note.when)",
                              text: note.text, rule: Palette.rose(0.25))
                        .padding(.top, 14)
                }

                Text("The verdict").sectionLabel()
                    .padding(.top, 30).padding(.bottom, 11)

                VStack(spacing: 8) {
                    ForEach(Verdict.allCases) { verdict in
                        verdictRow(verdict, app: app)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 130)
        }
    }

    @ViewBuilder
    private func pourPhoto(app: AppState) -> some View {
        if let data = app.tasting.pourPhoto, let image = UIImage(data: data) {
            // Same reason as the detail hero: constrain the box, not the image.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 9))
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 9) {
                    Image(systemName: "camera").font(.system(size: 21))
                    Text("Photograph the glass").font(Typo.sans(14))
                }
                .foregroundStyle(Palette.rose(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 132)
                .background(Palette.rose(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
            }
        }
    }

    private func verdictRow(_ verdict: Verdict, app: AppState) -> some View {
        let active = app.tasting.verdict == verdict
        return Button {
            app.tasting.verdict = verdict
        } label: {
            HStack(spacing: 12) {
                Dot(color: verdict.dot, size: 10)
                Text(verdict.label)
                    .font(Typo.sans(15, 500))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Text(verdict.caption)
                    .font(Typo.sans(12))
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(.horizontal, 15)
            .frame(height: 56)
            .background(active ? Palette.rose(0.10) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(active ? verdict.dot : Palette.borderSoft, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Commit

    private func markTasted() {
        guard let verdict = app.tasting.verdict else {
            app.showToast("Pick a verdict first")
            return
        }
        let t = app.tasting

        if !t.text.isEmpty {
            let note = TastingNote(kind: .text, phase: .post, text: t.text)
            note.wine = wine
            context.insert(note)
        }
        for dictated in t.notes {
            let note = TastingNote(kind: dictated.typed ? .text : .voice, phase: .post,
                                   text: dictated.text, when: dictated.when)
            note.wine = wine
            context.insert(note)
        }

        wine.status = .tasted
        wine.verdict = verdict
        wine.openedAt = Formatters.today()
        if let photo = t.pourPhoto { wine.pourPhoto = photo }
        try? context.save()

        app.tasting.reset()
        app.go(.detail)
        app.showToast("Marked as tasted")
    }
}
