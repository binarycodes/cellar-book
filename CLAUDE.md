# Vinnota — developer notes

Native iOS app built from the Claude Design project
`Vinnota - Cellar Book.dc.html`.

SwiftUI · iOS 17+ · SwiftData · Vision · Speech · AVFoundation · Swift Testing

```bash
open Vinnota.xcodeproj
```

```bash
xcodebuild -scheme Vinnota -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

```bash
xcodebuild test -scheme Vinnota -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Repository conventions

**`main` is protected.** Work on a feature branch and open a PR; direct pushes
are rejected.

**Commit messages** are enforced by a committed hook. Enable it once per clone:

```bash
git config core.hooksPath .githooks
```

It requires a Conventional Commits subject of at most 100 characters, on a
**single line with no body**, and **no `Co-Authored-By` trailer**. Accepted
types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert.

**CI** (`.github/workflows/ci.yml`) builds Debug and Release, fails on any Swift
warning, runs the test suite, and asserts the debug sign-in stub is absent from
the Release binary. It is explicitly `contents: read` and publishes nothing.
Actions are pinned to commit SHAs; Dependabot opens one grouped PR a month.

## Layout

```
Vinnota/
  Theme/       Palette, Typography
  Model/       Wine, TastingNote, enums, AppState, Settings, Formatters
  Services/    AuthController, CameraController, LabelScanner, SpeechTranscriber
  Views/       one file per screen, Sheets/, Components/
  Resources/   bundled fonts
VinnotaTests/  Swift Testing suites
```

`Vinnota.xcodeproj` uses file-system-synchronized groups (`objectVersion 77`),
so adding a Swift file to `Vinnota/` or `VinnotaTests/` is enough — no project
edit needed.

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

Plus four overlays: note composer, currency picker, purchase, and delete
confirmation — with a toast for confirmations.

## The model

A bottle moves `new → want / maybe / not → bought → tasted`. Prices are dual:
the shelf price seen when scanned, and what was actually paid. Notes are split
`pre` (before opening) and `post` (in the glass), each either typed or
dictated.

Only the **producer** gates a save; everything else is optional and can be
filled in later from the edit screen. The reasoning is in OPEN-QUESTIONS §3.6a
— a form filled in a shop aisle that blocks on missing data produces no data,
not better data.

The form's commit path lives on `WineForm` (`makeWine`, `apply(to:)`,
`makeNotes`) rather than inside `ReviewView.save()`, so it is reachable from
tests. It was inlined once, and a mutation dropping `.trimmed` went undetected.

## What is real, not simulated

The design fakes its scanner (a 1.6s delay and canned text) and its
transcription. Both are real here:

- **`LabelScanner`** — `VNRecognizeTextRequest` at `.accurate`, five languages,
  language correction off since labels are proper nouns. Fields are assigned by
  heuristic: the tallest text is the producer, a four-digit year in range is the
  vintage, and grape/region are matched against built-in lists. `parse(_:)` is
  pure and directly unit-tested.
- **`SpeechTranscriber`** — `SFSpeechRecognizer`, preferring an on-device model
  where one exists and otherwise falling back to Apple's servers. The waveform
  is driven by real RMS levels off the audio buffer, not an animation.
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

## Unverified for want of hardware

- **The camera path.** No camera on the development host, so scanning is tested
  through the photo-library fallback — same OCR code, different image source.
  CI runners have no camera either, so this gap is not closed by CI.
- **Dictation.** The Simulator cannot open an audio input on this virtualised
  host, so `SpeechTranscriber` refuses there rather than letting AudioToolbox
  abort the process.

`TESTING.md` lists what to exercise on a real device.
