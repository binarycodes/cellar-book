import AVFoundation
import PhotosUI
import SwiftUI

/// Live camera preview layer bridged into SwiftUI.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct ScanView: View {
    @Environment(AppState.self) private var app
    @State private var camera = CameraController()
    @State private var reading = false
    @State private var pickerItem: PhotosPickerItem?

    /// The design's 186×330 label frame.
    private let frameSize = CGSize(width: 186, height: 330)

    var body: some View {
        ZStack {
            Palette.scanGround.ignoresSafeArea()

            if case .running = camera.status {
                CameraPreview(session: camera.session).ignoresSafeArea()
                // Vignette so the guides stay legible over a bright shelf.
                RadialGradient(
                    colors: [.clear, .black.opacity(0.55)],
                    center: .init(x: 0.5, y: 0.42), startRadius: 120, endRadius: 460
                )
                .ignoresSafeArea()
            } else {
                RadialGradient(
                    colors: [Palette.rose(0.10), .clear],
                    center: .init(x: 0.5, y: 0.42), startRadius: 0, endRadius: 380
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                scanFrame
                Spacer(minLength: 0)
                controls
            }
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadFromLibrary(item) }
        }
    }

    private var topBar: some View {
        HStack {
            Text("Scan a label").eyebrow(0.6)
            Spacer()
            Button {
                camera.stop()
                app.go(.cellar)
            } label: {
                Text("Cancel")
                    .font(Typo.sans(15, 500))
                    .foregroundStyle(Palette.rose(0.75))
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 54)
    }

    private var scanFrame: some View {
        ZStack {
            CornerGuides()
                .frame(width: frameSize.width, height: frameSize.height)

            if reading {
                ScanLine()
                    .frame(width: frameSize.width - 16, height: frameSize.height)
            }
        }
        .overlay(alignment: .bottom) {
            if reading {
                VStack(spacing: 6) {
                    Text("Reading the label").eyebrow(0.55)
                    Text("Producer, year, appellation…")
                        .font(Typo.sans(15, 500))
                        .foregroundStyle(.white)
                }
                .offset(y: 96)
                .transition(.opacity)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Text(message)
                .font(Typo.sans(12))
                .lineSpacing(12 * 0.45)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: 260)

            if canCapture {
                Button { Task { await capture() } } label: {
                    Image(systemName: "viewfinder")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 70, height: 70)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Palette.rose(0.25), lineWidth: 2))
                }
                .disabled(reading)
            } else {
                // No camera (simulator, or access denied) — the library feeds
                // the identical OCR path.
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 70, height: 70)
                        .background(.white, in: Circle())
                        .overlay(Circle().stroke(Palette.rose(0.25), lineWidth: 2))
                }
                .disabled(reading)
            }

            Button {
                app.form = WineForm()
                app.go(.review)
            } label: {
                Text("Enter it by hand")
                    .font(Typo.sans(14, 500))
                    .foregroundStyle(Palette.rose(0.7))
                    .frame(height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }

    /// Device presence alone is not enough — a denied permission or a failed
    /// configuration leaves a camera that exists but cannot be used, and the
    /// library fallback must take over.
    private var canCapture: Bool {
        if case .unavailable = camera.status { return false }
        return camera.isAvailable
    }

    private var message: String {
        switch camera.status {
        case .unavailable(let why): why
        default: "Fill the frame with the front label. Everything is editable afterwards."
        }
    }

    // MARK: - Capture

    private func capture() async {
        withAnimation { reading = true }
        defer { withAnimation { reading = false } }
        guard let image = try? await camera.capture() else { return }
        await handle(image)
    }

    private func loadFromLibrary(_ item: PhotosPickerItem) async {
        withAnimation { reading = true }
        defer { withAnimation { reading = false }; pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await handle(image)
    }

    /// OCR the frame, then hand the result to the Review screen for correction.
    private func handle(_ image: UIImage) async {
        let result = await LabelScanner.read(image)
        let photo = image.jpegData(compressionQuality: 0.8)
        camera.stop()
        app.form = WineForm(reading: result, photo: photo, currency: Settings.defaultCurrency)
        app.go(.review)
    }
}

/// The four bracket corners around the label frame.
private struct CornerGuides: View {
    private let arm: CGFloat = 26
    private let thickness: CGFloat = 2
    private var color: Color { Palette.rose(0.8) }

    var body: some View {
        ZStack {
            corner(h: .leading,  v: .top)
            corner(h: .trailing, v: .top)
            corner(h: .leading,  v: .bottom)
            corner(h: .trailing, v: .bottom)
        }
    }

    /// One bracket: a horizontal arm and a vertical arm meeting at a corner.
    private func corner(h: HorizontalAlignment, v: VerticalAlignment) -> some View {
        let alignment = Alignment(horizontal: h, vertical: v)
        return ZStack(alignment: alignment) {
            Color.clear
            Rectangle().fill(color).frame(width: arm, height: thickness)
            Rectangle().fill(color).frame(width: thickness, height: arm)
        }
    }
}

/// The sweeping red read-line, matching the design's `scanline` keyframes.
private struct ScanLine: View {
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Palette.scanLine)
                .frame(height: 2)
                .shadow(color: Palette.red.opacity(0.65), radius: 10)
                .offset(y: down ? geo.size.height * 0.88 : geo.size.height * 0.08)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: down)
                .onAppear { down = true }
        }
    }
}
