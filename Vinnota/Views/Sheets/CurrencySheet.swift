import SwiftUI

struct CurrencySheet: View {
    @Environment(AppState.self) private var app

    private var current: CurrencyCode {
        app.currencyTarget == .buy ? app.buy.currency : app.form.currency
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHandle().padding(.top, 18).padding(.bottom, 16)

            Text("Currency")
                .eyebrow(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            ForEach(CurrencyCode.allCases) { code in
                Button { pick(code) } label: {
                    HStack {
                        HStack(spacing: 12) {
                            Text(code.symbol)
                                .font(Typo.sans(15, 600))
                                .frame(width: 24, alignment: .leading)
                            Text("\(code.rawValue) — \(code.name)")
                                .font(Typo.sans(15))
                        }
                        Spacer()
                        if code == current {
                            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Palette.rose(0.08)).frame(height: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .background(Palette.surface)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 15, topTrailingRadius: 15))
        .overlay(alignment: .top) { Rectangle().fill(Palette.borderHair).frame(height: 1) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Picking for the purchase sheet returns to it rather than dismissing —
    /// the design reopens `bought` so the half-filled form is not lost.
    private func pick(_ code: CurrencyCode) {
        if app.currencyTarget == .buy {
            app.buy.currency = code
            app.present(.bought)
        } else {
            app.form.currency = code
            app.closeSheet()
        }
    }
}
