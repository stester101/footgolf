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

## simulation call used by the tournament flow (stub: career/systems/sim_stub.gd, class `CareerSimStub`)
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
