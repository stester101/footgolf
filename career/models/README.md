# Career data shapes (plain Dictionary / Array, JSON-safe)

All unapproved numbers live in `career/data/career_config.gd`. JSON turns ints into floats on load: always `int(x)` when reading.
Seasons/events are indices, not wall-clock dates. Ids are stable strings.

## golfer
```
{id, name, nationality, age:int, rating:float(40-100), consistency:float(0-1), form:float(-1..1, 0 at start),
 injured_until:int (event serial; 0 = fit), status:"active"|"injured"|"retired", initial_rank:int,
 kind:"sound_alike"|"generated", ...}
```
Source: `career/data/golfer_roster.json`; copied into the save (`golfers`) at career creation, then evolved by the simulation.

## event
```
{id:"s1_e07", serial:int (1-based order in the season), category:"regular"|"flagship"|"major"|"finale",
 name, course_id (data/courses.json id), rounds:int,
 cut:{type:"none"|"top_n"|"percent", after_round:int, n:int | percent:int}   # always "and ties"
 purse:int, field_size:int, points:{winner:int},   # season points for the winner; places via CareerConfig.POINTS_DECAY_PER_PLACE
 status:"upcoming"|"in_progress"|"complete"|"skipped", eligible:bool, requirement:String, result:{}}
```

## simulation call used by the tournament flow (live: career/systems/career_sim.gd `CareerSim` -> OpponentSimulation; tests may use `CareerSimStub`)
```
simulate_round(field: Array[golfer Dictionary], event: Dictionary, round_index: int (0-based),
               course: {holes:int, par:int, difficulty:float (0 = neutral)}, seed: int, adaptive: float = 0.0)
   -> {golfer_id: strokes:int}      # deterministic for identical arguments; no hidden state
```
Only OPPONENTS are in `field` (never the human). The caller stores the returned scores in the save
(`active_tournament.opponent_rounds[golfer_id] = [r1, r2, ...]`) so a restart never re-rolls.
Swap point: the static var `CareerManager.sim` (any object/class with `simulate_round`).

## tournament (`save.active_tournament`, {} when none)
```
{id, event (copy), snapshot:{course_id, name, holes:[{id, par, data:<hole json dict>}], hash},
 field:[opponent golfer ids], status:"setup"|"in_round"|"between_rounds"|"complete"|"missed_cut",
 round_index:int (0-based: round being played / next), human_rounds:[{strokes, par, holes}],
 opponent_rounds:{golfer_id:[strokes]}, cut:{applied:bool, line_total:int, survivors:[ids], human_made:bool},
 rules:{RoundConfig.to_dict()} (frozen when each round starts), mulligans:int,
 round_save:{RoundSave.capture() dict} (in-progress round; {} between rounds), sim_seed:int}
```

## save envelope (user://career/career.json)
`{schema_version, checksum (sha256 of the payload text), saved_at, payload:"<JSON text of the career data>"}`.
Career data top level: `schema_version, career_id, player{name,nationality}, options{footballer_once_per_season},
season{number,id,length}, calendar[event], active_tournament, world_rankings{player_rank}, season_standings{id|"player":points},
golfers[], rivalries[], sponsorships{}, economy{balance,currency,season_earnings,career_earnings}, cosmetics{}, achievements[],
career_history[], simulation_state{seed}, season_footballers{season_id:[footballer ids]}, save_metadata{}`.
Rivalries, sponsorships, cosmetics, achievements are reserved placeholders (later phases).


## Schema v2 additions (save `schema_version` 2; v1 saves migrate in `CareerMigration.v1_to_v2`, filling defaults)
- `golfers` also holds the human entity `{id:"player", is_human:true, initial_rank:180, tour_card:true, honours:[]}`; every golfer has `honours`.
- `world_rankings = {player_rank, world:{season_points:{"<season>":{id:pts}}, applied:{event_id:true}}}` (RankingManager).
- `season_standings = {season, points:{id:pts}, wins:{}, starts:{}, applied:{event_id:true}}` (v1 was a flat `{id:pts}`).
- `prev_standings_rank {id:rank}` (last season's top 60, for exemptions); `season_history [{season, standings_champion(_id), human_rank, human_points, tour_champion, earnings}]`.
- events carry `order` (monotonic counter, injuries are measured in it) and keep `points.winner` (season) / `world_points.winner`.
- event `result` (calendar, written once per event, played or skipped): `{winner_id, winner_name, winner_total, winner_to_par, human_played, human_place(_label),
  human_total, human_rel, human_missed_cut, human_won, human_earnings, human_points, human_world_points, field, rounds, world_rank_before/after,
  season_rank_before/after, playoff{needed,human_involved,holes}, cut, movers[], report[top rows + you + rivals], rivals[]}`.
- `ledger [{id:"prize:<event_id>", kind, label, amount, event_id, season, balance_after}]` (ids are stable: nothing pays twice; economy totals move only when an entry is new).
- `trophies [{id:"win:<event_id>"|"title:season_N", kind:event_win|flagship|major|tour_championship|season_title, name, season, event_id}]`, `records {wins, majors, starts, cuts_made, top10s, best_finish, best_world_rank, biggest_cheque, applied}`.
- `head_to_head {applied:{event_id:true}, records:{golfer_id:{w,l,t,close,last_event}}}`, `rivalries [{id,name,meetings,wins,losses,ties,close}]` (best first; a rival needs `RIVAL_MIN_CLOSE` close finishes within `RIVAL_CLOSE_STROKES`; the Hub features the first `RIVAL_MAX_FEATURED`).


## LBT / off-season / adaptive additions (no schema bump; defaults filled by `CareerMigration.ensure_defaults` on every load and at creation)
Other features add their own defaults in that function (one block each) instead of bumping `schema_version`.
- The tour is the **LBT** (Q-School dropped). The human golfer's `tour_card` flag is the card; `tour_status {wildcards_left, wildcards_used[event ids], history[{season,event_id?,text}]}`.
  Season end outside `TOUR_CARD_RETENTION_RANK` (Standings rank, 0 = no points) = card lost, `WILDCARDS_PER_SEASON` sponsor wildcards to REGULAR events next season (`eligibility().via == "wildcard"`, tournament event `wildcard:true`).
  Top `WILDCARD_CARD_PLACE` in a wildcard event, or a Standings rank inside the line, earns the card back (`result.card_message`).
- `off_season {active, season, step: review|sponsors|shop|news|start, review{}, card{status,standings_rank,line,wildcards_next}, news{aged,retired[],entrants[]}, evolved, archived, prev_rank{}}` (OffSeason). Hooks: `CareerManager.off_season_hook_sponsors()` / `off_season_hook_shop()` -> `{available, lines[]}`.
- `adaptive {mode: off|balanced|hard, offset, window[{event_id,score}], applied{event_id:true}}` (AdaptiveDifficulty). The offset is added to AI ratings only, frozen into `tournament.adaptive_offset` at entry.
