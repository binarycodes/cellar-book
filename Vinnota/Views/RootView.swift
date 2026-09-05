import SwiftData
import SwiftUI

/// The single-surface router. Every screen paints its own chrome, so this is a
/// ZStack of states rather than a NavigationStack.
struct RootView: View {
    @Environment(AuthController.self) private var auth
    @State private var app = AppState()

    /// Set when the on-disk cellar could not be opened at launch.
    var storeFailure: String?

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()

            switch auth.state {
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                book
                    .transition(.opacity)
            }
        }
        .environment(app)
        .preferredColorScheme(.dark)
        .task {
            if let storeFailure { app.showToast(storeFailure) }
        }
        .animation(.easeOut(duration: 0.25), value: auth.state)
    }

    // MARK: - Signed in

    private var book: some View {
        ZStack {
            screen
            if app.showsNav { scanBar }
            sheets
            toast
        }
        // The design's 402x874 frame includes the status-bar and home-indicator
        // zones and allocates its own padding for them (54pt top, 40pt bottom).
        // Taking the full canvas is what makes those numbers land where drawn.
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var screen: some View {
        switch app.screen {
        case .cellar:  CellarView()
        case .search:  SearchView()
        case .scan:    ScanView()
        case .review:  ReviewView()
        case .detail:
            if let wine = app.selected { DetailView(wine: wine) } else { CellarView() }
        case .tasting:
            if let wine = app.selected { TastingView(wine: wine) } else { CellarView() }
        }
    }

    /// The floating "Scan a label" action over the two list screens.
    private var scanBar: some View {
        VStack {
            Spacer()
            Button { app.go(.scan) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "viewfinder").font(.system(size: 20, weight: .medium))
                    Text("Scan a label").font(Typo.sans(15, 600))
                }
                .foregroundStyle(Palette.ink)
                .padding(.leading, 18)
                .padding(.trailing, 22)
                .frame(height: 52)
                .background(Palette.burgundy, in: Capsule())
                .shadow(color: .black.opacity(0.5), radius: 11, y: 6)
            }
            .padding(.top, 14)
            .frame(height: 86, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: Palette.ground.opacity(0), location: 0),
                        .init(color: Palette.ground.opacity(0.9), location: 0.34),
                        .init(color: Palette.ground, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var sheets: some View {
        // `switch` over an Optional needs the wrapped value bound first —
        // and binding it also drops the `.none` branch.
        if let sheet = app.sheet {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { app.closeSheet() }
                .transition(.opacity)

            switch sheet {
            case .voice:
                VStack { Spacer(); VoiceSheet() }.ignoresSafeArea(edges: .bottom)
            case .currency:
                VStack { Spacer(); CurrencySheet() }.ignoresSafeArea(edges: .bottom)
            case .bought:
                if let wine = app.selected {
                    VStack { Spacer(); BoughtSheet(wine: wine) }.ignoresSafeArea(edges: .bottom)
                }
            case .delete:
                if let wine = app.selected { DeleteDialog(wine: wine) }
            case .account:
                VStack { Spacer(); AccountSheet() }.ignoresSafeArea(edges: .bottom)
            }
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let message = app.toast {
            VStack {
                Spacer()
                ToastView(message: message)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 104)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}
