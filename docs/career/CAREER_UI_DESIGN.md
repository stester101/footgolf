# Career UI design (LBT career)

Portrait first (720x1280 canvas, tested at 450x800). Presentation only: every number comes from
`CareerManager` and its systems; the UI never decides results, money or eligibility.

## What the reference games do well (brief research, Nov 2026)
- **EA Sports PGA Tour / PGA 2K MyCAREER**: the career is a season calendar plus a points race (FedExCup-style)
  with a clear "next event" focus. Reviews praise clean presentation but criticise menus that hide key actions
  (upgrades only reachable outside career, wrong menus opening, sluggish menus). Lesson: the next action is always
  one tap from the hub, and nothing important is buried.
- **Football Manager (FM26 "Portal")**: Sports Interactive found players lived in the Inbox, not the Home screen,
  and rebuilt the hub as tiles that summarise and open into detail cards, with larger text and better contrast.
  Critics found extra clicks between inbox items and screens frustrating. Lesson: summary tiles that open into
  detail, a news feed that is glanceable, no dead-end confirmation screens.
- **EA FC career**: hero header with club/rank, a central "Continue" CTA, calendar strip of upcoming fixtures,
  and a news ticker. Lesson: one bold CTA, a horizontal "what's coming" strip, and identity (name, nation, rank)
  always on screen.

Sources: EA PGA Tour reviews (GameSpot, Push Square, COGconnected), PGA TOUR 2K25 MyCAREER page,
footballmanager.com "FM26's reimagined user interface", Galaxus FM26 critique.

## Layout
- **Career shell** (one page): hero header, scrolling content, bottom tab bar.
  - Tabs: **Hub** (next event CTA, calendar strip, news/inbox, quick tiles), **Schedule** (season calendar as
    tier-coloured event cards), **Rankings** (World Ranking / Season Standings segmented, movement arrows),
    **Me** (records, trophy shelf, rivals, sponsor, shop, money, settings).
  - Back: from Schedule/Rankings/Me goes to Hub; from Hub leaves Career. Implemented by stacking non-Hub tabs on
    top of the Hub page in the existing MainMenu page stack (no MainMenu changes).
- **Detail pages** (event, tournament, round setup, report, sponsors, shop, off-season, settings, full ranking
  lists): compact career header (back chevron 96 px, title, optional subtitle chip), scroll body, fixed footer
  for the primary action.

## Hierarchy
1. Identity + status (hero): name, nation chip, **world rank** (biggest number), season standing, season
   progress bar (events done / total), earnings.
2. **Primary CTA**: "Play next event" / "Continue tournament" / "Begin off-season" — full width, 120 px, lime.
3. Context: next event card (tier stripe, course, rounds, purse, eligibility), calendar strip, news.
4. Everything else is a tile or row that opens a detail page.

## Colours (on the existing navy glass theme)
| Token | Colour | Use |
|---|---|---|
| Regular | `#4FA3FF` | regular LBT event |
| Flagship | `#B98CFF` | flagship |
| Major | `#FFC845` | majors (gold) |
| Finale | `#FF7A59` | LBT Championship |
| Up | `#7CF27C` | ranking up / money in |
| Down | `#FF6B6B` | ranking down / money out |
| CTA | lime `#C6FF70`→`#8DDB2A`, dark text | the one primary action per screen |
| Me highlight | turf `#A0F344` at 18% | the player's own row |

Surfaces: hero uses a deep blue gradient with a tier-coloured glow; cards use the shared `UiSkin` glass/recess
materials. White primary text, `#B8C8DA` secondary, cyan caps captions.

## Typography
Bundled sans with `UiKit` variations: display (bold italic) for big numbers and headlines, caps for captions,
tabular figures for tables. All sizes pass through `CareerKit.fs()`, which applies Settings > Larger text (x1.25).

## Motion
- Count-up on hero numbers (rank, points, money) 0.6 s ease-out; fade/slide-in of cards (60 ms stagger).
- Progress bars fill from 0.
- Settings > Reduced motion: every tween is skipped and final values are shown immediately.

## Components (`scripts/ui/career_kit.gd`)
`hero`, `tab_bar`, `cta`, `card`, `stat_tile`, `progress_bar`, `tier_chip`, `nation_chip`, `event_card`,
`calendar_strip`, `move_arrow` (drawn triangle, no glyph dependency), `rank_row`, `news_item`, `trophy_shelf`,
`segmented`, `count_up`, `page` (detail page shell). Minimum touch target 96 canvas px (48 dp).

## Rules kept
- Fail-closed save: the Save Error overlay (Retry Save only, Back blocked) is unchanged in behaviour.
- No balance or rule changes; all numbers remain PROVISIONAL in `CareerConfig`.
- Rank movement for other golfers comes from a UI-only cache (`user://career_ui_ranks.json`) that remembers the
  previous table; it is presentation data and never feeds the career save.
