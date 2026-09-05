# Testing Vinnota

Two passes: the Simulator covers most of it, a real device covers what it can't.

---

## Simulator (Xcode)

```bash
open Vinnota.xcodeproj
```

Pick **iPhone 17 Pro**, press **⌘R**.

**Feed it test photos first** — the Simulator's library has no wine labels.
Drag any image file onto the Simulator window, or:

```bash
xcrun simctl addmedia booted /path/to/label.jpg
```

Then walk this, in order:

| # | Do | Expect |
|---|---|---|
| 1 | Tap **Continue with Apple** | Signs in locally (no dev account). A yellow-ish note in the account sheet says so. |
| 2 | Tap **Scan a label** | Falls back to a photo-picker button — the Simulator has no camera. |
| 3 | Pick a wine label photo | Review screen pre-filled from OCR. Producer/year/grape/region as far as the label allows. |
| 3b | Clear the producer | **Add to the book** greys out and a line above it says "Add the producer first." Everything else is optional. |
| 3c | Enter by hand instead | Header reads "Enter it by hand" and an **Add a label photo** button offers the library. |
| 4 | Fill just the producer, **Add to the book** | Saves. Detail page shows "Added by hand", no invented year, no stray dashes, and the hero collapses since there is no photo. |
| 4b | Tap the pencil on the detail hero | Edit form, pre-filled. Change region and shop, **Save changes** — detail updates in place. Backing out returns to the bottle, not the scanner. |
| 4c | Tap a card's photo in the cellar grid | Opens the bottle. The whole tile is the tap target, not just the caption. |
| 4d | Open a bottle, **Add a note** | A composer opens with the keyboard up. Type and **Keep note** — it saves labelled "Typed", not "Dictated". |
| 4e | In the composer, **Dictate it instead** (real device) | Records, then folds the transcript into the same draft so you can keep typing. A note that mixes both is labelled "Dictated". |
| 4f | Decline the microphone, then **Add a note** | Still fully usable: the composer explains dictation is unavailable in one line and typing carries on. Never a dead end. |
| 5 | Tap **Want to try** / **Pass** | Tag and dot colour change. |
| 6 | **I bought it** → set price/currency → **Add to the rack** | Tag becomes "In the rack", provenance gains a "Bought" row, button becomes "Open the bottle". |
| 7 | **Open the bottle** → **Photograph the glass** → pick a photo → type a note → pick a verdict → **Mark as tasted** | Detail hero switches to the glass photo. Verdict pill appears. Trash icon disappears. |
| 8 | Tap the search icon, type part of a producer/grape/region | Filters live. Result count updates. |
| 9 | Open an **untasted** bottle → trash icon → **Delete** | Returns to the cellar, bottle gone. Tasted bottles have no trash icon at all. |
| 10 | Tap the avatar (top right) | Account sheet: name, email, provider, bottle count. Tap the avatar in the sheet to set a picture. |
| 11 | **Sign out**, then sign in again | Back to login. Cellar survives; avatar and name do not. |
| 12 | Quit and relaunch (⌘Q, ⌘R) | Everything still there. |

**Known Simulator limits** — not bugs:
- No camera, so scanning always uses the photo picker.
- **Dictation is disabled** and says so. See the device pass.

---

## Real device

Needed for the camera and dictation, and the only way to see it at true size.

### One-time setup

You have no paid Apple Developer account, so:

1. Xcode → **Settings → Accounts** → add your Apple ID (free is fine).
2. Select the **Vinnota** target → **Signing & Capabilities**:
   - tick **Automatically manage signing**
   - set **Team** to your Personal Team
   - change **Bundle Identifier** to something unique, e.g. `com.yourname.vinnota`
3. Plug the iPhone in, pick it as the run destination, **⌘R**.
4. First launch fails to open — on the phone: **Settings → General → VPN & Device Management** → trust your developer certificate. Launch again.

A free account's build **expires after 7 days**. Re-run from Xcode to renew.

> **Sign in with Apple will not work on a free account.** The entitlement needs a
> paid membership. Tapping the button falls through to a local account and says
> so. Everything else works normally.

### What to test that the Simulator can't

| # | Do | Expect |
|---|---|---|
| 1 | **Scan a label** on a real bottle | Live camera in the frame. Allow the camera prompt. |
| 2 | Fill the frame with the front label, tap the shutter | OCR fills the Review screen. Try 5–10 real bottles — this is the thing most worth measuring. |
| 3 | Deny camera access (Settings → Vinnota), reopen Scan | Falls back to the photo picker with an explanation. No dead button. |
| 4 | **Dictate a note** on any bottle | Allow mic + speech. Waveform moves with your voice, timer counts, **Stop and transcribe** produces editable text. **Keep note** files it. |
| 5 | While dictating, read Apple's permission dialog | It says speech may be sent to Apple — which contradicts the app's "on device" line. Decision pending, see OPEN-QUESTIONS §3.8. |
| 6 | Photograph an actual glass in the tasting screen | Appears as the detail hero afterwards. |
| 7 | Rotate / try a landscape photo as the pour | Layout stays put, nothing shifts sideways. |
| 8 | Settings → Display → **Larger Text**, max | Text does not currently scale. Known gap. |

---

## Checking a release build

Confirms the development sign-in stub is compiled out:

```bash
xcodebuild -scheme Vinnota -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

In a Release build, **Continue with Apple** must fail with an error and stay on
the login screen — it must never sign you in. If it signs you in, the stub
leaked into release and that is a bug to report.
