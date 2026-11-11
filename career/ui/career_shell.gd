class_name CareerShell
extends RefCounted
## The Career home: hero header (identity, world rank, season progress), scrolling tab content and a bottom tab bar
## (Hub / Schedule / Rankings / Me). Presentation only (CareerManager owns every rule and number).
## Navigation: the Hub shell sits on the MainMenu page stack; the other tabs are pushed on top of it, so Android
## Back from Schedule / Rankings / Me returns to the Hub, and Back on the Hub leaves Career.

const TABS := [["hub", "Hub", "flag"], ["schedule", "Schedule", "list"], ["rankings", "Rankings", "bars"], ["me", "Me", "player"]]
const NEWS_ROWS := 6
const TOP_ROWS := 10

static var rank_view := 0  # 0 = World Ranking, 1 = Season Standings (Rankings tab)


# ------------------------------------------------------------------ navigation

static func open(menu: MainMenu, tab: String = "hub") -> void:
	menu._push(_shell(menu, tab))


## Switch tab: non-Hub tabs replace each other on top of the Hub; going to the Hub rebuilds it fresh.
static func go(menu: MainMenu, tab: String) -> void:
	var top: Control = menu._stack.back()
	var cur := String(top.get_meta("career_tab", ""))
	if cur == tab:
		return
	if tab == "hub":
		while menu._stack.size() > 1 and String(menu._stack.back().get_meta("career_tab", "")) != "":
			menu._pop()
		open(menu, "hub")
		return
	if cur != "" and cur != "hub":
		menu._pop()
	open(menu, tab)


static func _shell(menu: MainMenu, tab: String) -> Control:
	var c := CareerManager.active
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("career_tab", tab)
	var nxt := c.next_event()
	var tint := CareerKit.tier_color(String(nxt.get("category", "regular"))) if not nxt.is_empty() else CareerKit.C_MAJOR
	root.add_child(CareerKit.backdrop(tint))
	var sm := menu._safe()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(sm[0]) - 8)
	m.add_theme_constant_override("margin_right", int(sm[2]) - 8)
	m.add_theme_constant_override("margin_top", int(sm[1]) - 8)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) - 16)
	root.add_child(m)
	var v := UiKit.vbox(14)
	m.add_child(v)
	v.add_child(_hero(menu, c, tab))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	v.add_child(sc)
	var body := UiKit.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	match tab:
		"schedule":
			_schedule(menu, c, body)
		"rankings":
			_rankings(menu, c, body)
		"me":
			_me(menu, c, body)
		_:
			_hub(menu, c, body)
	body.add_child(CareerKit.spacer(8))
	var i := 0
	for ch in body.get_children():
		CareerKit.appear(ch as Control, i)
		i += 1
	v.add_child(_tab_bar(menu, tab))
	return root


static func _tab_bar(menu: MainMenu, current: String) -> Control:
	var p := PanelContainer.new()
	var sb := CareerKit.flat(Color(0.03, 0.06, 0.12, 0.96), 24, 6.0, Color(0.6, 0.78, 1.0, 0.22), 1)
	p.add_theme_stylebox_override("panel", sb)
	var h := UiKit.hbox(4)
	p.add_child(h)
	for t in TABS:
		var id := String(t[0])
		var on := id == current
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 108)
		var hl := CareerKit.flat(Color(0.71, 0.97, 0.35, 0.12) if on else Color(0, 0, 0, 0), 18, 0.0, Color(0, 0, 0, 0), 0)
		CareerKit._btn_styles(b, hl, CareerKit.flat(Color(1, 1, 1, 0.06), 18, 0.0, Color(0, 0, 0, 0), 0), CareerKit.flat(Color(0, 0, 0, 0.25), 18, 0.0, Color(0, 0, 0, 0), 0))
		var v := UiKit.vbox(4)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var cc := CenterContainer.new()
		cc.add_child(LineIcon.make(String(t[2]), 38, CareerKit.C_LIME if on else CareerKit.C_MUTED))
		v.add_child(cc)
		v.add_child(CareerKit.text(String(t[1]).to_upper(), 16, CareerKit.C_LIME if on else CareerKit.C_MUTED, "caps", false, HORIZONTAL_ALIGNMENT_CENTER))
		var cc2 := CenterContainer.new()
		cc2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cc2.add_child(v)
		b.add_child(cc2)
		CareerKit._ignore_tree(cc2)
		cc2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tab_id := id
		CareerKit._wire(b, func() -> void: go(menu, tab_id), "career_tab_%s" % id, String(t[1]))
		h.add_child(b)
	return p


# ------------------------------------------------------------------ hero

static func events_done(c: CareerManager) -> int:
	var n := 0
	for e in c.data["calendar"]:
		if String(e["status"]) in ["complete", "skipped"]:
			n += 1
	return n


static func last_result(c: CareerManager) -> Dictionary:
	return CareerWorldPages._last_result(c)


