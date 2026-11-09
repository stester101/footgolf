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
- **Cup:** a real pit (game default 6 ft across = 0.9144 m; 4.25-72 in allowed). No capture-speed rule: HOLED = the
  simulated ball comes to rest inside the pit. See "Cup pit and flagstick" below.
- **Ball radius:** 0.02135 m physically. The *visual* sphere is enlarged with camera distance
  (visual-only, documented) so it remains visible on a phone.

## Cup pit and flagstick (owner-approved 9 Nov 2026; deterministic, no RNG; `tests/integration/test_cup_flag.gd`)
Neutral calibration and `ShotCalculator` are unaffected (the neutral reference plane has no cup).
- **Geometry:** vertical cylinder of radius R = `cup_radius` under the green, flat floor `cup_depth()` =
  clamp(0.25 R, 0.10 m, 0.30 m) below the LOWEST rim point (so a big hole on a slope is a pit all round).
  Ball centre support vs distance d from the axis: d >= R turf (ground + r); R - r < d < R the rim edge circle
  (centre sqrt(r^2 - (R - d)^2) above the rim height, contact normal from edge point to centre, no rolling
  resistance on the bare edge); d <= R - r no support.
- **Leaving the ground:** a rolling ball follows the support only while it does not fall away faster than
  gravity can follow; otherwise it becomes airborne (`_lip_air`) and falls into the pit or carries over.
- **In the air:** sphere vs rim-edge circle, wall (centre confined to R - r while below the rim) and floor.
  Impacts: normal reversed with restitution (`cup_wall_restitution` 0.35 wall/edge, `cup_floor_restitution` 0.25
  floor), tangential reduced by Coulomb friction `cup_friction` 0.3. Gentle contact on a near-flat support rolls.
  Floor rolling: `cup_floor_roll_decel` 1.6 m/s^2 + `cup_floor_roll_drag` 0.6 v.
- **Sub-steps:** near the cup each fixed step is split so the ball travels <= r/4 per sub-step (max 32); away from
  the cup the step is unchanged.
- **Emergent outcomes (tests):** 0.9 m/s centre putt into a 1 ft cup drops and settles on the floor; 6 m/s across it
  meets the far rim/wall and stays out; 12 m/s skims over; a lip graze is pulled sideways; steep drops into a 6 ft
  hole stay in; 12 m/s flat just above the turf hits the far wall of a 6 ft hole and stays in, 25 m/s rising skims
  across; rolling balls 0.8-15 m/s into a 6 ft hole end HOLED.
- **Flagstick** (pole at the cup centre, active only when `cup_radius <= 0.45 m`): `pin_radius` 0.0125 m,
  `pin_height` 2 m; slower than `pin_soft_speed` 1.0 m/s it is ignored; faster, the horizontal normal velocity is
  reflected (restitution 0.35). In flight (once per flight) the velocity is also scaled by 0.55, except for a ball
  that just ran off the rim. The pit decides the rest (a moderate strike falls in, a hard head-on one bounces out).
- Old heuristic keys (`cup_capture_speed`, `cup_sink_fraction`, `cup_landing_capture_speed`, `cup_rim_lip`,
  `cup_lip_*`) are ignored by `apply_dict`, so older saved settings still load.
- Collision log entries `pin`, `rim` (edge impact), `cup_wall`, `cup_floor` are recorded in `BallSim.collisions`.
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

## Cup capture (8 Nov 2026; SUPERSEDED 9 Nov 2026 by the real pit above)
Rolling and landing use the same physics: a ball drops only if it sinks k x ball radius before reaching the far rim (k = cup_sink_fraction = 1.5). Rolling: v_crit = chord / sqrt(2 k r / g) (about 1.3 m/s centre-line on a regulation cup, 3.7 m/s on the 1 ft default). Landing: sink = v_down * t + g t^2 / 2 with t = distance to the far rim / horizontal speed. The old flat 7 m/s landing capture is no longer used.
