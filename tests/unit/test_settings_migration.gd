extends TestCase
## Settings v2 -> v3: untouched old physics defaults are replaced, deliberate edits are kept.


func test_v2_untouched_defaults_are_dropped() -> void:
	var saved := {"bounce_soft": 8.0, "min_bounce_speed": 0.9, "surfaces": {}}
	for t in SettingsStore.V2_SURFACE.keys():
		(saved["surfaces"] as Dictionary)[Surface.name_of(int(t))] = (SettingsStore.V2_SURFACE[t] as Dictionary).duplicate()
	var out := SettingsStore.migrate_physics_v2(saved)
	assert_false(out.has("bounce_soft"), "old bounce default removed")
	assert_false(out.has("min_bounce_speed"), "old min bounce removed")
	assert_eq((out["surfaces"] as Dictionary).size(), 0, "old surface defaults removed")


func test_v2_custom_edits_are_kept() -> void:
	var saved := {"bounce_soft": 12.5, "surfaces": {"Rough": {"roll_decel": 3.0, "roll_drag": 0.6,
		"restitution": 0.18, "retention": 0.20, "caps_min": 0.80, "caps_max": 0.92}}}
	var out := SettingsStore.migrate_physics_v2(saved)
	assert_near(float(out["bounce_soft"]), 12.5, 1e-9, "custom bounce kept")
	assert_near(float((out["surfaces"] as Dictionary)["Rough"]["roll_decel"]), 3.0, 1e-9, "custom surface kept")


func test_clean_install_uses_v3_defaults() -> void:
	var cfg := PhysicsConfig.new()
	assert_near(cfg.bounce_soft, 16.0, 1e-9, "v3 bounce default")
	var empty := SettingsStore.migrate_physics_v2({})
	assert_eq(empty.size(), 0)
