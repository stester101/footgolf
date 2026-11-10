# career/simulation — opponent world (pure logic)

Plain Dictionary/Array in and out; no nodes, no autoloads, no ball physics. All unapproved numbers live in
`career/data/career_config.gd` (PROPOSED DEFAULT - OWNER APPROVAL REQUIRED). Deterministic: every draw comes from
`SimRng.make(career_seed, event_id, round, golfer_id, salt)` (64-bit FNV-1a), so re-simulating never rerolls.

| File | Class | Purpose |
|---|---|---|
| sim_rng.gd | `SimRng` | derived seeded RNG |
| opponent_simulation.gd | `OpponentSimulation` | rounds, whole event, cut, positions, payouts, points, sudden death |
| ranking_manager.gd | `RankingManager` | World Ranking (2-season window, weights 1.0/0.5) and Season Standings |
| qualification_manager.gd | `QualificationManager` | eligibility + explanations, exemptions, field construction, finale top 30 |
| world_evolution.gd | `WorldEvolution` | form, injuries, honours, ageing, retirement, new entrants |

## Shapes (extra fields beyond the shared golfer/event shapes)
- golfer: `{id,name,nationality,age,rating,consistency,form,injured_until,status,initial_rank,kind}` plus optional
  `tour_card` (bool, default true), `honours` `[{season,category,event_id}]` (wins; category regular/flagship/major/finale),
  `status_history` `[{season,status}]`, `retired_season`, `entered_season`, `last_event_id` (idempotence marker).
  The human is an entity with `is_human = true` (needs id, name, initial_rank; no rating needed).
  `injured_until` = event `order` value (int, monotonically increasing event counter) before which the golfer is unavailable.
- event: `{id,category,name,course_id,rounds,cut:{type:none|top_n|percent,after_round,n|percent},purse,field_size,points}`
  plus optional `order` (int counter, default 0) and `adaptive_adjust` (strokes/hole hook, capped, default 0).
  `points` may be omitted (config), a number (winner world points), or `{world, season}`.
- course_info: `{par (per round), holes, difficulty (strokes/hole offset, optional)}`.
- world: `{season_points:{"<season>":{id:pts}}, applied:{event_id:true}}`; standings: `{season,points,wins,starts,applied}`.
  Applying an event twice is a no-op in both.
- ctx (qualification): from `QualificationManager.build_context(world, standings, golfers, season, prev_standings_rank)`.

## API
- `OpponentSimulation.simulate_round(golfer, course_info, event, round_index(0-based), career_seed, strength=-1) -> {strokes,to_par}`
- `simulate_event_field(field, event, course_info, career_seed, human_rounds=[], through_round=-1) -> result`
  result = `{event_id, category, rounds_played, complete, field_size, field_strength, cut:{...}|{}, winner_id,
  playoff:{needed,tied_ids,human_involved,resolved,...}, leaderboard:[{id,name,rounds,total,to_par,status(made_cut|cut|incomplete),
  position,tied,position_label,payout,world_points,season_points,is_human}]}`.
  AI-only ties for 1st are settled by `sudden_death`; if the human is in the tie `winner_id` is "" and the caller plays the
  playoff, then `apply_playoff_result(result, groups, event)` (groups = ids best to worst, ties as inner arrays).
  `through_round` hides future rounds (mid-event leaderboard); a human with fewer rounds than revealed is `incomplete`.
- `RankingManager`: `init_world`, `add_baseline`, `world_table`, `apply_event_to_world`, `prune_world`, `movement`,
  `new_standings`, `apply_event_to_standings`, `standings_table` (rows have `in_finale`, `tour_card_safe`), `new_season_standings`.
- `QualificationManager`: `check(golfer,event,ctx) -> {eligible,via,reason,requirement,exemptions,world_rank,standings_rank}`,
  `requirement_text(category)`, `build_field(event,golfers,ctx) -> {field,ids,player_in,invited,shortfall,player_check}`, `finale_qualifiers(rows)`.
  Majors/flagships top up with invited next-ranked AI when fewer than field_size qualify (`invited`); the human is only ever
  in a field when eligible.
- `WorldEvolution`: `update_after_event(golfers,result,event,seed,season)`, `record_honours`,
  `advance_season(golfers,new_season,seed,world={},target_active=-1) -> {retired,entrants,aged,active}`.
  Retired golfers stay in the array (status "retired") and in history; entrants have `kind="generated"`, ids `gx<season>_<n>`.

Open tuning: see `CareerConfig` sections "opponent world / simulation additions" (all invented).
