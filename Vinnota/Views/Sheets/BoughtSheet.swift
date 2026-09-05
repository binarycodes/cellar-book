import SwiftData
import SwiftUI

/// "Bought it" — what was actually paid, which the design notes is
/// "rarely the shelf price".
struct BoughtSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.modelContext) private var context
    let wine: Wine

    var body: some View {
        @Bindable var app = app

        BottomSheet {
            VStack(alignment: .leading, spacing: 0) {
                Text("Bought it")
                    .font(Typo.serif(26))
                    .tracking(-26 * 0.01)
                    .foregroundStyle(Palette.ink)
                    .padding(.bottom, 6)

                Text("What you actually paid — rarely the shelf price.")
                    .font(Typo.sans(13))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 22)

                HStack(spacing: 12) {
                    field("Date") {
                        BoxedField(placeholder: Formatters.today(), text: $app.buy.date, height: 46)
                    }
                    field("Bottles") {
                        BoxedField(placeholder: "1", text: $app.buy.qty,
                                   keyboard: .numberPad, monospacedDigits: true, height: 46)
                    }
                }
                .padding(.bottom, 14)

                field("Price paid") {
                    HStack(spacing: 8) {
                        BoxedField(placeholder: "0.00", text: $app.buy.price,
                                   keyboard: .decimalPad, monospacedDigits: true, height: 46)
                        Button {
                            app.currencyTarget = .buy
                            app.present(.currency)
                        } label: {
                            HStack {
                                Text(app.buy.currency.rawValue).font(Typo.sans(16))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down").font(.system(size: 12)).opacity(0.6)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .frame(width: 104, height: 46)
                            .background(Palette.fieldFill)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.border, lineWidth: 1))
                        }
                    }
                }
                .padding(.bottom, 14)

                field("Bought from") {
                    BoxedField(placeholder: "Shop, bar, cellar door", text: $app.buy.shop, height: 46)
                }
                .padding(.bottom, 22)

                SplitActionRow(secondaryTitle: "Cancel", primaryTitle: "Add to the rack") {
                    app.closeSheet()
                } primary: {
                    confirm()
                }
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).sectionLabel()
            content()
        }
    }

    private func confirm() {
        let b = app.buy
        wine.status = .bought
        wine.boughtPrice = b.price.isEmpty ? nil : b.price
        wine.boughtCurrency = b.currency
        wine.boughtDate = b.date
        wine.qty = Int(b.qty) ?? 1
        if !b.shop.isEmpty { wine.shop = b.shop }
        try? context.save()

        app.closeSheet()
        app.showToast("In the rack")
    }
}
