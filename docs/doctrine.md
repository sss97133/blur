# Blur — Operating Doctrine

*The fixed points. Everything else is implementation. When a decision is
unclear, it is resolved here, not re-litigated.*

---

## Stance

Blur is run as a CEO + full-stack lead would run it: **steady, not reactive.**
Direction is held, not re-opened every turn. The job is to keep the nuts and
bolts tight — technical and design — and to never sprint to implement in a
not-quite-right direction. Urgency is not a virtue; correctness is.

## The design position

**Design is transient. Bespoke design is a liability** — it ages, it demands
maintenance, it is a problem you must keep re-solving. So:

1. **We do not invent a skin, and we do not bake hard style rules.** We
   acknowledge that design *exists and matters* — and we solve it with
   **infrastructure**, not decoration.
2. **The platform is the design. SDK-maxxing.** Extract the maximum from
   Apple's frameworks and use them *as given*: native SwiftUI components, SF
   Symbols, system type and color, Dynamic Type, dark mode, accessibility,
   PhotoKit, Vision, Foundation Models. The SDK *is* the design language.
3. **The TextEdit principle.** TextEdit isn't "designed" — it is the system's
   default text surface, and that plainness is exactly why it can be stretched
   into an IDE. Blur is the system's default **photo-curation surface**: so
   native it feels *integral*, so unopinionated it can flex.
4. **Nuke DNA, stated correctly.** Adopt as closely as possible the thing you
   adhere to. Nuke mirrors its domain instead of inventing chrome; Blur mirrors
   the photo library through the platform's own surfaces. **Restraint is the
   absence of bespoke design**, not a prettier version of it.

The product's "design" is its **native correctness** plus its **utility.**
Nothing should feel like "an app." If it feels *designed*, we have added
liability and we cut it.

## Two surfaces, two rules

| Surface | Rule | Why |
|---|---|---|
| **Brand / go-to-market** (landing page, deck) | Crafted. Allowed to be beautiful. | It persuades humans to care. |
| **Product** (the app) | Native integral utility. No custom fonts, no bespoke palette, no invented chrome. | Zero design debt; feels like part of iOS. |

*(Apple's marketing pages are lush; its apps are HIG-native. Same split.)*

## What the doctrine buys us

- **Always current** — tracks iOS automatically, no restyling each release.
- **Accessible + localized for free** — Dynamic Type, VoiceOver, dark mode.
- **Zero design maintenance** — nothing bespoke to age.
- **Instantly familiar** — an integral utility, not a thing to learn.

## What it forbids

- A bespoke app skin. *(An earlier `docs/design/screens.html` mockup was exactly
  this — a custom-typed, custom-chromed concept. It is superseded by this
  doctrine and removed: it is the liability we are refusing.)*
- Frozen style rules. Design is transient; we bake the **principle** (platform
  adherence), never the pixels.

## The technical corollary (because design = infrastructure here)

"Get the design right" therefore means **get the engineering right**:

- Lean maximally on PhotoKit (native picker, smart albums, limited-library
  access, system thumbnails, native share sheet).
- Lean maximally on on-device intelligence (Vision feature-prints; Foundation
  Models where available) — SDK-maxxing the ML, not just the UI.
- Default SwiftUI containers; no hand-rolled components where a system one
  exists. Accessibility and dark mode are acceptance criteria, not polish.
- The one and only signature gesture is the blur/focus. Everything else is the
  platform.