static func _hero(menu: MainMenu, c: CareerManager, tab: String) -> Control:
	var p: Dictionary = c.data["player"]
	var eco: Dictionary = c.data["economy"]
	var season: Dictionary = c.data["season"]
	var compact := tab != "hub"
	var v := UiKit.vbox(10 if not compact else 6)
	var top := UiKit.hbox(14)
	top.add_child(CareerKit.nation_chip(String(p["nationality"]), 30))
	var nm := CareerKit.trim(CareerKit.text(String(p["name"]).to_upper(), 30, Color.WHITE, "display"))
	top.add_child(nm)
	var gear := Button.new()
	gear.custom_minimum_size = Vector2(CareerKit.TOUCH, 72)
	var e := StyleBoxEmpty.new()
	CareerKit._btn_styles(gear, e, CareerKit.flat(Color(1, 1, 1, 0.08), 18, 0.0, Color(0, 0, 0, 0), 0), e)
	var gc := CenterContainer.new()
	gc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gc.add_child(LineIcon.make("gear", 34, CareerKit.C_MUTED))
	gear.add_child(gc)
	CareerKit._wire(gear, func() -> void: CareerPages.open_settings(menu), "career_settings_gear", "")
	top.add_child(gear)
	v.add_child(top)
	# stats
	var st := UiKit.hbox(12)
	var wr := c.world_rank()
	var lr := last_result(c)
	var wdelta := (int(lr["world_rank_before"]) - int(lr["world_rank_after"])) if not lr.is_empty() else 0
	var wcol := UiKit.hbox(8)
	wcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wv := UiKit.vbox(0)
	wv.add_child(CareerKit.caption("World rank", CareerKit.C_MUTED))
	var wh := UiKit.hbox(8)
	var wl := CareerKit.text("#%d" % wr, 54 if not compact else 40, Color.WHITE, "display")
	CareerKit.count_up(wl, float(wr), func(x: float) -> String: return "#%d" % int(round(x)))
	wh.add_child(wl)
	if not lr.is_empty():
		var a := CareerKit.move_arrow(wdelta, true, 20)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wh.add_child(a)
	wv.add_child(wh)
	wcol.add_child(wv)
	st.add_child(wcol)
	var sr := c.season_rank()
	st.add_child(CareerKit.stat("Standings", CareerKit.ordinal(sr) if sr > 0 else "-", "%d pts" % c.season_points(), Color.WHITE, 40 if not compact else 32))
	var earn := int(eco["season_earnings"])
	st.add_child(CareerKit.stat("Earnings", CareerKit.money_short(earn), "this season", CareerKit.C_UP if earn > 0 else Color.WHITE, 40 if not compact else 32,
		float(earn), func(x: float) -> String: return CareerKit.money_short(int(round(x)))))
	v.add_child(st)
	# season progress
	var total := (c.data["calendar"] as Array).size()
	var done := events_done(c)
	var ph := UiKit.hbox(10)
	ph.add_child(CareerKit.trim(CareerKit.caption("Season %d · %s" % [int(season["number"]), CareerConfig.season_label(String(season["length"]))], CareerKit.C_MUTED)))
	ph.add_child(CareerKit.text("%d / %d EVENTS" % [done, total], 16, Color.WHITE, "caps"))
	v.add_child(ph)
	v.add_child(CareerKit.progress(float(done) / maxf(1.0, float(total)), CareerKit.C_LIME, 10))
	var p_card := CareerKit.card(v, CareerKit.glass(Color(0.13, 0.28, 0.52, 0.92), Color(0.05, 0.11, 0.23, 0.96), 24.0, 22.0))
	return p_card


# ------------------------------------------------------------------ hub tab

