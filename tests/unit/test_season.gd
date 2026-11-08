extends TestCase
## Mini season points/standings, custom course combinations, picker-sort opt-in and the frozen online setup.


func test_points_table_scaled_by_holes() -> void:
	# four players, distinct scores, 3-hole course: 2x3=6, 1.2x3=3.6->4, 0.7x3=2.1->2, 0.4x3=1.2->1
	var pts := Season.points_for([1, -2, 0, 3], 3)
	assert_eq(pts[1], 6, "1st")
	assert_eq(pts[2], 4, "2nd")
	assert_eq(pts[0], 2, "3rd")
	assert_eq(pts[3], 1, "4th, min 1")
	# 9-hole course: 18 / 11 / 6 / 4
	var p9 := Season.points_for([0, 1, 2, 3], 9)
	assert_eq(p9, [18, 11, 6, 4], "9 holes")
	# 1-hole course: last place never below 1
	assert_eq(Season.points_for([0, 1, 2, 3], 1), [2, 1, 1, 1], "min 1")
	assert_eq(Season.points_for([0, 1], 4), [8, 5], "two players")


func test_ties_share_the_average_of_covered_places() -> void:
	# two tied for 1st on 3 holes: avg(6, 3.6)=4.8 -> 5 each; 3rd 2.1 -> 2
	assert_eq(Season.points_for([0, 0, 5], 3), [5, 5, 2], "tie for first")
	# tie for 2nd/3rd: avg(1.2, 0.7)=0.95 x 3 = 2.85 -> 3
	assert_eq(Season.points_for([-1, 4, 4], 3), [6, 3, 3], "tie for second")
	# all four tied, 10 holes: avg(2, 1.2, .7, .4)=1.075 -> 10.75 -> 11
	assert_eq(Season.points_for([2, 2, 2, 2], 10), [11, 11, 11, 11], "all tied")
	assert_eq(Season.places_for([0, 0, 5]), [1, 1, 3], "shared place")


func _two_course_season() -> Season:
	var s := Season.create(["starter", "lakeside"])
	s.record_course(0, "starter", "Starter Links", 3, 10, ["Ann", "Bob"], [10, 12], [0, 2])
	s.record_course(1, "lakeside", "Lakeside", 4, 14, ["Ann", "Bob"], [16, 13], [2, -1])
	return s


func test_standings_and_winner() -> void:
	var s := _two_course_season()
	# course 1: Ann 6, Bob 4 ; course 2 (4 holes): Bob 8, Ann 5 (1.2x4=4.8) -> Ann 11, Bob 12
	assert_eq(s.results[0].points, [6, 4])
	assert_eq(s.results[1].points, [5, 8])
	var rows := s.standings()
	assert_eq(rows[0].name, "Bob")
	assert_eq(rows[0].points, 12)
	assert_eq(rows[1].points, 11)
	assert_eq(s.winners(), ["Bob"])
	assert_true(s.is_finished())
	s.advance()
	assert_false(s.has_next())


func test_season_tied_on_points_breaks_by_score_then_shares_place() -> void:
	var s := Season.create(["a"])
	s.record_course(0, "a", "A", 3, 10, ["X", "Y"], [10, 10], [0, 0])
	var rows := s.standings()
	assert_eq(rows[0].place, 1)
	assert_eq(rows[1].place, 1)
	assert_eq(s.winners().size(), 2, "tie at the top has two winners")


func test_single_player_season_sums_scores() -> void:
	var s := Season.create(["a", "b"])
	s.record_course(0, "a", "A", 3, 10, ["Solo"], [11], [1])
	s.record_course(1, "b", "B", 4, 14, ["Solo"], [13], [-1])
	var rows := s.standings()
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].strokes, 24)
	assert_eq(rows[0].rel, 0)
	assert_eq(rows[0].points, 0, "no points for one player")


func test_progress_and_record_is_idempotent() -> void:
	var s := Season.create(["a", "b", "c"])
	assert_eq(s.current_course(), "a")
	s.record_course(0, "a", "A", 3, 10, ["P", "Q"], [10, 11], [0, 1])
	s.record_course(0, "a", "A", 3, 10, ["P", "Q"], [10, 11], [0, 1])
	assert_eq(s.results.size(), 1, "re-recording the same course replaces it")
	s.advance()
	s.advance()
	s.advance()
	assert_eq(s.current_course(), "c", "stops on the last course")
	assert_false(s.is_finished())


