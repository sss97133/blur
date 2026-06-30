# Blur — App Store Listing Copy

*Ready-to-paste metadata for App Store Connect. Character limits noted; Apple
counts characters, not bytes. Lead with the privacy + passive-organization
story everywhere — it's the differentiator and the honesty is the marketing.*

---

## App name (30 chars max) — pick one

"Blur" is almost certainly taken as a standalone App Store name. The **bundle
id `ag.nuke.blur` is independent** and stays regardless. Candidates (all ≤30):

| Name | Chars | Note |
|---|---|---|
| **Blur — Private Photos** | 21 | clearest; leads with privacy |
| **Blur: Photo Organizer** | 21 | leads with the category for ASO |
| **Blur — Quiet Photos** | 19 | on-brand, calm |
| **Blur Gallery** | 12 | short, if available |

*Recommendation:* try **Blur — Private Photos**; fall back to **Blur: Photo
Organizer** for keyword weight. Confirm availability in App Store Connect before
committing (names are globally unique).

## Subtitle (30 chars max)
- **It organizes itself.** *(20 — recommended; pairs with the name)*
- Private photos, sorted. *(22)*
- Find &amp; show, fast. *(17)*

## Promotional text (170 chars max — editable anytime without a new build)
> Your photo library, organized for you — privately, on your phone. Find any
> photo in a tap, and show people exactly what you mean. Nothing ever leaves
> your device.

*(157 chars)*

## Keywords (100 chars max, comma-separated, no spaces after commas)
```
photo,organizer,private,gallery,albums,sort,cleaner,hide,photos,vault,camera roll,offline,smart
```
*(99 chars. Don't repeat words from the app name/subtitle — Apple already indexes
those. Revisit after launch using App Store search-term data.)*

## Description (4000 chars max)

> **Blur is the private photo app that organizes itself.**
>
> It works as smoothly as the photos app you already know — but underneath, it
> does the work you never want to do. Blur sorts your library into galleries,
> finds the photos you missed, and lets you flip straight to the one you mean to
> show while everything else stays softly blurred. No more frantic scrolling.
> No more handing someone your phone and hoping.
>
> And it's private by design: everything happens on your device. No account. No
> cloud. No upload. Blur works in airplane mode, because your photos never leave
> your phone.
>
> **ORGANIZES ITSELF**
> Blur reads the albums already on your phone and arranges them into clean
> galleries — no tagging, no swiping, no rabbit hole.
>
> **FINDS WHAT YOU MISSED**
> Started an album but missed a few shots out of thousands? Blur finds the
> strays that belong and completes the group for you.
>
> **SHOW WITH CONFIDENCE**
> Turn on Show mode and present a gallery safely — flip to exactly what you want
> while the rest stays blurred. Hand someone your phone without a second thought.
>
> **PRIVATE BY ARCHITECTURE**
> No sign-up. No data collection. No servers. Everything stays on your device.
> The privacy isn't a setting — it's how Blur is built.
>
> Free to download and use. A Nuke product.

*(Trim/expand to taste; keep the ALL-CAPS feature headers — they scan well on
the store. Do not promise features not in the shipped build.)*

## What's New (version notes, 4000 chars)
> First release. Blur organizes the photos already on your phone into galleries,
> finds the ones you missed, and lets you show people exactly what you mean —
> all privately, on your device.

## Categories
- **Primary:** Photo &amp; Video
- **Secondary:** Productivity *(or Utilities)*

## Age rating
4+ (no objectionable content; the user's own library).

## App Privacy — nutrition label
**Data Not Collected.** No data types collected; no tracking. (Matches
`ios/PrivacyInfo.xcprivacy`.) This near-empty privacy card is a selling point —
screenshot it.

## Support & marketing URLs
- **Support URL:** a contact page (required). e.g. a `nuke` contact route.
- **Marketing URL:** the Vercel landing page (`web/`).
- **Privacy Policy URL:** required and **must be live** before review — must
  state on-device processing / no data collected. (A 404 here is a launch
  blocker.)

## Screenshots (App Store, required — 6.7" + 6.1" sets)
In order, the money shots:
1. The galleries grid — a chaotic library made calm.
2. A gallery in Show mode — a few frames softly blurred (the name, shown).
3. The stray-finder moment — "more photos belong here."
4. The privacy line / Settings — "Data Not Collected."

*No device frames or marketing text needed; clean UI screenshots read as
confident. Match the landing page's calm, editorial tone.*

## Review notes (paste into App Review Information)
> Blur organizes the photos already on the device into galleries and lets the
> user hide photos (blur) and present a gallery safely via Show mode. It is
> fully native (PhotoKit, on-device state) and makes no network calls — no
> account, no server, no data leaves the device. Grant Photos access on first
> launch to see your albums as galleries. (Guideline 4.2: genuinely native
> on-device functionality, not a web wrapper.)