static func _hub(menu: MainMenu, c: CareerManager, body: VBoxContainer) -> void:
	if c.store.is_blocked():
		body.add_child(_save_banner(menu, c))
	var feature := UiKit.vbox(10)
	if c.has_active_tournament():
		var t := c.tournament()
		var ev: Dictionary = t["event"]
		var rounds := int(ev["rounds"])
		var ri := mini(int(t["round_index"]) + 1, rounds)
		feature.add_child(_feature_card(menu, c, ev, "LIVE · ROUND %d OF %d" % [ri, rounds], CareerPages._status_text(String(t["status"])).capitalize(), func() -> void: CareerPages.open_tournament(menu)))
		feature.add_child(CareerKit.cta("Continue tournament", String(ev["name"]), func() -> void: CareerPages.open_tournament(menu), "career_continue"))
	else:
		var e := c.next_event()
		if e.is_empty():
			var v := UiKit.vbox(8)
			v.add_child(CareerKit.caption("Season complete", CareerKit.C_MAJOR))
			v.add_child(CareerKit.text("That's a wrap on season %d" % c.season_number(), 34, Color.WHITE, "display", true))
			v.add_child(CareerKit.text("Review the season, talk to sponsors, visit the shop and catch up on world news before the new calendar.", 21, CareerKit.C_MUTED, "", true))
			feature.add_child(CareerKit.card(v, CareerKit.glass(Color(0.35, 0.27, 0.08, 0.92), Color(0.10, 0.08, 0.04, 0.96), 22.0, 24.0)))
			feature.add_child(CareerKit.cta("Continue off-season" if c.off_season_active() else "Begin off-season", "Season review · sponsors · shop · news", func() -> void:
				if c.begin_off_season():
					CareerOffSeasonPages.open(menu)
				else:
					CareerPages._present_save_error(menu, c.store, func() -> void: CareerOffSeasonPages.open(menu)), "career_next_season"))
		else:
			var el := c.eligibility(e)
			var serial := int(e["serial"])
			feature.add_child(_feature_card(menu, c, e, "NEXT UP · EVENT %d OF %d" % [serial, (c.data["calendar"] as Array).size()], String(el["reason"]),
				func() -> void: CareerPages.open_event(menu, serial), bool(el["eligible"])))
			var eligible := bool(el["eligible"])
			feature.add_child(CareerKit.cta("Play next event" if eligible else "View event", "%d rounds · purse %s" % [int(e["rounds"]), CareerKit.money_short(int(e["purse"]))] if eligible else "You are not eligible for this one",
				func() -> void:
					if not eligible:
						CareerPages.open_event(menu, serial)
					elif c.enter_event(serial):
						CareerPages.open_tournament(menu)
					elif c.store.is_blocked():
						CareerPages._present_save_error(menu, c.store, Callable()), "career_next_event"))
			var links := UiKit.hbox(8)
			var d := CareerKit.link("Event details", func() -> void: CareerPages.open_event(menu, serial), "career_event_details", UiKit.C_CYAN)
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			links.add_child(d)
			var sk := CareerKit.link("Skip event", func() -> void:
				if c.skip_next_event():
					CareerPages._replace(menu, func() -> void: open(menu, "hub"))
				elif c.store.is_blocked():
					CareerPages._present_save_error(menu, c.store, func() -> void: CareerPages._replace(menu, func() -> void: open(menu, "hub"))), "career_hub_skip")
			sk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			links.add_child(sk)
			feature.add_child(links)
	body.add_child(feature)
	# calendar strip
	var cal := UiKit.vbox(10)
	cal.add_child(CareerKit.section("This season", "%d of %d played" % [events_done(c), (c.data["calendar"] as Array).size()]))
	cal.add_child(_strip(menu, c))
	body.add_child(cal)
	# quick tiles
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	var sr := c.season_rank()
	var moves := CareerKit.note_ranks(c)
	grid.add_child(_tile("Standings", CareerKit.ordinal(sr) if sr > 0 else "-", "%d pts · top %d make finale" % [c.season_points(), CareerConfig.FINALE_QUALIFIERS], "list",
		UiKit.C_CYAN, func() -> void: CareerWorldPages.open_standings(menu), "career_standings", int((moves["ss"] as Dictionary).get(CareerManager.PLAYER, 0))))
	grid.add_child(_tile("World Ranking", "#%d" % c.world_rank(), "of %d golfers" % c.world_table().size(), "bars", CareerKit.C_REGULAR,
		func() -> void: CareerWorldPages.open_world_ranking(menu), "career_world_ranking", int((moves["world"] as Dictionary).get(CareerManager.PLAYER, 0))))
	CareerSponsorPages.hub_refresh(c)
	var k := SponsorManager.contract_for(c.data, c.season_id())
	grid.add_child(_tile("Sponsor", String(SponsorManager.by_id(String(k["sponsor_id"])).get("name", "Signed")) if not k.is_empty() else "%d offers" % (SponsorManager.ensure_offers(c.data, c.season_id(), c.world_rank(), c.career_seed()) as Array).size(),
		"Contract active" if not k.is_empty() else "Sign one per season", "trophy", CareerKit.C_MAJOR, func() -> void: CareerSponsorPages.open_sponsor_review(menu), "career_sponsors"))
	var nnew := ShopManager.new_count(c.data)
	grid.add_child(_tile("Shop", CareerKit.money_short(int((c.data["economy"] as Dictionary)["balance"])), ("%d new items" % nnew) if nnew > 0 else "Cosmetics only", "star",
		CareerKit.C_FLAGSHIP, func() -> void: CareerShopPages.open_shop(menu), "career_shop"))
	body.add_child(grid)
	# inbox
	var inbox := UiKit.vbox(10)
	var items := _news(menu, c)
	inbox.add_child(CareerKit.section("Inbox", "%d new" % items.size() if not items.is_empty() else ""))
	if items.is_empty():
		inbox.add_child(CareerKit.info_card("", ["Nothing yet. Results, sponsor offers and tour news land here after your first event."]))
	for it in items:
		inbox.add_child(it)
	body.add_child(inbox)
	body.add_child(_status_card(c))


static func _save_banner(menu: MainMenu, c: CareerManager) -> Control:
	var v := UiKit.vbox(8)
	v.add_child(CareerKit.caption("Save failed", UiKit.C_WARN))
	v.add_child(CareerKit.text(c.store.last_error, 20, Color.WHITE, "", true))
	v.add_child(CareerKit.ghost("Retry Save", func() -> void:
		if c.store.retry():
			CareerPages._replace(menu, func() -> void: open(menu, "hub")), "career_retry", UiKit.C_WARN))
	return CareerKit.card(v, CareerKit.striped(Color(0.25, 0.14, 0.05, 0.95), UiKit.C_WARN))


