<div align="center">

# Blur

**The private photo app that organizes itself.**

*As smooth as Apple Photos. Better power under the hood.*
*Free · anonymous · nothing ever leaves your phone.*

`iOS 17+` · `On-device` · `No account` · `No network` · `A Nuke product — the first`

</div>

---

## The three questions

Every serious conversation about this product starts here. So does this README.

**What is it?**
Blur is a private iPhone photo app that organizes your library *for* you. It
finds the photos you missed, groups them without you sorting by hand, and lets
you flip straight to the one you mean to show — while everything else stays
blurred. It feels like Apple Photos; it runs on an engine Apple Photos doesn't have.

**What does it cost?**
- *To run:* ~**$0** — the free tier is entirely on-device. No servers, no cloud.
- *To build:* **low** — Blur reuses a proven iOS shell and an existing
  image-intelligence engine. The free app is a re-skin of shipping plumbing.
- *To the user:* free, with an optional **~$20–30/yr** tier for fully automatic
  organization — undercutting the predatory weekly-priced "cleaner" apps that
  dominate the category today.

**Who is it for?**
People with a life worth showing and a camera roll too full to find it —
enthusiasts, collectors, makers, parents. The wedge is the *show-and-tell*
moment: handing someone your phone and landing on exactly the right photo.
Privacy-conscious iPhone users are the broad market; this is the beachhead.

---

## Why it exists

The default photo app creates the pain we solve. Apple Photos hits real walls
at scale — smart albums choke past a few dozen, there's no "find the strays that
belong in this album" flow, and nothing lets you present a group *safely*. The
category that monetizes around this is owned by **manual**, swipe-to-clean apps
with **aggressive weekly pricing**. The position no one owns at scale —
**private, passive, on-device** — is exactly where Blur sits.

And it's possible *now*: Apple's on-device Vision framework and (iOS 26)
Foundation Models make private, server-free intelligence real for the first time.

---

## How it works (under the hood)

Three pillars, one promise — *smoothness like Apple Photos, with an engine that
actually organizes.*

| Pillar | What the user feels | What's under it |
|---|---|---|
| **Private by nature** | No account, works in airplane mode | Everything on-device; nothing transmitted |
| **Quietly ordered** | It organizes itself; finds what you missed | Apple-tag seed → on-device clustering → stray-finder |
| **Shown with intention** | Flip to the one that matters; the rest softens | Native PhotoKit rendering + focus/blur |

**The reuse story (why this is cheap and fast):** Blur is forked from a proven,
App-Store-runbooked iOS app and **inverted** — the original *uploads* photos to
a backend; Blur removes the upload entirely and keeps the bytes on the phone.
The expensive parts already exist; what's left is a re-skin and one net-new
clustering layer.

---

## What it is / what it is NOT

Tight scope is the product, not a limitation.

**It IS:** a private, passive iPhone photo organizer — self-building galleries,
a stray-finder that completes albums you started, flip-to-show, instant retrieval.
All on-device. No account.

**It is NOT (v1):** a cloud backup, a social feed, a photo editor, a storage
cleaner, an Android app, or anything that requires an account or sends your
photos anywhere. *Every "not" is what keeps the promise.*

---

## Status & roadmap

- ✅ **v0 — free tier scaffold** (`ios/`): pure local, no backend, no account.
  Galleries from your albums, tap-to-hide (blur), Show mode. Ready to build.
- ◻︎ **v0 → TestFlight → App Store** — see [`docs/app-store.md`](docs/app-store.md).
- ◻︎ **Paid tier — automatic image handling** — on-device clustering + stray
  finder, gated by a managed subscription. See [`docs/build-plan.md`](docs/build-plan.md).

---

## Repository map

```
blur/
├── README.md            ← you are here
├── ios/                 ← the native iOS app (SwiftUI, PhotoKit, iOS 17+)
│   ├── project.yml         XcodeGen spec — bundle ag.nuke.blur, no dependencies
│   ├── generate.sh         generate the .xcodeproj + a monotonic build number
│   ├── PrivacyInfo.xcprivacy   privacy manifest — collects nothing
│   └── Sources/Blur/       the app
├── web/                 ← the free landing page (static, Vercel-ready)
│   └── index.html
└── docs/
    ├── doctrine.md         the fixed points — stance + design-as-infrastructure
    ├── product.md          Product · Cost · Client — the pitch, in full
    ├── deck/               the investor deck (open index.html)
    ├── app-store-listing.md  name, subtitle, description, keywords
    ├── build-plan.md       architecture, reuse ledger, phased plan
    └── app-store.md        TestFlight → App Store runbook
```

## Build the app

The `.xcodeproj` is generated, never committed.

```bash
brew install xcodegen
cd ios
./generate.sh        # also stamps a fresh, monotonic build number
open Blur.xcodeproj
```

In Xcode: target **Blur** → Signing & Capabilities → set your **Team** → run.

## Privacy

The privacy claim is literally true: **Data Not Collected.** All processing is
on-device; the free app makes no network calls and runs in airplane mode. The
honesty is the marketing.

---

<div align="center">

**Blur** — a [Nuke](https://github.com/sss97133) product.
*The discipline: measure, don't guess. Ship small, learn fast. Private by architecture.*

</div>