func test_season_dict_roundtrip_through_json() -> void:
	var s := _two_course_season()
	s.index = 1
	var back := Season.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(JSON.stringify(back.to_dict()), JSON.stringify(s.to_dict()))
	assert_eq(back.standings()[0].points, 12)
	var bad := Season.from_dict({"courses": ["a", 5, ""], "results": [{"names": 3}]})
	assert_eq(bad.courses, ["a"], "junk course ids dropped")
	assert_eq(bad.results.size(), 0, "malformed results dropped")


func test_combo_course_concatenates_holes_in_order() -> void:
	var courses := [
		{"id": "a", "name": "Alpha", "holes": ["h1", "h2"]},
		{"id": "b", "name": "Beta", "holes": ["h3", "h2"]},
	]
	var id := CourseCombo.make_id(["b", "a"])
	assert_true(CourseCombo.is_combo(id))
	assert_eq(CourseCombo.parse(id), ["b", "a"])
	var info := CourseCombo.info(id, courses)
	assert_eq(info.holes, ["h3", "h2", "h1"], "order kept, repeated hole id skipped")
	assert_eq(CourseCombo.info("combo:nope", courses), {})
	assert_false(CourseCombo.is_combo("starter"))


func test_combo_resolves_through_app_to_real_holes() -> void:
	var id := CourseCombo.make_id(["starter", "lakeside"])
	var defs := App.load_holes(id)
	assert_eq(defs.size(), 3 + 4, "starter 3 holes + lakeside 4 holes")
	assert_eq(App.course_par(id), App.course_par("starter") + App.course_par("lakeside"))


func test_picker_sort_option_defaults_off_and_roundtrips() -> void:
	var rc := RoundConfig.new()
	assert_false(rc.order_by_stats, "off by default")
	assert_eq(rc.season_courses, [])
	rc.order_by_stats = true
	rc.season_courses = ["starter", "ridge"]
	var back := RoundConfig.from_dict(JSON.parse_string(JSON.stringify(rc.to_dict())))
	assert_true(back.order_by_stats)
	assert_eq(back.season_courses, ["starter", "ridge"])
	assert_true(rc.duplicate_config().order_by_stats)
	var st := SettingsStore.new()
	st.save_path = "user://test_season_settings_%d.json" % randi()
	rc.write_defaults(st)
	var st2 := SettingsStore.new()
	st2.save_path = st.save_path
	st2.load_settings()
	var defaults := RoundConfig.from_settings(st2)
	assert_true(defaults.order_by_stats, "Settings default stored")
	assert_eq(defaults.season_courses, [], "a season is never a saved default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(st.save_path))


func test_online_setup_carries_sort_option_and_season_to_every_phone() -> void:
	var rc := RoundConfig.new()
	rc.order_by_stats = true
	rc.show_stats = false
	rc.season_courses = ["starter", "coastal", "starter"]
	var setup: Dictionary = JSON.parse_string(JSON.stringify({"physics": PhysicsConfig.new().to_dict(),
		"rules": rc.to_dict(), "course": "starter", "wind_custom": false, "wind_speed": 0.0, "wind_bearing": 0.0}))
	var repo := TestHelpers.make_repo()
	var seasons: Array[String] = []
	for i in 2:
		var s := OnlineSession.new(PhysicsConfig.new(), repo)
		var got := OnlineSession.apply_setup(s, setup)
		assert_true(s.rules.order_by_stats, "frozen rules reach the session")
		assert_false(s.rules.show_stats, "numbers stay hidden")
		seasons.append(JSON.stringify(Season.create(got.season_courses).to_dict()))
	assert_eq(seasons[0], seasons[1], "both phones build the identical season")
	assert_eq(Season.create(rc.season_courses).courses.size(), 3, "repeats allowed")


func test_picker_offers_stat_sorts_only_when_opted_in() -> void:
	var repo := TestHelpers.make_repo()
	var alpha := repo.sorted_by("name_az")
	var by_caps := repo.sorted_by("caps_hi")
	assert_eq(alpha.size(), by_caps.size())
	for i in range(1, by_caps.size()):
		assert_true(by_caps[i - 1].caps >= by_caps[i].caps, "caps high-low")
	var low := repo.sorted_by("goals_lo")
	for i in range(1, low.size()):
		assert_true(low[i - 1].goals <= low[i].goals, "goals low-high")
	var p := FootballerPicker.new()
	assert_false(p.stat_sort, "off by default")
	assert_false(p.show_stats)
	p.free()