## Big next-event card with tier stripe and glow.
static func _feature_card(menu: MainMenu, c: CareerManager, e: Dictionary, kicker: String, note: String, cb: Callable, ok: bool = true) -> Control:
	var cat := String(e["category"])
	var col := CareerKit.tier_color(cat)
	var v := UiKit.vbox(8)
	var h := UiKit.hbox(10)
	h.add_child(CareerKit.tier_chip(cat))
	h.add_child(CareerKit.trim(CareerKit.text(kicker, 16, CareerKit.C_MUTED, "caps", false, HORIZONTAL_ALIGNMENT_RIGHT)))
	v.add_child(h)
	v.add_child(CareerKit.text(String(e["name"]), 38, Color.WHITE, "display", true))
	var info := CourseSource.course_info(String(e["course_id"]))
	v.add_child(CareerKit.text("%s  ·  %d holes per round" % [String(info.get("name", e["course_id"])), (info.get("holes", []) as Array).size()], 21, CareerKit.C_MUTED, "", true))
	var st := UiKit.hbox(10)
	st.add_child(CareerKit.stat("Rounds", str(int(e["rounds"])), "", Color.WHITE, 32))
	st.add_child(CareerKit.stat("Field", str(int(e["field_size"])), "", Color.WHITE, 32))
	st.add_child(CareerKit.stat("Purse", CareerKit.money_short(int(e["purse"])), "", CareerKit.C_UP, 32))
	st.add_child(CareerKit.stat("Win pts", str(int((e["points"] as Dictionary).get("winner", 0))), "", col, 32))
	v.add_child(st)
	if note != "":
		var nh := UiKit.hbox(10)
		var ic := LineIcon.make("check" if ok else "close", 24, CareerKit.C_UP if ok else UiKit.C_WARN)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nh.add_child(ic)
		nh.add_child(CareerKit.text(note, 19, CareerKit.C_UP if ok else UiKit.C_WARN, "", true))
		v.add_child(nh)
	var sk := CareerKit.glass(Color(col.r * 0.32 + 0.04, col.g * 0.32 + 0.07, col.b * 0.32 + 0.14, 0.95), Color(0.05, 0.09, 0.18, 0.97), 22.0, 24.0)
	sk.border = Color(col.r, col.g, col.b, 0.6)
	sk.rim = col
	return CareerKit.tap_card(v, cb, "career_feature", Color(0, 0, 0, 0), 120, false, String(e["name"]), [sk, sk, sk], 24.0)



## Horizontal calendar strip, scrolled so the next event is in view.
static func _strip(menu: MainMenu, c: CareerManager) -> Control:
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.scroll_deadzone = 14
	sc.custom_minimum_size = Vector2(0, 176)
	var h := UiKit.hbox(12)
	sc.add_child(h)
	var nxt := c.next_event()
	var focus := 0
	var i := 0
	for e in c.data["calendar"]:
		var st := event_status(c, e, nxt)
		var cat := String(e["category"])
		var col := CareerKit.tier_color(cat)
		var v := UiKit.vbox(4)
		var top := UiKit.hbox(6)
		top.add_child(CareerKit.trim(CareerKit.text("#%d" % int(e["serial"]), 17, col, "caps")))
		v.add_child(top)
		var nm := CareerKit.text(String(e["name"]), 19, Color.WHITE, "semi", true)
		nm.max_lines_visible = 2
		nm.custom_minimum_size.y = CareerKit.fs(19) * 2.75
		v.add_child(nm)
		v.add_child(CareerKit.text(String(st["text"]), 19, st["color"], "caps"))
		var is_next: bool = e == nxt
		var serial := int(e["serial"])
		var b := CareerKit.tap_card(v, func() -> void: CareerPages.open_event(menu, serial), "career_strip_%d" % serial, col, 164, is_next, String(e["name"]), [], 14.0)
		b.custom_minimum_size.x = 184
		var dim: bool = String(e["status"]) in ["complete", "skipped"]
		if dim and not reduced_contrast():
			b.self_modulate = Color(1, 1, 1, 0.8)
		h.add_child(b)
		if is_next:
			focus = i
		i += 1
	sc.ready.connect(func() -> void:
		var go_to := func() -> void:
			if is_instance_valid(sc):
				sc.scroll_horizontal = maxi(0, focus * 188 - 40)
		go_to.call_deferred(), CONNECT_ONE_SHOT)
	return sc


static func reduced_contrast() -> bool:
	return false


static func _tile(title: String, value: String, sub: String, icon: String, color: Color, cb: Callable, ui_id: String, delta: int = 0) -> Control:
	var v := UiKit.vbox(2)
	var h := UiKit.hbox(8)
	h.add_child(CareerKit.trim(CareerKit.caption(title, color)))
	var ic := LineIcon.make(icon, 26, color)
	h.add_child(ic)
	v.add_child(h)
	var vh := UiKit.hbox(8)
	var vl := CareerKit.text(value, 34, Color.WHITE, "display")
	vl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vl.clip_text = true
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vh.add_child(vl)
	if delta != 0:
		var a := CareerKit.move_arrow(delta, true, 18)
		a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vh.add_child(a)
	v.add_child(vh)
	v.add_child(CareerKit.trim(CareerKit.text(sub, 17, CareerKit.C_MUTED)))
	var b := CareerKit.tap_card(v, cb, ui_id, Color(0, 0, 0, 0), 150, false, title)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


