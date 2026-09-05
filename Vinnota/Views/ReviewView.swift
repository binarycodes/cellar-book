import PhotosUI
import SwiftData
import SwiftUI

/// "Check the reading" — the correction pass over whatever OCR produced.
struct ReviewView: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var pickerItem: PhotosPickerItem?

    /// The screen doubles as the edit form for a bottle already in the book.
    private var isEditing: Bool { app.editing != nil }

    /// There is no reading to check when the bottle was typed in by hand, or
    /// when OCR came back with nothing.
    private var title: String {
        if isEditing { return "Edit the bottle" }
        return app.form.recognized ? "Check the reading" : "Enter it by hand"
    }

    var body: some View {
        @Bindable var app = app

        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                form(app: app)
            }

            // The save bar floats over the scroll, on the design's fade.
            VStack(spacing: 10) {
                if !app.form.isComplete {
                    Text("Add \(String.list(app.form.missingRequired)) first.")
                        .font(Typo.sans(12))
                        .foregroundStyle(Palette.rosePink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PrimaryButton(title: isEditing ? "Save changes" : "Add to the book",
                              enabled: app.form.isComplete) { save() }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
            .background(Palette.ground)
            // A fixed fade strip ABOVE the bar rather than a gradient behind
            // it: the bar's height changes with the hint, and a proportional
            // gradient leaves the hint sitting in the translucent part.
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Palette.ground.opacity(0), Palette.ground],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 28)
                .offset(y: -28)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Palette.ground)
        .task(id: pickerItem) { await loadPickedPhoto() }
    }

    /// Entering by hand skips the camera, so the label photo is offered here —
    /// which also lets a bottle saved without one pick one up later, from edit.
    @ViewBuilder private var photoRow: some View {
        if let data = app.form.labelPhoto, let ui = UIImage(data: data) {
            HStack(spacing: 14) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 62, height: 88)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.border, lineWidth: 1))
                VStack(alignment: .leading, spacing: 9) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        OutlineLabel(title: "Replace", height: 34, fillsWidth: false)
                    }
                    Button { app.form.labelPhoto = nil } label: {
                        Text("Remove")
                            .font(Typo.sans(13))
                            .foregroundStyle(Palette.rose(0.6))
                            .frame(height: 30)
                            .contentShape(Rectangle())
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                OutlineLabel(title: "Add a label photo", icon: "photo.on.rectangle")
            }
        }
    }

    private func loadPickedPhoto() async {
        guard let item = pickerItem else { return }
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        app.form.labelPhoto = image.jpegData(compressionQuality: 0.8)
    }

    /// Backing out goes wherever the screen was entered from.
    private func leave() {
        if isEditing {
            app.editing = nil
            app.form = WineForm()
            app.go(.detail)
        } else {
            app.go(.scan)
        }
    }

    private var header: some View {
        HStack {
            Button { leave() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Palette.rose(0.75))
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(title).eyebrow(0.6)
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

    private func form(app: AppState) -> some View {
        @Bindable var app = app

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if app.form.recognized && !isEditing {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .medium))
                        Text("Read off the label — the year is the usual culprit.")
                            .font(Typo.sans(12))
                            .lineSpacing(12 * 0.4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Palette.rosePink)
                    .padding(.bottom, 22)
                }

                photoRow.padding(.bottom, 22)

                UnderlineField(placeholder: "Producer \u{00B7} required", text: $app.form.producer,
                               font: Typo.serif(30), bottomPadding: 10)
                    .padding(.bottom, 16)

                UnderlineField(placeholder: "Cuvée or grape", text: $app.form.name,
                               font: Typo.sans(17), bottomPadding: 9)
                    .padding(.bottom, 24)

                HStack(spacing: 14) {
                    labelled("Which year") {
                        BoxedField(placeholder: "2022", text: $app.form.vintage,
                                   keyboard: .numberPad, monospacedDigits: true)
                    }
                    labelled("Grape") {
                        BoxedField(placeholder: "Nebbiolo", text: $app.form.grape)
                    }
                }
                .padding(.bottom, 16)

                labelled("Region") {
                    BoxedField(placeholder: "Piemonte, IT", text: $app.form.region)
                }
                .padding(.bottom, 16)

                labelled("Where you found it") {
                    BoxedField(placeholder: "Shop, bar, cellar door", text: $app.form.shop)
                }
                .padding(.bottom, 16)

                if Settings.showShelfPrice {
                    labelled("Shelf price") {
                        HStack(spacing: 8) {
                            BoxedField(placeholder: "0.00", text: $app.form.price,
                                       keyboard: .decimalPad, monospacedDigits: true)
                            Button {
                                app.currencyTarget = .form
                                app.present(.currency)
                            } label: {
                                HStack {
                                    Text(app.form.currency.rawValue).font(Typo.sans(16))
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12)).opacity(0.6)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 11)
                                .frame(width: 104, height: 44)
                                .background(Palette.fieldFill)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.bottom, 28)
                }

                if !isEditing {
                Text("On the shelf").sectionLabel().padding(.bottom, 10)

                NoteEditor(placeholder: "What the shelf talker said, who pushed it on you, why you picked it up.",
                           text: $app.form.text)

                OutlineButton(title: "Add a note", icon: "square.and.pencil") {
                    app.voiceTarget = .form
                    app.present(.voice)
                }
                .padding(.top, 10)

                ForEach(Array(app.form.notes.enumerated()), id: \.offset) { _, note in
                    NoteBlock(icon: note.typed ? "text.alignleft" : "mic",
                              label: (note.typed ? "Typed" : "Dictated") + " · \(note.when)",
                              text: note.text, rule: Palette.rose(0.25))
                        .padding(.top, 12)
                }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, app.form.isComplete ? 130 : 165)
        }
    }

    private func labelled<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).sectionLabel()
            content()
        }
    }

    // MARK: - Save

    private func save() {
        guard app.form.isComplete else {
            app.showToast("Add \(String.list(app.form.missingRequired)) first.")
            return
        }
        let f = app.form

        if let existing = app.editing {
            f.apply(to: existing)
            try? context.save()

            app.form = WineForm()
            app.editing = nil
            app.selected = existing
            app.go(.detail)
            app.showToast("Changes saved")
            return
        }

        let wine = f.makeWine()
        context.insert(wine)
        for note in f.makeNotes() {
            note.wine = wine
            context.insert(note)
        }
        try? context.save()

        app.form = WineForm()
        app.selected = wine
        app.go(.detail)
        app.showToast("Added to the book")
    }
}
