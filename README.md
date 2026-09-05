# Cellar Book

A wine notebook for your phone. Point it at a label in the shop, keep the
bottle, and remember what it was actually like when you opened it.

Made for the moment you are standing in an aisle holding something you have
never heard of, trying to decide.

---

## What it does

**Scan a label.** Photograph the bottle and the producer, year, grape and
region are read off it for you. Correct anything it got wrong — labels are
hard to read, and it will not always get them right.

**Or just type it in.** No camera, no signal, no patience: enter the name and
you are done. Everything else can wait, and you can add a label photo later.

**Say how keen you are.** Want to try, undecided, or pass. The passes matter as
much as the wants — that is how you stop buying the same disappointing bottle
twice.

**Keep a note.** Type it, or dictate it if your hands are full. What the
shopkeeper said, who recommended it, why you picked it up.

**Record the bottle you bought.** What you paid, how many, and where — which is
rarely what the shelf said.

**Taste it.** Photograph the glass, write what it was like, and give it a
verdict. Loved, fine, or no.

**Find it again.** Search across producer, cuvée, region, grape and shop, or
filter the shelf by where each bottle has got to.

## Your cellar stays on your phone

The book is stored on your device. There is no account to create beyond signing
in, nothing is uploaded, and no one else can see what you drink.

Two things to know:

- **It is not backed up anywhere by us.** Your cellar rides along in your normal
  encrypted iPhone backup. Without one, losing the phone loses the book.
- **Dictation uses Apple's speech recognition.** On many phones that happens on
  the device; where it cannot, Apple transcribes it. Either way the finished
  note is kept on your phone and nowhere else.

## Getting it running

Requires an iPhone or iPad on **iOS 17 or later**.

Open `Vinnota.xcodeproj` in Xcode, pick your device, and press run. Building to
a real iPhone needs a free Apple ID — [TESTING.md](TESTING.md) walks through the
signing set-up and what to try once it is installed.

## Known gaps

Being straight about what is not there yet:

- **No export.** The only copy is on the phone.
- **The camera and dictation are unverified on real hardware.** They are written
  and wired up, but the development machine has neither, so they have only been
  exercised through the photo library and a simulator.
- **One cellar per device.** Signing out leaves the bottles behind, so a second
  person on the same phone sees the first person's book.
- **English only, and no accessibility work yet** — text does not respond to
  Larger Text, and there are no VoiceOver labels.

---

Contributing or looking at the code? See [CLAUDE.md](CLAUDE.md).