static func _status_card(c: CareerManager) -> Control:
	var held := OffSeason.has_card(c)
	var v := UiKit.vbox(6)
	var h := UiKit.hbox(10)
	h.add_child(CareerKit.trim(CareerKit.caption("LBT status")))
	h.add_child(CareerKit.chip("Card held" if held else "No card", CareerKit.C_UP if held else UiKit.C_WARN))
	v.add_child(h)
	v.add_child(CareerKit.text(OffSeason.card_status_text(c), 19, Color.WHITE, "", true))
	v.add_child(CareerKit.text(AdaptiveDifficulty.hint_text(c.data), 19, CareerKit.C_MUTED, "", true))
	return CareerKit.card(v)


## Status text and colour of an event for cards and the strip.
static func event_status(c: CareerManager, e: Dictionary, nxt: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var r: Dictionary = e.get("result", {})
	match String(e["status"]):
		"complete":
			if not bool(r.get("human_played", true)):
				return {"text": "Not played", "color": CareerKit.C_FAINT}
			if bool(r.get("human_won", false)):
				return {"text": "Won", "color": CareerKit.C_MAJOR}
			if bool(r.get("human_missed_cut", false)):
				return {"text": "Missed cut", "color": CareerKit.C_DOWN}
			return {"text": String(r.get("human_place_label", "")) if String(r.get("human_place_label", "")) != "" else CareerKit.ordinal(int(r.get("human_place", 0))), "color": Color.WHITE}
		"skipped":
			return {"text": "Skipped", "color": CareerKit.C_FAINT}
		"in_progress":
			return {"text": "Live", "color": CareerKit.C_UP}
	if e == nxt:
		return {"text": "Next", "color": CareerKit.C_LIME}
	var el := c.eligibility(e, ctx)
	return {"text": "Open" if bool(el["eligible"]) else "Locked", "color": CareerKit.C_MUTED if bool(el["eligible"]) else UiKit.C_WARN}


# ------------------------------------------------------------------ inbox / news

static func _news(menu: MainMenu, c: CareerManager) -> Array:
	var out: Array = []
	var sid := c.season_id()
	if SponsorManager.contract_for(c.data, sid).is_empty():
		var n := (SponsorManager.ensure_offers(c.data, sid, c.world_rank(), c.career_seed()) as Array).size()
		if n > 0:
			out.append(_news_item("trophy", CareerKit.C_MAJOR, "%d sponsor offer%s on the table" % [n, "" if n == 1 else "s"], "Sign one primary sponsor for season %d" % c.season_number(),
				"Action", func() -> void: CareerSponsorPages.open_sponsor_review(menu), "career_news_sponsor"))
	var nn := ShopManager.new_count(c.data)
	if nn > 0:
		out.append(_news_item("star", CareerKit.C_FLAGSHIP, "%d new item%s unlocked in the shop" % [nn, "" if nn == 1 else "s"], "Cosmetics only: ball, flag, outfit and more", "Shop",
			func() -> void: CareerShopPages.open_shop(menu), "career_news_shop"))
	if not OffSeason.has_card(c):
		out.append(_news_item("flag", UiKit.C_WARN, "Playing on sponsor wildcards", "%d wildcard%s left this season" % [OffSeason.wildcards_left(c), "" if OffSeason.wildcards_left(c) == 1 else "s"], "Tour", Callable(), ""))
	var done: Array = []
	for e in c.data["calendar"]:
		if String(e["status"]) in ["complete", "skipped"]:
			done.append(e)
	done.reverse()
	for e in done:
		if out.size() >= NEWS_ROWS:
			break
		var r: Dictionary = e["result"]
		var ev: Dictionary = e
		var cb := (func() -> void: CareerWorldPages.open_report(menu, ev, false)) if r.has("report") else Callable()
		var tag := "Event %d" % int(e["serial"])
		var wr := ""
		if r.has("world_rank_after"):
			var d := int(r.get("world_rank_before", 0)) - int(r.get("world_rank_after", 0))
			wr = "  ·  World #%d%s" % [int(r["world_rank_after"]), (" (up %d)" % d) if d > 0 else ((" (down %d)" % -d) if d < 0 else "")]
		if bool(r.get("human_played", false)):
			if bool(r.get("human_won", false)):
				out.append(_news_item("trophy", CareerKit.C_MAJOR, "Champion! You won the %s" % String(e["name"]), "%s to par  ·  %s%s" % [RoundState.fmt_relative(int(r.get("human_rel", 0))), CareerPages.money(int(r.get("human_earnings", 0))), wr], tag, cb, "career_news_%d" % int(e["serial"])))
			elif bool(r.get("human_missed_cut", false)):
				out.append(_news_item("close", CareerKit.C_DOWN, "Missed the cut at the %s" % String(e["name"]), "%s won at %s%s" % [r.get("winner_name", "?"), RoundState.fmt_relative(int(r.get("winner_to_par", 0))), wr], tag, cb, "career_news_%d" % int(e["serial"])))
			else:
				out.append(_news_item("flag", CareerKit.tier_color(String(e["category"])), "You finished %s at the %s" % [CareerWorldPages.place_text(String(r.get("human_place_label", "")), int(r.get("human_place", 0))), String(e["name"])],
					"%s won  ·  you earned %s%s" % [r.get("winner_name", "?"), CareerPages.money(int(r.get("human_earnings", 0))), wr], tag, cb, "career_news_%d" % int(e["serial"])))
		else:
			out.append(_news_item("course", CareerKit.C_FAINT, "%s wins the %s" % [r.get("winner_name", "?"), String(e["name"])], "You sat this one out%s" % wr, tag, cb, "career_news_%d" % int(e["serial"])))
	return out.slice(0, NEWS_ROWS)


static func _news_item(icon: String, color: Color, title: String, sub: String, tag: String, cb: Callable, ui_id: String) -> Control:
	var h := UiKit.hbox(16)
	h.add_child(CareerKit.icon_disc(icon, color, 56))
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(CareerKit.text(title, 22, Color.WHITE, "semi", true))
	tv.add_child(CareerKit.text(sub, 18, CareerKit.C_MUTED, "", true))
	h.add_child(tv)
	var rv := UiKit.vbox(4)
	rv.add_child(CareerKit.text(tag.to_upper(), 14, CareerKit.C_FAINT, "caps", false, HORIZONTAL_ALIGNMENT_RIGHT))
	if cb.is_valid():
		var ch := LineIcon.make("chevron_right", 24, Color(1, 1, 1, 0.5))
		ch.size_flags_horizontal = Control.SIZE_SHRINK_END
		rv.add_child(ch)
	h.add_child(rv)
	if cb.is_valid():
		return CareerKit.tap_card(h, cb, ui_id, Color(0, 0, 0, 0), CareerKit.TOUCH, false, title, [], 16.0)
	var sb := CareerKit.flat(CareerKit.C_CARD, 16, 16.0)
	return CareerKit.card(h, sb)


# ------------------------------------------------------------------ schedule tab

static func _schedule(menu: MainMenu, c: CareerManager, body: VBoxContainer) -> void:
	var cal: Array = c.data["calendar"]
	var played := 0
	var skipped := 0
	var wins := 0
	for e in cal:
		match String(e["status"]):
			"complete":
				played += 1
				if bool((e["result"] as Dictionary).get("human_won", false)):
					wins += 1
			"skipped":
				skipped += 1
	var sum := UiKit.hbox(10)
	sum.add_child(CareerKit.stat("Events", str(cal.size()), "", Color.WHITE, 34))
	sum.add_child(CareerKit.stat("Played", str(played), "", Color.WHITE, 34))
	sum.add_child(CareerKit.stat("Skipped", str(skipped), "", CareerKit.C_MUTED, 34))
	sum.add_child(CareerKit.stat("Wins", str(wins), "", CareerKit.C_MAJOR, 34))
	body.add_child(CareerKit.card(sum))
	var legend := HFlowContainer.new()
	legend.add_theme_constant_override("h_separation", 8)
	legend.add_theme_constant_override("v_separation", 8)
	for cat in ["regular", "flagship", "major", "finale"]:
		legend.add_child(CareerKit.tier_chip(cat))
	body.add_child(legend)
	var nxt := c.next_event()
	var ctx := c.qual_ctx()
	var list := UiKit.vbox(12)
	for e in cal:
		list.add_child(event_card(menu, c, e, nxt, ctx))
	body.add_child(list)


static func event_card(menu: MainMenu, c: CareerManager, e: Dictionary, nxt: Dictionary, ctx: Dictionary) -> Control:
	var cat := String(e["category"])
	var col := CareerKit.tier_color(cat)
	var st := event_status(c, e, nxt, ctx)
	var h := UiKit.hbox(16)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", CareerKit.flat(Color(col.r, col.g, col.b, 0.18), 14, 0.0, Color(col.r, col.g, col.b, 0.6), 1))
	badge.custom_minimum_size = Vector2(64, 64)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bc := CenterContainer.new()
	bc.add_child(CareerKit.text(str(int(e["serial"])), 28, col, "display"))
	badge.add_child(bc)
	h.add_child(badge)
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(CareerKit.text(CareerKit.tier_label(cat), 15, col, "caps"))
	tv.add_child(CareerKit.trim(CareerKit.text(String(e["name"]), 25, Color.WHITE, "semi")))
	tv.add_child(CareerKit.trim(CareerKit.text("%s  ·  %d rds  ·  %s" % [String(CourseSource.course_info(String(e["course_id"])).get("name", "")), int(e["rounds"]), CareerKit.money_short(int(e["purse"]))], 18, CareerKit.C_MUTED)))
	h.add_child(tv)
	var sc := CareerKit.text(String(st["text"]).to_upper(), 19, st["color"], "caps", false, HORIZONTAL_ALIGNMENT_RIGHT)
	sc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sc)
	var serial := int(e["serial"])
	var b := CareerKit.tap_card(h, func() -> void: CareerPages.open_event(menu, serial), "career_event_%d" % serial, col, 112, e == nxt, String(e["name"]), [], 16.0)
	if String(e["status"]) in ["complete", "skipped"]:
		b.modulate = Color(1, 1, 1, 0.82)
	return b


