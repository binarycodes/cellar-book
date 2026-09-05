import SwiftData
import SwiftUI

/// Composing a note. Typing is the primary path and dictation is an option
/// inside it — not everyone wants to say what they think of a wine out loud in
/// a shop, and a denied microphone must never be a dead end for note-taking.
///
/// Dictation appends into the same draft, so a note can be part spoken and part
/// typed, and whichever way it was written is recorded honestly on the note.
struct VoiceSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    @State private var speech = SpeechTranscriber()

    /// The note being written. Dictation lands here; so does the keyboard.
    @State private var draft = ""
    /// False as soon as any dictated text is folded in.
    @State private var typedOnly = true
    @FocusState private var writing: Bool

    var body: some View {
        BottomSheet {
            if case .recording = speech.phase {
                listening
            } else {
                composer
            }
        }
        .onDisappear { speech.reset() }
    }

    // MARK: - Composing

    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add a note").eyebrow(0.55).padding(.bottom, 12)

            // TextEditor is greedy; without a ceiling it takes the whole sheet.
            NoteEditor(placeholder: "What you are tasting, or anything worth remembering.",
                       text: $draft, minHeight: 140)
                .frame(maxHeight: 210)
                .focused($writing)

            dictateControl.padding(.top, 10)

            SplitActionRow(secondaryTitle: "Discard", primaryTitle: "Keep note") {
                app.closeSheet()
            } primary: {
                keep()
            }
            .padding(.top, 16)
        }
        .task { writing = true }
    }

    /// Offers dictation, or explains in one quiet line why it is unavailable.
    @ViewBuilder private var dictateControl: some View {
        if case .denied(let why) = speech.phase {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mic.slash").font(.system(size: 12))
                Text(why)
                    .font(Typo.sans(11))
                    .lineSpacing(11 * 0.45)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Palette.textMuted)
        } else {
            OutlineButton(title: draft.isBlank ? "Dictate it instead" : "Dictate more",
                          icon: "mic", height: 42, fillsWidth: false) {
                writing = false
                Task { await speech.start() }
            }
        }
    }

    // MARK: - Listening

    private var listening: some View {
        VStack(spacing: 18) {
            Text("Listening").eyebrow(0.55)

            HStack(spacing: 4) {
                ForEach(Array(speech.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Palette.rosePink)
                        .frame(width: 4, height: max(8, 48 * level))
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(height: 48)

            Text(speech.elapsed)
                .font(Typo.serif(40).monospacedDigit())
                .tracking(-40 * 0.01)
                .foregroundStyle(Palette.ink)

            Text("Transcribed by Apple's speech recognition. The finished note is kept on this phone.")
                .font(Typo.sans(12))
                .lineSpacing(12 * 0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: 250)

            Button { fold() } label: {
                Text("Stop and transcribe")
                    .font(Typo.sans(15, 500))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Palette.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    /// Stops recording and folds the transcript into the draft, so the user
    /// lands back in the editor with everything they have written so far.
    private func fold() {
        speech.stop()
        let heard = speech.transcript.trimmed
        guard !heard.isEmpty else { return }
        draft = draft.isBlank ? heard : draft.trimmed + " " + heard
        typedOnly = false
        speech.reset()
    }

    // MARK: - Commit

    /// Routes the note to whichever collection opened the sheet.
    private func keep() {
        let text = draft.trimmed
        guard !text.isEmpty else { app.closeSheet(); return }
        let when = Formatters.stamp()

        switch app.voiceTarget {
        case .form:
            app.form.notes.append((when: when, text: text, typed: typedOnly))
        case .tasting:
            app.tasting.notes.append((when: when, text: text, typed: typedOnly))
        case .detail:
            if let wine = app.selected {
                let note = TastingNote(kind: typedOnly ? .text : .voice,
                                       phase: wine.isTasted ? .post : .pre,
                                       text: text, when: when)
                note.wine = wine
                context.insert(note)
                try? context.save()
                app.showToast("Note added")
            }
        }
        app.closeSheet()
    }
}
