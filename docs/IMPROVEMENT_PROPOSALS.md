# Improvement proposals (need owner approval or device testing)

Ranked, concise. Implemented polish items are in the git log ("Polish: ..."); these are the rest.

1. Auto-pause when the app is backgrounded mid-round (Android `NOTIFICATION_APPLICATION_PAUSED`): open the Pause menu so a returning player never resumes mid-flight. Needs a decision on in-flight shots and online rounds.
2. Touch targets: several controls are under 48 dp at the 720 px design width (`game_ui.gd` change-footballer chip 220x40, flag chips, picker flag/dot 34-36 px, wind indicator 44). Raising them changes approved layouts; wants a screenshot review.
3. Audio: a volume setting is not possible until sound exists. Minimum set: shot hit, hole-out, water splash, UI tap. Needs asset choice and licensing.
4. Left-handed / control-scheme options (the Settings > Controls page is a placeholder).
5. Haptic consistency: only shots and hole-outs vibrate. Candidates: penalty (water/OOB), eagle or better, UI confirm. Needs an owner taste call.
6. Remember last tee colour / hole selection per course in Round Setup (today: course, players and mulligans are remembered).
7. Share sheet for the diagnostic log (needs an Android plugin; today the file is saved to Documents/FootballGolf and a short tail is copied to the clipboard).
8. Reduced-motion option (skip camera easing, spark bursts, cup pulse) for accessibility and low-end devices.
9. Text-size / high-contrast setting; fonts are fixed at 19-30 px on the settings pages.
10. Richer empty states on Statistics (a "play your first round" shortcut button).


## Round 2 status
Done (see git log "Polish round 2"):
- 1 Auto-pause on backgrounding: offline rounds waiting to aim open the Pause menu (setting "Pause the round when the app goes to the background", default on). Online and in-flight shots are left alone.
- 2 (partial) Change-footballer chip raised to 48 px high. Other chips/flags/dots still need a screenshot review.
- 3 (partial) Sound hooks are stubbed in `Feedback.sfx` behind a muted-by-default setting; no audio assets yet.
- 5 Haptic consistency: penalty and eagle-or-better now have their own cues (`Feedback`), all behind the Vibration toggle.
- 8 Reduced motion: no camera sweep, cup celebration or result reveal animation.
- 9 (partial) "Larger text" scales the Settings pages (x1.25); in-round HUD sizes are unchanged.
- 10 Statistics empty state has a "Play your first round" button.
- Extras: "Copy round summary" on the round-complete screen (`RoundText`), tutorial copy refreshed (no "three holes", new trajectory/spin page), online reconnect countdown and clearer disconnect/timeout messages, settings load tolerates wrong-typed values and `save()` reports failure, HUD distance/wind labels no longer rebuilt every frame.
Still open: 4, 6, 7, audio assets, remaining touch targets.
