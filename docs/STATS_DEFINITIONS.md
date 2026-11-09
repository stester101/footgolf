# Statistics definitions (non-Career play)

Implemented in `scripts/stats/stats_engine.gd`; input is the versioned telemetry shot record
(`TelemetryLog.FORMAT_VERSION = 2`). `N/A` = not reliably computable (never shown as 0).

## Shot record (telemetry `shot`, v2)
`seq` (per round, firing order, never reused), `player_idx`, `player_id` (profile id, "" = guest), `player_name`, `hole_id`,
`hole_index`, `par`, `shot_no` (per player per hole), `tee_shot`, `shot_type` (`Approach` = flight, `Putt` = roll),
`mode` (CAPS/GOALS), `footballer_id`, `trajectory`, `spin`, `start_lie`, `final_lie`, `on_green_end`, `carry_m`, `roll_m`,
`total_m`, `pin_before_m`, `pin_after_m` (0 when holed), `penalty`, `stroke_delta`, `holed`, `replacement`.
Measured distances are `null` when not measured: `carry_m` needs a flight shot with a first ground contact; `roll_m` needs a
first contact (flight) or is the full travel (roll); a simulation error measures nothing.
Mulligan / Developer Undo append a `mulligan` / `undo` record with `replaces_seq`; the replaced shot stays in the log (audit)
but is excluded by `TelemetryLog.played_shots`. History is built from the session's HoleState shots (already net of
mulligan/undo), so a replaced shot never counts. Version-1 files load unchanged (matched by shot_id) and give `limited` stats.

## Round metrics (per player)
- **Strokes** = sum of hole strokes (shots). **Penalties** = sum of penalty strokes. **Score** = recorded hole scores
  (strokes + penalties, capped by a max score if set). **To par** = score - par of completed holes.
- **Birdies or better** = holes with to par <= -1; **Pars** = to par 0; **Bogeys or worse** = to par >= +1. **Holes-in-one** = score 1.
- **Fairways hit** = tee shots (first counted shot) on par 4/5 holes that end with final lie Fairway and no penalty; denominator =
  par 4/5 holes. Par 3 excluded. Tee shots ending on the green are not fairway hits.
- **GIR** = the first non-penalty shot that ends on the green (or holes out), counting strokes + penalties through that shot, is
  <= par - 2. Denominator = completed holes.
- **Putts** = shots whose start lie is Green (Caps or Goals).
- **Distances**: Approach carry = `carry_m` of Approach shots with a measured carry (yd); Approach total = `total_m` (yd);
  Putt travel = `total_m` of Putt shots (ft). Average and longest over measured values only. Caps total (yd) / Goals total (ft).
- **Caps vs Goals**: shot counts and share; average yards gained on the pin (`pin_before - pin_after`) and average yards left to
  the pin, per mode; holes finished with each mode.
- **Footballers used** = distinct footballer ids; most used = top 3 by shot count.
- **Per-hole breakdown**: par, strokes, penalties, score, to par, putts, fairway, GIR (stored in `stats.hole_rows`).

## Reliability
A round is `full` only if every shot is a v2 record, every completed hole has shots, and counted shots equal the scorecard
(strokes and penalties). Otherwise it is `limited`: scorecard metrics and Caps/Goals/footballer usage are exact, everything
shot-level (fairways, GIR, putts, distances, performance) is N/A. Lifetime figures aggregate only `full` rounds for shot-level
metrics (the page says how many rounds were used) and all rounds for scorecard metrics; they always reconcile with the scorecards.

## Lifetime, records, trends
Per local profile: rounds, holes, shots, all of the above summed (ratios from summed numerators/denominators, not averages of
ratios). Personal bests: best round, most birdies in a round, fewest putts (full rounds), longest approach carry and putt travel.
Course records: best score per course and rule set (cup, hole-out, mulligans, tees, wind, max score, pins). Trend: mean to-par of
the newest 3 rounds minus the previous 3 (N/A below 6 rounds).

## Storage
`user://history.json` (`history_version` 2): one record per round, one entry per player with `profile_id` and `stats`; pages show
only the selected profile's entries (guests are their own scope). Telemetry-only rounds from earlier versions are imported once
(`HistoryMigration`) as the first profile's single-player rounds; unfinished, developer and multi-player-unseparable rounds are skipped.
Unfinished rounds: `user://saves/round_<id>.json` (`save_version` 2, full frozen RoundConfig). Online rounds are never saved.
