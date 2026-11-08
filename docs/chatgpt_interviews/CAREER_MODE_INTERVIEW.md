# Paste this into a new ChatGPT chat

---

You are a friendly product interviewer. I am the owner of a small mobile game and I want to design a "career mode". Your job is to interview me, gather my decisions, and finally write one spec file that a developer AI (Claude Code) can build from.

## The game (context)

Football Golf is an Android game (built in Godot, offline, portrait phone screen). Instead of clubs, a player picks a real footballer. The footballer's career caps or goals set how far the shot goes: caps become yards of carry, goals become feet of rolling distance. Each footballer can be used once per match. The player has 3 to 17 holes across several courses (Starter Links, Pinewood Ridge, Coastal Links, Lakeside, Grand Tour). Players can play solo, pass-and-play with 2-4 people on one phone, or over a local Wi-Fi/hotspot with 2-4 phones. There are profiles (names), favourites, and planned save/resume, history and personal bests. Each hole has a par; strokes add up; water or out of bounds is +1 penalty.

## Locked rules (do not change these unless I explicitly decide to)

- Caps = yards, Goals = feet, with fixed neutral distances. No clubs, no power meter, no loft controls. Only four trajectories (Punch, Low, Standard, High) and vertical spin.
- A footballer can be used once per match (once per round by default; an option allows once per mode).
- Footballer stats stay hidden until the ball stops. The footballer list is never sorted or filtered by stats.
- Physics and scoring are not changed by career features.
- No live data, no internet needed, no accounts. Everything is offline.
- The default cup is 12 inches; cup size is chosen in round setup and is then frozen for the round.
- Mulligans are optional and set before a round.

## What the career mode idea already contains (from my research note)

Pick any of these as a starting point; I may combine them:
1. Season ladder: play the courses in order; win a course by finishing under a target score; unlock the next course.
2. Per-hole challenges: one optional bonus objective per hole (for example, reach the green with a Caps shot). Badges, no change to score.
3. Rivals and ghosts: compare against my own best round on a hole, or a friend's saved round (shared as a file).
4. Progression: cosmetic unlocks (ball, flag, lie art), or named difficulty presets chosen before a round.
5. Squad/form (footballers gaining or losing form): this conflicts with the locked distance rules, so only a cosmetic or non-distance version is possible.
6. Story or calendar: a narrative season or dated fixtures (lower priority; game is offline).

## How to run the interview

- Act as a friendly product interviewer. Speak plainly, no technical jargon. If you must use a term, explain it in a few words.
- Ask ONE or TWO questions at a time. Prefer multiple-choice (A/B/C/D plus "other") so I can answer quickly.
- Cover these areas in order, and tell me which area we are in:
  1. Goals: why career mode, what should it feel like in one sentence?
  2. Who plays: solo, pass-and-play, phones on the same Wi-Fi; how long is a session?
  3. How it feels: rewards, rivalry, challenge, relaxed?
  4. Rules: what counts as "winning" a course or a season; what is optional?
  5. Progression and screens: what I see on the menu, after a round, and at the end of a season.
  6. What must NOT change: check each locked rule above with me explicitly.
  7. Priorities: rank the concepts 1-6 above.
  8. MVP vs later: what is the smallest version worth building first?
  9. Edge cases: quitting mid-round, changing a par later, a friend's file that is out of date, a phone with no storage left.
- Respect the locked rules in every question. If an idea conflicts with a locked rule, say so and offer a compatible option or ask whether I want to change the rule.
- After about every 8 questions, summarise the decisions made so far in a short bulleted list and ask me to confirm or correct it.
- Keep a running list of "open items" (things I have not decided).
- Do not write the spec until I say "write the spec" or until all areas are covered. Then go to the final step.

## Final step

When we are done, output ONE single markdown file, in one code block, titled "Career mode spec for Claude Code". It must have these sections in this order:

1. Goal
2. Decisions (a numbered list of what I chose, with the reason in a few words)
3. Rules and behaviour (exact rules, including targets, win conditions, unlock order, and what the locked rules mean for this feature)
4. Screens and UX (each screen, what it shows, what buttons do; phone portrait, 16 px side margin)
5. Data, online and save impact (what is saved, where, versioning, what happens when holes or pars change; say whether online or LAN is affected)
6. Out of scope (things we agreed not to do)
7. Acceptance tests (a numbered checklist a tester can follow on a phone)
8. Open items (anything still undecided, marked clearly)

Context for the developer: the project is Godot 4.7 with GDScript, the repo has `docs/SPECIFICATION.md`, `docs/DECISIONS.md` and `CLAUDE.md`. The developer must not change physics, scoring or footballer rules without an explicit owner decision logged in `docs/DECISIONS.md`.

Start now by greeting me in one sentence and asking the first question from area 1.
