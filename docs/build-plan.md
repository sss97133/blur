# Blur — Build Plan

*Architecture, the reuse ledger, and the phased path to ship. Engineering's
source of truth.*

---

## Principle

Blur = a **proven iOS shell, inverted** + an **existing image engine,
generalized** + a **privacy-correct (mostly absent) backend**. We reuse the
expensive parts and build only the one differentiator. The free tier ships with
**no server at all**.

---

## Architecture (two tiers)

| | Free (v0) | Paid upgrade |
|---|---|---|
| Photos | on-device only | on-device; processed only via the provider the user chooses |
| Organization | Apple tags + manual | + on-device passive clustering |
| Account | **none** | none required; anonymous / device-scoped |
| Network | **none** | only the user's chosen provider, or opt-in managed inference |
| Backend | **none** | small & separate: purchase validation, optional managed inference, opt-in anonymous analytics |

The free tier needs no backend, no account, and makes no network calls — which
is what makes the privacy claim literally true and the run cost ~$0.

---

## Reuse ledger

**Reused (already proven):**
- iOS app shell — SwiftUI, PhotoKit scanning, background refresh, the XcodeGen +
  monotonic-build-number tooling, and a full App Store launch runbook. Forked
  from a shipping app and **inverted**: the upload path and location gate are
  removed; photos stay on the phone.
- Image-intelligence engine — entity grouping ("does this photo belong here?"),
  hero/cover selection, quality scoring, and perceptual-hash deduplication —
  generalized from a vehicle domain to any subject.
- A multi-provider AI router (supports local models and bring-your-own keys) for
  the paid tier.
- A first-party, **anonymous** analytics pattern for the learning loop.

**Net-new (the real engineering):**
- On-device subject clustering using Apple's Vision feature-prints
  (`VNGenerateImageFeaturePrintRequest` + `computeDistance`), seeded from the
  user's own albums — the **stray-finder**.
- The consumer iOS UI and the focus/blur presentation.
- Optional text→image search (a shipped Core ML model) — later.

### On-device reality (designed around, not against)
- Feature-prints give cheap near-duplicate / same-event grouping; **true
  full-library subject clustering is an ANN/k-means problem we own.** The
  stray-finder (distance-to-album-centroid) is the tractable, high-value first
  cut — no full-library clustering required.
- Feature-print vectors are **not stable across iOS versions** — cache the
  revision alongside the vector.
- Named-people grouping is **Apple-private** — if we want people albums, we
  rebuild from raw face detection.
- Foundation Models (on-device LLM) is available on recent hardware with a small
  context window, and is becoming a unified door to on-device third-party models
  too — worth designing toward for the paid "automatic" tier.

---

## Phases

- **Phase 0 — decided.** Standalone app; iOS-only; anonymous-local free tier;
  separate (mostly absent) backend; fork-and-invert the shell.
- **Phase 1 — the FREE tier → TestFlight.** Apple-seed galleries + manual
  curation + focus/blur, pure local. *This is `ios/` today.* Goal: a real build
  on a real phone, internal TestFlight (no Apple review needed) — where we learn
  the first-mile user behavior.
- **Phase 2 — the PAID upgrade: automatic image handling.** On-device clustering
  + the stray-finder, gated behind a managed subscription. The "it organizes
  itself" moment.
- **Phase 3 — App Store submission.** Privacy policy, screenshots, listing. See
  [`app-store.md`](app-store.md).
- **Phase 4 — post-launch.** Cross-device metadata sync (never photos), optional
  server escalation, search.

---

## Compliance notes (load-bearing for an AI photo app)

- **v0 collects nothing** → App Privacy questionnaire is "Data Not Collected,"
  the cleanest possible card.
- When any AI touches data (paid tier): Apple's guideline **5.1.2(i)** requires
  naming the exact provider and getting explicit opt-in — the top AI-app
  rejection vector. Bring-your-own keys must be Keychain-only and must not gate
  our own paywall.
- Account deletion (5.1.1(v)) applies **only if/when accounts are introduced** —
  not in v0.

---

## Build & ship

```bash
brew install xcodegen
cd ios && ./generate.sh && open Blur.xcodeproj
```

Then the runbook in [`app-store.md`](app-store.md): Apple App ID `ag.nuke.blur`,
a live privacy-policy URL, archive → TestFlight internal → App Store.
