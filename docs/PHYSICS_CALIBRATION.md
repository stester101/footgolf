# Physics and calibration

All values are **engineering defaults** (tunable in the developer panel), not locked rules,
except the stat conversions and the neutral-baseline definitions.

## Model (`scripts/physics/ball_sim.gd`)
- Fixed step `dt = 1/240 s`, independent of frame rate (`GameSession.advance` accumulates real time).
- **Air:** gravity 9.81 m/s² + quadratic drag `a = -k|v−w|(v−w)`, `k = 0.0011 1/m`, `w` = wind velocity.
  RK2 midpoint integration. Ground contact found by linear interpolation inside the step.
- **Bounce:** normal restitution `e/(1+|vn|/16)` per surface, tangential retention per surface. Short grass permits quick, diminishing hops; rough and sand absorb impacts. Below 0.65 m/s normal rebound speed the ball starts rolling.
- **Roll:** constrained to terrain; slope acceleration `5/7·g` along the surface; rolling resistance
  `a = roll_decel + roll_drag·v`; analytic stop inside a step; static friction holds the ball when
  slope acceleration ≤ `roll_decel`.
- Rough and sand catch a ball below 0.15 m/s instead of allowing a long hillside creep.
- **Rest:** speed < 0.02 m/s for 0.3 s. Hard timeout 60 s. Non-finite state → `ERROR`, ball restored.
- **Trees:** trunk cylinder (restitution 0.4) and canopy ellipsoid (damping 5/s) proxies.
- **Cup:** radius 0.054 m regulation (game default 12 in diameter); rolling capture ≤ 1.6 m/s x sqrt(R/0.054) (cap 3x),
  landing capture ≤ 7 m/s. See "Cup rim and flagstick" below.
- **Ball radius:** 0.02135 m physically. The *visual* sphere is enlarged with camera distance
  (visual-only, documented) so it remains visible on a phone.

## Cup rim and flagstick (owner-approved; all deterministic, no RNG; `tests/integration/test_cup_flag.gd`)
Neutral calibration is unaffected (the neutral reference plane has no cup). Defaults in `PhysicsConfig`:
`pin_radius` 0.0125 m, `pin_height` 2.0 m, `pin_soft_speed` 1.0 m/s, `pin_restitution` 0.35,
`pin_air_loss` 0.55, `pin_max_cup_radius` 0.45 m, `cup_rim_lip` 0.5, `cup_lip_max_factor` 2.0,
`cup_lip_deflect_deg` 35, `cup_lip_loss` 0.12. All are saved/loaded via `to_dict`/`apply_dict`.
- **Rolling rim:** the drop decision is made once per pass, when the ball first reaches the cup radius,
  from the lateral offset `b` of its line from the centre: drop if `v <= capture_eff * (1 - 0.5 (b/R)^2)`
  (dead centre = the old capture speed, a ball clipping the edge must be ~half as fast). Faster up to
  `2 x capture_eff`: lip-out, the path is bent toward the cup centre by `35 deg x b/R` and 12% of the speed is
  lost. Faster still: skips over unchanged. A ball that stops on the lip falls in.
- **Landing:** drops if inside the radius and `v <= 7 m/s * (1 - 0.5 (d/R)^2)` (d = landing distance from centre);
  otherwise it bounces as before.
- **Flagstick** (pole at the cup centre, active only when `cup_radius <= 0.45 m`, i.e. up to a ~3 ft cup; bigger cups
  ignore it): a ball slower than 1.0 m/s ignores the pole. Faster, a ball whose path comes within
  `pin_radius + ball_radius` reflects its horizontal normal velocity (restitution 0.35). Rolling: the drop test then
  uses the PRE-impact speed, so a strike up to the capture speed loses its pace and drops, a harder one bounces out.
  Airborne (below 2 m, once per flight): the velocity is also scaled by 0.55, so a ball hitting the pin on the way
  down usually falls in (landing capture applies afterwards).
- Collision log entries `pin`, `lip`, `skip`, `rim` (landing too fast to drop) are recorded in `BallSim.collisions`.
- Gimme (rest within gimme distance of the cup edge) stays in `ScoringService`. The hole-out drop animation is
  unchanged (no separate pin/rim bounce visual).

## Spin (owner-approved, docs/DECISIONS.md)
- Strike point s in [-1 backspin, +1 topspin], 0.05 steps, flight shots only.
- Magnus lift `a = -s · 0.0016 · |v_rel|² ` perpendicular to the flight path in the vertical plane.
- Landing grip: tangential retention `+= s · 0.26` on the first bounce, halving each bounce
  (may go slightly negative on greens: backspin draws back).
