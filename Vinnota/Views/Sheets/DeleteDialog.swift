import SwiftData
import SwiftUI

/// The centred confirmation. Only untasted bottles reach it.
struct DeleteDialog: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    let wine: Wine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Delete this bottle?")
                .font(Typo.serif(25))
                .tracking(-25 * 0.01)
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 8)

            Text("\(wine.producer) \(wine.vintage) and every note on it go for good. "
                 + "Untasted bottles only — tasted ones stay on the record.")
                .font(Typo.sans(14))
                .lineSpacing(14 * 0.55)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 22)

            HStack(spacing: 8) {
                Button { app.closeSheet() } label: {
                    Text("Keep")
                        .font(Typo.sans(15, 500))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(.white)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
                }
                Button { confirm() } label: {
                    Text("Delete")
                        .font(Typo.sans(15, 600))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Palette.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.borderHair, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func confirm() {
        context.delete(wine)
        try? context.save()
        app.selected = nil
        app.closeSheet()
        app.go(.cellar)
        app.showToast("Deleted")
    }
}