# ------------------------------------------------------------------ rankings tab

static func _rankings(menu: MainMenu, c: CareerManager, body: VBoxContainer) -> void:
	var holder := UiKit.vbox(16)
	var fn := {}  # lambdas capture by value: keep the rebuild callable in a shared dictionary
	fn["rebuild"] = func() -> void:
		UiKit.clear(holder)
		holder.add_child(CareerKit.segmented(["World Ranking", "Season Standings"], rank_view, func(i: int) -> void:
			rank_view = i
			(fn["rebuild"] as Callable).call(), "career_rank_view"))
		_rank_summary(menu, c, holder)
		for ch in holder.get_children():
			if ch is Control and (ch as Control).is_inside_tree():
				(ch as Control).modulate.a = 1.0
	(fn["rebuild"] as Callable).call()
	body.add_child(holder)
	body.add_child(CareerKit.row("people", "Rivals", "Head-to-head records", str((c.data["rivalries"] as Array).size()), func() -> void: CareerWorldPages.open_rivals(menu), "career_rivals"))


static func _rank_summary(menu: MainMenu, c: CareerManager, holder: VBoxContainer) -> void:
	var world := rank_view == 0
	var wt := c.world_table()
	var rows := wt if world else c.standings_table(wt)
	var moves: Dictionary = CareerKit.note_ranks(c)["world" if world else "ss"]
	var me := {}
	var me_i := 0
	for i in rows.size():
		if bool(rows[i]["is_human"]):
			me = rows[i]
			me_i = i
	var started := world or not (c.standings()["applied"] as Dictionary).is_empty()
	var v := UiKit.vbox(6)
	var h := UiKit.hbox(14)
	var big := CareerKit.stat("Your rank", ("#%d" % int(me.get("rank", 0))) if started else "-", "of %d" % rows.size(), CareerKit.C_LIME, 56)
	h.add_child(big)
	h.add_child(CareerKit.stat("Points", str(int(round(float(me.get("points", 0.0))))), "two-season window" if world else "season %d" % c.season_number(), Color.WHITE, 40))
	var d := int(moves.get(CareerManager.PLAYER, 0))
	var mv := UiKit.vbox(0)
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.add_child(CareerKit.caption("Move", CareerKit.C_MUTED))
	mv.add_child(CareerKit.move_arrow(d, true, 34))
	h.add_child(mv)
	v.add_child(h)
	var note := ""
	var rk := int(me.get("rank", 0))
	if world:
		note = "Majors: top %d  ·  Flagships: top %d. You are %s." % [CareerConfig.MAJOR_MAX_WORLD_RANK, CareerConfig.FLAGSHIP_MAX_WORLD_RANK,
			"inside both lines" if rk <= CareerConfig.MAJOR_MAX_WORLD_RANK else ("inside the flagship line" if rk <= CareerConfig.FLAGSHIP_MAX_WORLD_RANK else "outside both lines")]
	elif started:
		note = "Top %d reach the LBT Championship  ·  top %d keep the card. You are %s the finale line." % [CareerConfig.FINALE_QUALIFIERS, CareerConfig.TOUR_CARD_RETENTION_RANK, "inside" if rk <= CareerConfig.FINALE_QUALIFIERS else "outside"]
	else:
		note = "Not ranked until the season has results."
	v.add_child(CareerKit.text(note, 19, CareerKit.C_MUTED, "", true))
	holder.add_child(CareerKit.card(v, CareerKit.glass(Color(0.12, 0.25, 0.46, 0.92), Color(0.05, 0.10, 0.21, 0.96), 20.0, 22.0)))
	var list := UiKit.vbox(2)
	list.add_child(CareerKit.section("Top %d" % TOP_ROWS, "Points"))
	var lines := {CareerConfig.MAJOR_MAX_WORLD_RANK: "Majors line", CareerConfig.FLAGSHIP_MAX_WORLD_RANK: "Flagships line"} if world else \
		{CareerConfig.FINALE_QUALIFIERS: "Finale line", CareerConfig.TOUR_CARD_RETENTION_RANK: "Card line"}
	var show: Array = []
	for i in mini(TOP_ROWS, rows.size()):
		show.append(i)
	if me_i >= TOP_ROWS:
		show.append(-1)
		for i in range(maxi(TOP_ROWS, me_i - 2), mini(rows.size(), me_i + 3)):
			show.append(i)
	for i in show:
		if int(i) < 0:
			list.add_child(CareerKit.text("· · ·", 20, CareerKit.C_FAINT, "caps", false, HORIZONTAL_ALIGNMENT_CENTER))
			continue
		var r: Dictionary = rows[i]
		var sub := ("%dW" % int(r["wins"])) if not world and int(r.get("wins", 0)) > 0 else ""
		list.add_child(CareerKit.rank_row(str(int(r["rank"])), String(r["name"]), str(int(round(float(r["points"])))), int(moves.get(String(r["id"]), 0)), bool(r["is_human"]), sub))
		if lines.has(int(r["rank"])) and int(i) + 1 < rows.size() and show.has(int(i) + 1):
			list.add_child(CareerKit.line_marker(String(lines[int(r["rank"])])))
	holder.add_child(CareerKit.card(list))
	holder.add_child(CareerKit.ghost("Full World Ranking" if world else "Full Season Standings", func() -> void:
		if world:
			CareerWorldPages.open_world_ranking(menu)
		else:
			CareerWorldPages.open_standings(menu), "career_rank_full"))


