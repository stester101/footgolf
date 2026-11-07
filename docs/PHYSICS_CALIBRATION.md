# Physics and calibration

All values are **engineering defaults** (tunable in the developer panel), not locked rules,
except the stat conversions and the neutral-baseline definitions.

## Model (`scripts/physics/ball_sim.gd`)
- Fixed step `dt = 1/240 s`, independent of frame rate (`GameSession.advance` accumulates real time).
- **Air:** gravity 9.81 m/s² + quadratic drag `a = -k|v−w|(v−w)`, `k = 0.0011 1/m`, `w` = wind velocity.
  RK2 midpoint integration. Ground contact found by linear interpolation inside the step.
- **Bounce:** normal restitution `e/(1+|vn|/8)` per surface, tangential retention per surface
  (crudely represents spin/turf). Below 0.9 m/s normal speed the ball starts rolling.
- **Roll:** constrained to terrain; slope acceleration `5/7·g` along the surface; rolling resistance
  `a = roll_decel + roll_drag·v`; analytic stop inside a step; static friction holds the ball when
  slope acceleration ≤ `roll_decel`.
- **Rest:** speed < 0.02 m/s for 0.3 s. Hard timeout 60 s. Non-finite state → `ERROR`, ball restored.
- **Trees:** trunk cylinder (restitution 0.4) and canopy ellipsoid (damping 5/s) proxies.
- **Cup:** radius 0.054 m; rolling capture ≤ 1.6 m/s, landing capture ≤ 7 m/s.
- **Ball radius:** 0.02135 m physically. The *visual* sphere is enlarged with camera distance
  (visual-only, documented) so it remains visible on a phone.

## Spin (owner-approved, docs/DECISIONS.md)
- Strike point s in [-1 backspin, +1 topspin], 0.05 steps, Caps only.
- Magnus lift `a = -s · 0.0016 · |v_rel|² ` perpendicular to the flight path in the vertical plane.
- Landing grip: tangential retention `+= s · 0.26` on the first bounce, halving each bounce
  (may go slightly negative on greens: backspin draws back).
- The solver is keyed by spin, so neutral first-contact carry stays exact (tested at s = ±0.5, ±1).
- Observed (120 caps, flat): fairway rollout back 0.5 m / none 4.9 m / top 15.3 m; green back −0.3 m.

## Neutral baselines
- Caps: `carry_m = caps × 0.9144`, measured as horizontal distance to **first ground contact**,
  launch angle 42° (engineering default), flat FAIRWAY plane, zero wind, no obstacles.
- Goals: `roll_m = goals × 0.3048`, initial rolling speed on the flat FAIRWAY plane until rest.
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
- 120-cap rollout after landing: fairway ~4.9 m, green ~2.3 m, rough ~1.1 m, bunker ~0.1 m.

## Surface defaults (`Surface.default_params`)
| Surface | roll_decel | roll_drag | restitution | retention | Caps lie factor |
|---|---:|---:|---:|---:|---|
| Tee / Fairway (reference) | 0.90 | 0.22 | 0.32 | 0.32 | 1.00 |
| Fringe | 0.80 | 0.18 | 0.30 | 0.28 | 0.97–1.00 |
| Green | 0.80 | 0.17 | 0.26 | 0.22 | 1.00 |
| Rough | 2.20 | 0.60 | 0.18 | 0.20 | 0.80–0.92 |
| Bunker | 5.50 | 1.50 | 0.05 | 0.06 | 0.60–0.80 |

Lie factors with a range use a per-shot seeded RNG (seed recorded in `ShotResult`, reused by Replay).
The player sees only the approximate range text, never a predicted landing point.

## Wind
Hole defaults: H1 1.5 m/s, H2 2.5 m/s, H3 3.0 m/s. Bearing = direction the wind blows **toward**
(0° = +Z). Developer panel can override speed/bearing or zero the wind.
