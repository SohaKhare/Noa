# Noa design direction

Items 0.17 (direction), 0.18 (design kit) and 0.19 (landing). Owner: Saish.

## References

- **[mio.xyz](https://www.mio.xyz/)** is the main reference for layout and UI elements:
  - a floating glass nav
  - a large two-line hero and numbered step cards with glass chips
  - an "@mention" use-case grid and a "flip the switch" comparison
  - an FAQ accordion and a big closing CTA

  Mio is also a close product analogue: an AI teammate that lives in chat, follows connect → @mention → approve, and keeps you in control.
- **Elf** (`~/code/dobby/web`, Saish's earlier site) is our own rebuild of Mio's design language. Noa reuses its patterns directly:
  - motion helpers (`Reveal`, `Parallax`, `SmoothScroll` with Lenis)
  - `GlassNav`, `SectionHeading`, `FAQ`
  - the scripted product-mock approach (`useLoop`)
  - noise overlay, glass utilities, type scale
- **Theme:** Elf's palette and photography as-is: warm off-white page, forest-green accent, pale sage pills, glass chips on nature photos, and the sky video in the hero. Elf's images and video are copied into `landing/public/`.

## Tokens (`packages/theme/theme.css`)

| Token | Value | Use |
| --- | --- | --- |
| `bg` | `#F1F1EE` | Page background |
| `surface` | `#FFFFFF` | Cards, windows |
| `ink` / `muted` / `line` | `#111111` / `#6B6B6B` / `#E2E2DC` | Text, secondary text, hairlines |
| `accent` (= `accent-fg`) | `#1E3A2F` | Forest green: primary buttons, active tabs, icons |
| `mist` | `#DDE8D8` | Sage pill and tinted bento cells |
| `deep` | `#16241E` | Code panels (agent pack files) |
| `signal` | `#D9734E` | Sparingly: "new", "just changed" |
| `radius-card` / `radius-chip` | 28px / 16px | Big cards / glass chips |

Type: Geist (sans) and Geist Mono (eyebrows, step numbers, source chips).
- Headlines are semibold with tight tracking (−0.03 to −0.045em).
- Utilities: `glass`, `glass-dark`, `liquid-glass`, `card-shadow`, `eyebrow`, `mist-wash`.

## Motion principles

- Every feature is shown as a **looping scripted scene** (`landing/src/lib/useLoop.ts`) that runs only while on screen and rests on its final frame under `prefers-reduced-motion`.
- Springs for things that move (cards flying to the board, popovers). Blur-in reveals for text and lists.
- Use one coral highlight per scene, to point at what just changed.
- Landing page order follows Elf:
  1. Hero (valley loop, `noa-valley.mp4`)
  2. Logo marquee
  3. Steps
  4. **Feature story** (`story/Story.tsx`): six sections scroll over one pinned valley. The camera pans and zooms through crops of `valley.jpg`. It does not swap to a different picture. Each section plays its scene:
     - **Chat to task** (`ChatToTask`): a Discord reply becomes a proposal, gets approved, and the card flies onto the Kanban.
     - **Staffing** (`DropIntoProject`): Riya is dragged from Project A to B, the confirm checklist ticks, and her `CLAUDE.md` types itself.
     - **KT** (`KTBrief`): the brief assembles and is delivered on WhatsApp.
     - **@noa** (`AskNoa`): a question is typed, then a cited answer appears.
     - **Decisions** (`DecisionsEdits`): "Decided today" fills, a deadline edit is made, and the lead approves it.
     - **Every role** (`RoleViews`): cycles the developer, designer, client servicing, ops and PM packs.
  5. Use cases
  6. Bento "Always current. Never in the way."
  7. FAQ
  8. Closing CTA
  9. Footer

## Components (design kit)

- **Landing:** `landing/src/components`, plus `scenes/` for the animated features.
- **App:** `web/src/components/ui.tsx` holds `Button`, `Card`, `Badge`, `Avatar`, `SourceChip`, `PageHeader` and `Eyebrow`; `AppShell` is the sidebar layout.
- Every item that came from a conversation shows a `SourceChip` (platform icon, place, time).

## Photos and scroll frames

Backdrops are the night photos on the CDN (`cdn.saish.xyz/noa/images/night.jpg` and `night-water.jpg`). Card crops are in `landing/src/lib/scenes.ts`.

**Shared style line:** night sky and night water, blue and cool, no text, no logos.

## AI-generated video (optional polish)

The hero is the night photo on the CDN. Do not add a second photo set.

**UI walkthrough videos (for the demo video, 4.7):** record the landing scenes and the `web/` pages directly, since they are already animated. Use AI video only for transitions and atmosphere, never to fake product UI.

Keep videos under 2 MB (webm plus an mp4 fallback), with a poster frame, muted, and paused off-screen.

## Mascot: Noa is a cat

Quiet, always listening (ears up), never in the way. All variants live in `Cat.tsx`, in both apps.

| Variant | Use |
| --- | --- |
| `CatMark` | Logo tile: cream face on forest green. Used for the favicon (`app/icon.svg`), nav, footer and app shell (`BrandMark`) |
| `CatFace` | Bare face. Noa's avatar in chat scenes (`NoaAvatar`) |
| `CatSit` | Full sitting cat with a curled tail. Used in the closing call to action |
| `CatPeek` | Head and paws over a card edge. Peeks over the hero's live feed |

Motion is small and foreground only: a blink every ~5 s, an ear twitch, a slow tail sway. All of it is off under reduced motion. Colours: forest `#1E3A2F`, cream `#F4F1E6`, coral `#D9734E` (inner ears, nose).
