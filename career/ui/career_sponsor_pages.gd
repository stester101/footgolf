class_name CareerSponsorPages
extends RefCounted
## Career Sponsors screen: this season's contract (progress per objective) or up to three offers to choose from.
## Presentation only: rules live in SponsorManager. Entry point `open_sponsor_review(menu)` is used by the Hub row
## and can be called from the off-season flow (off_season_hook_sponsors). Back pops to the previous page.


## Hub bookkeeping (one line in the Hub): settles a finished season's contract and makes sure offers exist.
static func hub_refresh(c: CareerManager) -> void:
	var before := JSON.stringify(c.data.get("sponsorships", {}))
	SponsorManager.ensure_offers(c.data, c.season_id(), c.world_rank(), c.career_seed())
	if c.season_finished():
		SponsorManager.settle(c.data, c.season_id())
	if JSON.stringify(c.data["sponsorships"]) != before:
		c.store.commit(c.data)


static func hub_subtitle(c: CareerManager) -> String:
	var k := SponsorManager.contract_for(c.data, c.season_id())
	if not k.is_empty():
		return String(SponsorManager.by_id(String(k["sponsor_id"])).get("name", "Signed"))
	var n := (SponsorManager.ensure_offers(c.data, c.season_id(), c.world_rank(), c.career_seed()) as Array).size()
	return "%d offers waiting" % n if n > 0 else "No offers yet"


static func _tier_color(tier: String) -> Color:
	return {"local": Color("#9FD6A0"), "regional": Color("#8FC4FF"), "global": Color("#FFD24A")}.get(tier, Color.WHITE)


static func _sponsor_card(s: Dictionary, lines: Array, objective_rows: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 20, 14))
	var v := UiKit.vbox(4)
	var head := UiKit.hbox(10)
	var sw := ColorRect.new()
	sw.color = Color(String(s["color"]))
	sw.custom_minimum_size = Vector2(14, 34)
	head.add_child(sw)
	var t := UiKit.label(String(s["name"]).to_upper(), 22, UiKit.C_CYAN)
	t.add_theme_font_override("font", UiKit.font_caps())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	head.add_child(UiKit.label(SponsorManager.tier_label(String(s["tier"])), 19, _tier_color(String(s["tier"]))))
	v.add_child(head)
	v.add_child(UiKit.text(String(s["tagline"]), 20, UiKit.C_MUTED))
	for l in lines:
		var lab := UiKit.text(String(l), 22, Color.WHITE)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lab)
	for r in objective_rows:
		var h := UiKit.hbox(8)
		var col := Color.WHITE
		if bool(r["failed"]):
			col = UiKit.C_WARN
		elif bool(r["done"]):
			col = Color("#9BFF7A")
		var lab := UiKit.label(("✓ " if bool(r["done"]) else "· ") + String(r["label"]), 21, col)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.add_child(lab)
		h.add_child(UiKit.label("%s  %s" % [String(r["text"]), CareerPages.money(int(r["bonus"]))], 19, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(h)
	p.add_child(v)
	return p


static func _offer_rows(s: Dictionary) -> Array:
	var rows: Array = []
	for o in s["objectives"]:
		rows.append({"label": String(o["label"]), "bonus": int(o["bonus"]), "text": "", "done": false, "failed": false})
	return rows


static func open_sponsor_review(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = menu._page("Sponsors")
	var body: VBoxContainer = pg["body"]
	var sid := c.season_id()
	var offers: Array = SponsorManager.ensure_offers(c.data, sid, c.world_rank(), c.career_seed())
	var k := SponsorManager.contract_for(c.data, sid)
	body.add_child(CareerPages._card("SEASON %d" % c.season_number(), [
		"One primary sponsor per season. Objectives pay a bonus; missing them costs nothing but the sponsor's patience.",
		"World ranking %d  ·  balance %s" % [c.world_rank(), CareerPages.money(int((c.data["economy"] as Dictionary)["balance"]))]]))
	if not k.is_empty():
		var s := SponsorManager.by_id(String(k["sponsor_id"]))
		body.add_child(_sponsor_card(s, [
			"Contract: %s" % ("settled" if String(k["status"]) == "settled" else "active"),
			"Appearance fee %s per event  ·  %d played" % [CareerPages.money(int(s["appearance_fee"])), int(k["events"])],
			"Earned from this sponsor: %s" % CareerPages.money(int(k["fees"]) + int(k["bonuses"]))], SponsorManager.objective_rows(k)))
	else:
		if offers.is_empty():
			body.add_child(menu._note("No sponsor wants to talk yet. Climb the world ranking to attract better offers."))
		for id in offers:
			var s := SponsorManager.by_id(String(id))
			body.add_child(_sponsor_card(s, [
				"Signing bonus %s  ·  fee %s per event" % [CareerPages.money(int(s["signing_bonus"])), CareerPages.money(int(s["appearance_fee"]))]],
				_offer_rows(s)))
			var sid_c := String(id)
			body.add_child(menu._primary_button("Sign with %s" % String(s["name"]), func() -> void:
				var r := SponsorManager.sign(c.data, sid_c, sid, c.season_number())
				if bool(r["ok"]) and not c.store.commit(c.data):
					CareerPages._present_save_error(menu, c.store, Callable())
				CareerPages._replace(menu, func() -> void: open_sponsor_review(menu)), "sponsor_sign_%s" % sid_c))
	var pat: Dictionary = c.data["sponsorships"]["patience"]
	var cool: Array = []
	for s in SponsorManager.all():
		if int(pat.get(String(s["id"]), 0)) >= SponsorManager.PATIENCE_MAX:
			cool.append(String(s["name"]))
	if not cool.is_empty():
		body.add_child(menu._note("Not offering this season after missed seasons: %s." % ", ".join(cool)))
	body.add_child(menu._note("Regional sponsors need world rank %d or better, global sponsors %d or better." % [
		int(_tier_rank("regional")), int(_tier_rank("global"))]))
	c.store.commit(c.data)  # persists the generated offers (deterministic anyway)
	menu._push(pg["root"])


static func _tier_rank(tier: String) -> int:
	for s in SponsorManager.all():
		if String(s["tier"]) == tier:
			return int(s["unlock_rank"])
	return 0