- The flight solver is keyed by spin, so neutral first-contact carry stays exact (tested at s = ±0.5, ±1).
- Observed (120 caps, flat): fairway rollout back 2.7 m / none 8.8 m / top 19.1 m; green back 0.5 m /
  none 4.3 m / top 10.2 m; apex back 27.1 m / none 25.8 m / top 24.8 m.

## Neutral baselines
- Caps supplies `caps × 0.9144 m`; Goals supplies `goals × 0.3048 m` independently of shot style.
- Flight calibrates that distance to **first ground contact** at the chosen angle on flat FAIRWAY,
  zero wind and no obstacles. Roll calibrates that distance to total ground travel on flat FAIRWAY.
- `ShotCalculator` solves launch speed with a log-space secant/bisection over **the same BallSim**
  (`measure_neutral_carry` / `measure_neutral_roll`), to relative tolerance 1e-5. Results cached by
  `PhysicsConfig.signature()`.

## Measured results (from `tests/integration/test_physics_calibration.gd`, local run, Godot 4.7-stable)
| Caps | Target m | Carry m | Error |
|---:|---:|---:|---:|
| 1 | 0.914 | 0.9144 | −0.0003% |
| 10 | 9.144 | 9.1441 | +0.0009% |
| 50 | 45.720 | 45.7200 | −0.0001% |
| 150 | 137.160 | 137.1591 | −0.0006% |
| 200 | 182.880 | 182.8783 | −0.0009% |
| 400 | 365.760 | 365.7569 | −0.0008% |

| Goals | Target m | Roll m | Error |
|---:|---:|---:|---:|
| 0 | 0 | 0 (no motion) | — |
| 1 | 0.3048 | 0.3048 | +0.0004% |
| 5 | 1.5240 | 1.5240 | 0.0000% |
| 30 | 9.1440 | 9.1440 | 0.0000% |
| 100 | 30.4800 | 30.4800 | −0.0001% |
| 200 | 60.9600 | 60.9598 | −0.0003% |

Tolerance required: Caps max(0.25 yd, 0.5%), Goals max(0.10 ft, 1%). The developer panel
"Calibration check" re-runs this table on device with the current settings.

## Non-neutral behaviour (observed in tests)
- 150 caps, 5 m/s wind: tail 141.0 m, calm 137.2 m, head 132.8 m; crosswind deflection 2.2 m.
- 30-goal roll: green 10.9 m, fairway 9.14 m, rough 3.6 m, bunker 1.4 m.
- 40 goals on a 3% slope: uphill 10.9 m, flat 12.2 m, downhill 13.9 m.
- 120-cap flight rollout after landing: fairway ~8.8 m, green ~4.3 m, rough ~1.7 m, bunker ~0.1 m.

## Surface defaults (`Surface.default_params`)
| Surface | roll_decel | roll_drag | restitution | retention | Caps lie factor |
|---|---:|---:|---:|---:|---|
| Tee / Fairway (reference) | 0.90 | 0.22 | 0.38 | 0.37 | 1.00 |
| Fringe | 0.80 | 0.18 | 0.35 | 0.36 | 0.97–1.00 |
| Green | 0.80 | 0.17 | 0.30 | 0.30 | 1.00 |
| Rough | 2.20 | 0.60 | 0.18 | 0.20 | 0.80–0.90 (10–20% shorter) |
| Bunker | 5.50 | 1.50 | 0.05 | 0.06 | 0.60–0.80 (20–40% shorter) |

Lie factors with a range use a per-shot seeded RNG (seed recorded in `ShotResult`, reused by Replay).
The player sees only the approximate range text, never a predicted landing point.

## Wind
Hole defaults: H1 1.5 m/s, H2 2.5 m/s, H3 3.0 m/s. Bearing = direction the wind blows **toward**
(0° = +Z). Developer panel can override speed/bearing or zero the wind.

## Cup capture (8 Nov 2026, owner: "battered balls must not drop")
Rolling and landing use the same physics: a ball drops only if it sinks k x ball radius before reaching the far rim (k = cup_sink_fraction = 1.5). Rolling: v_crit = chord / sqrt(2 k r / g) (about 1.3 m/s centre-line on a regulation cup, 3.7 m/s on the 1 ft default). Landing: sink = v_down * t + g t^2 / 2 with t = distance to the far rim / horizontal speed. The old flat 7 m/s landing capture is no longer used.