# ------------------------------------------------------------------ me tab

static func _me(menu: MainMenu, c: CareerManager, body: VBoxContainer) -> void:
	var rec: Dictionary = c.data["records"]
	var eco: Dictionary = c.data["economy"]
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 16)
	var fmt := func(x: float) -> String: return str(int(round(x)))
	g.add_child(CareerKit.stat("Wins", "", "", CareerKit.C_MAJOR, 40, float(rec["wins"]), fmt))
	g.add_child(CareerKit.stat("Majors", "", "", CareerKit.C_MAJOR, 40, float(rec["majors"]), fmt))
	g.add_child(CareerKit.stat("Top 10s", "", "", Color.WHITE, 40, float(rec["top10s"]), fmt))
	g.add_child(CareerKit.stat("Starts", "", "", Color.WHITE, 40, float(rec["starts"]), fmt))
	g.add_child(CareerKit.stat("Cuts made", "", "", Color.WHITE, 40, float(rec["cuts_made"]), fmt))
	g.add_child(CareerKit.stat("Best rank", ("#%d" % int(rec["best_world_rank"])) if int(rec["best_world_rank"]) > 0 else "-", "", CareerKit.C_LIME, 40))
	var rv := UiKit.vbox(12)
	rv.add_child(CareerKit.section("Career record"))
	rv.add_child(g)
	body.add_child(CareerKit.card(rv))
	# trophy shelf
	var shelf := UiKit.hbox(6)
	for k in [["major", "Majors", CareerKit.C_MAJOR], ["tour_championship", "LBT Champ", CareerKit.C_FINALE], ["season_title", "Season", UiKit.C_CYAN],
			["flagship", "Flagship", CareerKit.C_FLAGSHIP], ["event_win", "Wins", CareerKit.C_REGULAR]]:
		shelf.add_child(CareerKit.trophy(String(k[1]), CareerRecords.trophies_of(c.data, String(k[0])).size(), k[2]))
	var sv := UiKit.vbox(12)
	sv.add_child(CareerKit.section("Trophy shelf", "%d total" % (c.data["trophies"] as Array).size()))
	sv.add_child(shelf)
	body.add_child(CareerKit.tap_card(sv, func() -> void: CareerWorldPages.open_trophies(menu), "career_trophies", Color(0, 0, 0, 0), 200))
	# money
	var mv := UiKit.vbox(8)
	var mh := UiKit.hbox(10)
	mh.add_child(CareerKit.stat("Balance", "", "", Color.WHITE, 40, float(eco["balance"]), func(x: float) -> String: return CareerPages.money(int(round(x)))))
	mh.add_child(CareerKit.stat("Career earnings", CareerKit.money_short(int(eco["career_earnings"])), "", CareerKit.C_UP, 32))
	mv.add_child(mh)
	var rows := CareerRecords.ledger_recent(c.data, 4)
	rows.reverse()
	for t in rows:
		var lh := UiKit.hbox(10)
		lh.add_child(CareerKit.trim(CareerKit.text(String(t["label"]), 19, CareerKit.C_MUTED)))
		var amt := int(t["amount"])
		lh.add_child(CareerKit.text(("+" if amt > 0 else "") + CareerPages.money(amt), 19, CareerKit.C_UP if amt > 0 else CareerKit.C_DOWN, "num"))
		mv.add_child(lh)
	if rows.is_empty():
		mv.add_child(CareerKit.text("No transactions yet. Prize money appears here.", 19, CareerKit.C_MUTED, "", true))
	var mvv := UiKit.vbox(10)
	mvv.add_child(CareerKit.section("Money"))
	mvv.add_child(mv)
	body.add_child(CareerKit.card(mvv))
	var feat := CareerRecords.featured_rivals(c.data)
	body.add_child(CareerKit.row("people", "Rivals", ("%s (you %d - %d)" % [feat[0]["name"], int(feat[0]["wins"]), int(feat[0]["losses"])]) if not feat.is_empty() else "None yet", "",
		func() -> void: CareerWorldPages.open_rivals(menu), "career_rivals"))
	body.add_child(CareerKit.row("trophy", "Sponsors", CareerSponsorPages.hub_subtitle(c), "", func() -> void: CareerSponsorPages.open_sponsor_review(menu), "career_sponsors_me", CareerKit.C_MAJOR))
	body.add_child(CareerKit.row("star", "Shop", CareerShopPages.hub_subtitle(c), "", func() -> void: CareerShopPages.open_shop(menu), "career_shop_me", CareerKit.C_FLAGSHIP))
	body.add_child(_status_card(c))
	body.add_child(CareerKit.row("gear", "Career Settings", "Footballer rule, rivals' form, export, reset", "", func() -> void: CareerPages.open_settings(menu), "career_settings", CareerKit.C_MUTED))
