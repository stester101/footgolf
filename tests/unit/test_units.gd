extends TestCase


func test_conversion_constants() -> void:
	assert_eq(Units.METRES_PER_YARD, 0.9144)
	assert_eq(Units.METRES_PER_FOOT, 0.3048)
	assert_eq(Units.FEET_PER_YARD, 3.0)
	assert_near(Units.yards_to_m(1.0), 0.9144, 1e-12)
	assert_near(Units.feet_to_m(1.0), 0.3048, 1e-12)
	assert_near(Units.yards_to_m(1.0), Units.feet_to_m(3.0), 1e-12, "1 yd = 3 ft")


func test_caps_200_is_182_88_m() -> void:
	assert_near(Units.caps_to_carry_m(200), 182.88, 1e-9)


func test_goals_30_is_9_144_m() -> void:
	assert_near(Units.goals_to_roll_m(30), 9.144, 1e-9)


func test_negative_stats_clamp_to_zero_distance() -> void:
	assert_eq(Units.caps_to_carry_m(-5), 0.0)
	assert_eq(Units.goals_to_roll_m(-5), 0.0)


func test_bearing_roundtrip() -> void:
	for b in [0.0, 45.0, 90.0, 180.0, 271.5, 359.0]:
		var d := Units.bearing_to_dir(b)
		assert_near(d.length(), 1.0, 1e-6)
		assert_near(Units.dir_to_bearing(d), b, 1e-3, "bearing %s" % b)
	assert_near(Units.bearing_to_dir(0).z, 1.0, 1e-6, "0 deg = +Z")
	assert_near(Units.bearing_to_dir(90).x, 1.0, 1e-6, "90 deg = +X")


func test_horizontal_distance_ignores_height() -> void:
	assert_near(Units.horizontal_distance(Vector3(0, 0, 0), Vector3(3, 100, 4)), 5.0, 1e-6)


func test_holeout_radius_conversion() -> void:
	assert_near(Units.feet_to_m(5.0), 1.524, 1e-9)
	assert_near(Units.feet_to_m(10.0), 3.048, 1e-9)


func test_shot_unit_default_follows_lie() -> void:
	assert_eq(Units.default_feet_for_lie(Surface.Type.GREEN), true)
	for lie in [Surface.Type.TEE, Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.FRINGE, Surface.Type.BUNKER]:
		assert_eq(Units.default_feet_for_lie(lie), false)
