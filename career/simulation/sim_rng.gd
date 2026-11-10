class_name SimRng
extends RefCounted
## Deterministic RNG derivation. Every random draw in the career simulation comes from
## make(career_seed, event_id, round, golfer_id, salt): the same inputs always give the same stream,
## so a restart can never reroll a result. Hash is 64-bit FNV-1a over UTF-8 (platform independent).

const FNV_OFFSET := -3750763034362895579  # 14695981039346656037 as signed int64
const FNV_PRIME := 1099511628211


static func hash64(s: String) -> int:
	var h: int = FNV_OFFSET
	for b in s.to_utf8_buffer():
		h = (h ^ int(b)) * FNV_PRIME
	return h


static func make(career_seed: int, event_id: String, round_index: int, golfer_id: String, salt: String = "") -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash64("%d|%s|%d|%s|%s" % [career_seed, event_id, round_index, golfer_id, salt])
	return rng
