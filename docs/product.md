# Blur — Product

*Product · Cost · Client, in full. The README is the front door; this is the
room behind it.*

---

## Product

**Blur is a private iPhone photo app that organizes itself.** It works as
smoothly as Apple Photos but with a real engine underneath: it finds the photos
you missed, groups your library passively so you never sort by hand, and lets
you flip to exactly the group you want to show while everything else stays
blurred. Free, anonymous, on-device — nothing leaves your phone.

- **One line:** *The private photo app that organizes itself — and shows people
  exactly what you mean.*
- **North star:** Apple Photos smoothness; better power under the hood.

### The three pillars
1. **Private by nature** — no account, no cloud, no upload; works in airplane mode.
2. **Quietly ordered** — it organizes itself and completes the albums you started.
3. **Shown with intention** — flip to the one that matters; the rest softens away.

### Scope — what it is NOT (v1)
No cloud backup, no social feed, no editor, no storage-cleaner gimmicks, no
Android, no account. Every exclusion is what keeps the core promise deliverable.

---

## Cost

### Cost to run
The free tier is **~$0 marginal cost** — all work happens on the device. No
servers, no storage, no per-user infrastructure. This is structurally cheaper
than every account-and-cloud competitor in the category.

### Cost to build
**Low and leveraged.** Blur reuses a proven, App-Store-runbooked iOS shell and
an existing image-intelligence engine; the free app is a re-skin of shipping
plumbing with the network removed. The one genuinely net-new build is the
on-device clustering layer that powers the paid tier.

### Cost to the user
- **Free** — the full on-device organizer, forever, no account.
- **~$20–30/yr** (managed tier) for fully automatic organization. This is the
  proven, sustainable price band for the category, and a deliberate undercut of
  the $5–8/**week** "cleaner" apps that currently extract the most revenue.

*(Raise & use-of-funds: the build is cheap; the spend is identity, brand, and
go-to-market. Figures set with the team.)*

---

## Client

**Beachhead (narrow on purpose):** iPhone users with **large, chaotic libraries**
who **regularly show their phone to others** and **refuse to sort by hand** —
enthusiasts, collectors, makers, parents.

- **The wedge behavior** is show-and-tell: the moment you hand someone your
  phone and need *the* photo. That's where "everything else, blurred" is felt.
- **Broad market:** privacy-conscious iPhone users — the trust layer, not the
  beachhead.
- **First community to seed:** Nuke's existing enthusiast network — a built-in
  audience that matches the profile exactly.

---

## Why now

- **Apple Photos hits real walls at scale** — smart albums choke past a few
  dozen, no "find the strays" flow, no safe-to-show mode. The default app
  creates the pain.
- **On-device AI just became viable** — Apple's Vision framework and (iOS 26)
  Foundation Models make private, server-free intelligence real for the first
  time. The privacy claim stands on shipping technology.
- **Privacy is a buying criterion now** — and the monetized incumbents are
  account/subscription/cloud-first. The private, on-device, passive lane is
  validated by small players and owned by no one at scale.

## The market

Consumer photo-cleaner/organizer is a large, iOS-concentrated category measured
in tens of millions of dollars per month, captured almost entirely on the App
Store. It's owned by **manual** apps with **predatory weekly pricing** and no
real privacy story. Blur doesn't need to beat Apple Photos at everything — it
beats it on the three things it does badly (stray-finding, scale, safe-to-show)
while matching its smoothness, and it occupies the privacy lane the
revenue leaders left open.

*(Market sizing figures are third-party estimates; verify against live sources
before quoting in a financing context.)*

---

## What investors usually ask

| Question | Answer |
|---|---|
| Won't Apple just do this? | Apple optimizes for everyone and won't ship *no-account* intelligence or fill the niche gaps; we move first and stay narrow. The privacy stance is structurally hard for the default app to copy. |
| What's the moat? | Early moat is execution, taste, trust, and a reusable studio shell that ships products fast — plus a community beachhead. Honest: it's speed and positioning, not patents. |
| Is the AI actually hard? | Duplicate/event grouping is cheap and reused. The **stray-finder** (complete an album you started) is the tractable, high-value first cut; full-library subject clustering is the deeper build. We lead with what we can ship well. |
| How do you monetize anonymously? | Free on-device; a managed subscription for automatic handling. Revenue comes from convenience, not from your data. |
| How does a no-account app grow? | The show-and-tell moment is inherently social; seed via community; ASO into an underserved category. |

---

## The studio

Blur is **product #1 from Nuke**. It is both the first proof that Nuke can take a
product from zero to the App Store — and the **template**: a reusable app shell,
image-intelligence engine, and launch runbook that the next products fork. The
operating discipline shows in the build: *measure, don't guess; ship small,
learn fast; private by architecture.*
