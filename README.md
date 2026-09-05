# Vinnota — Cellar Book

A native iOS app built from the Claude Design project
`Vinnota - Cellar Book.dc.html`. Scan a wine label on the shelf, keep the note,
record what the bottle did in the glass.

SwiftUI · iOS 17+ · SwiftData · Vision · Speech · AVFoundation

---

## Status

**Builds and runs.** Verified on Xcode 26.6 / iOS 26.5, iPhone 17 Pro
simulator, 2026-09-05. The full flow was exercised: sign in, scan a label
through Vision OCR, correct and file it, set keenness, record a purchase,
taste it with a verdict, search, and delete.

Two things are **not** verified, both for want of hardware:
- **The camera path.** No camera on this host, so scanning was tested through
  the photo-library fallback — same OCR code, different image source.
- **Dictation.** The Simulator cannot open an audio input on this virtualised
  host, so `SpeechTranscriber` refuses there rather than letting AudioToolbox
  abort the process. Needs a real device.

See [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) for both, plus the missing login
photograph and the decisions taken along the way.

```bash
open Vinnota.xcodeproj
```

Or from the command line:

```bash
xcodebuild -scheme Vinnota -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

---

## The screens

Seven states on one surface, mirroring the design's single `screen` variable
rather than a navigation stack — every screen paints its own chrome.

| Screen | File | What it does |
|---|---|---|
| Login | `LoginView` | Sign in with Apple, with a local stub fallback |
| Cellar | `CellarView` | Two-column grid, three stats, six filter tabs |
| Search | `SearchView` | Live filter over producer, cuvée, region, grape, shop |
| Scan | `ScanView` | Live camera + Vision OCR, photo-library fallback |
| Review | `ReviewView` | Correct what OCR read, then file the bottle |
| Detail | `DetailView` | Hero, facts, provenance timeline, notes |
| Tasting | `TastingView` | Photograph the pour, note it, pick a verdict |

Plus four overlays: dictation, currency picker, purchase, and delete
confirmation — with a toast for confirmations.

## The model

A bottle moves `new → want / maybe / not → bought → tasted`. Prices are dual:
the shelf price seen when scanned, and what was actually paid. Notes are split
`pre` (before opening) and `post` (in the glass), each either typed or
dictated. Tasted bottles cannot be deleted — they stay on the record.

## What is real, not simulated

The design fakes its scanner (a 1.6s delay and canned text) and its
transcription. Both are real here:

- **`LabelScanner`** — `VNRecognizeTextRequest` at `.accurate`, five languages,
  language correction off since labels are proper nouns. Fields are assigned by
  heuristic: the tallest text is the producer, a four-digit year in range is the
  vintage, and grape/region are matched against built-in lists. Boilerplate
  ("contains sulfites", "75cl", appellation legalese) is filtered out.
- **`SpeechTranscriber`** — `SFSpeechRecognizer` with
  `requiresOnDeviceRecognition`, honouring the design's on-device promise. The
  waveform is driven by real RMS levels off the audio buffer, not an animation.
- **`CameraController`** — `AVCaptureSession` with continuous autofocus. The
  simulator has no camera, so `isAvailable` is false there and the scan screen
  offers `PhotosPicker` into the identical OCR path.

## Design fidelity

Colours, type sizes, tracking, spacing and radii are transcribed from the
`.dc.html` rather than approximated. The palette lives in `Theme/Palette.swift`
with the source values in comments.

Instrument Sans ships as a **variable** font, and iOS will not interpolate a
variable axis — `UIFont(name:size:)` always returns the default instance. So
weights are produced by driving the `wght` axis through CoreText
(`Theme/Typography.swift`). Instrument Serif is bundled as static regular and
italic faces from Google Fonts (OFL).

## Layout

```
Vinnota/
  Theme/       Palette, Typography
  Model/       Wine, TastingNote, enums, AppState, Settings, Formatters
  Services/    AuthController, CameraController, LabelScanner, SpeechTranscriber
  Views/       one file per screen, Sheets/, Components/
  Resources/   bundled fonts
```

`Vinnota.xcodeproj` uses a file-system-synchronized group (`objectVersion 77`),
so adding a Swift file to `Vinnota/` is enough — no project edit needed.
