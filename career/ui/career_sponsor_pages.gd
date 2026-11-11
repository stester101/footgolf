class_name CareerSponsorPages
extends RefCounted
## Career Sponsors screen: this season's contract (progress per objective) or up to three offers to choose from.
## Presentation only: rules live in SponsorManager. Entry point `open_sponsor_review(menu)` is used by the Hub tile,
## the Me tab and the off-season flow (off_season_hook_sponsors). Back pops to the previous page.


## Hub bookkeeping: settles a finished season's contract and makes sure offers exist.
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


static func _sponsor_card(s: Dictionary, stats: Array, objective_rows: Array, signed: bool) -> Control:
	var brand := Color(String(s["color"]))
	var tier := String(s["tier"])
	var v := UiKit.vbox(10)
	var h := UiKit.hbox(14)
	var logo := PanelContainer.new()
	logo.add_theme_stylebox_override("panel", CareerKit.flat(brand, 14, 0.0, Color(1, 1, 1, 0.35), 1))
	logo.custom_minimum_size = Vector2(68, 68)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var lc := CenterContainer.new()
	lc.add_child(CareerKit.text(String(s["name"]).substr(0, 1).to_upper(), 34, Color.WHITE if brand.get_luminance() < 0.6 else Color("#0B1426"), "display"))
	logo.add_child(lc)
	h.add_child(logo)
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(CareerKit.chip(SponsorManager.tier_label(tier), _tier_color(tier)))
	tv.add_child(CareerKit.trim(CareerKit.text(String(s["name"]), 28, Color.WHITE, "display")))
	h.add_child(tv)
	if signed:
		h.add_child(CareerKit.chip("Signed", CareerKit.C_UP, true))
	v.add_child(h)
	v.add_child(CareerKit.text(String(s["tagline"]), 19, CareerKit.C_MUTED, "", true))
	var sh := UiKit.hbox(10)
	for st in stats:
		sh.add_child(CareerKit.stat(String(st[0]), String(st[1]), "", st[2] if st.size() > 2 else Color.WHITE, 30))
	v.add_child(sh)
	if not objective_rows.is_empty():
		v.add_child(CareerKit.caption("Objectives", CareerKit.C_MUTED))
	for r in objective_rows:
		var oh := UiKit.hbox(12)
		var done := bool(r["done"])
		var failed := bool(r["failed"])
		var col := CareerKit.C_UP if done else (UiKit.C_WARN if failed else Color.WHITE)
		var ic := LineIcon.make("check" if done else ("close" if failed else "target"), 26, col if done or failed else CareerKit.C_FAINT)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		oh.add_child(ic)
		var ov := UiKit.vbox(0)
		ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ov.add_child(CareerKit.text(String(r["label"]), 20, col, "", true))
		if String(r["text"]) != "":
			ov.add_child(CareerKit.text(String(r["text"]), 17, CareerKit.C_MUTED))
		oh.add_child(ov)
		oh.add_child(CareerKit.text("+" + CareerKit.money_short(int(r["bonus"])), 20, CareerKit.C_UP if done else CareerKit.C_MUTED, "num"))
		v.add_child(oh)
	var sk := CareerKit.striped(CareerKit.C_CARD, brand, 18, 20.0)
	return CareerKit.card(v, sk)


static func _offer_rows(s: Dictionary) -> Array:
	var rows: Array = []
	for o in s["objectives"]:
		rows.append({"label": String(o["label"]), "bonus": int(o["bonus"]), "text": "", "done": false, "failed": false})
	return rows


static func open_sponsor_review(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = CareerKit.page(menu, "Sponsors", "Season %d" % c.season_number(), CareerKit.C_MAJOR)
	var body: VBoxContainer = pg["body"]
	var sid := c.season_id()
	var offers: Array = SponsorManager.ensure_offers(c.data, sid, c.world_rank(), c.career_seed())
	var k := SponsorManager.contract_for(c.data, sid)
	var iv := UiKit.vbox(8)
	var ih := UiKit.hbox(10)
	ih.add_child(CareerKit.stat("World rank", "#%d" % c.world_rank(), "", Color.WHITE, 34))
	ih.add_child(CareerKit.stat("Balance", CareerKit.money_short(int((c.data["economy"] as Dictionary)["balance"])), "", CareerKit.C_UP, 34))
	ih.add_child(CareerKit.stat("Status", "Signed" if not k.is_empty() else "%d offers" % offers.size(), "", CareerKit.C_MAJOR, 34))
	iv.add_child(ih)
	iv.add_child(CareerKit.text("One primary sponsor per season. Objectives pay a bonus; missing them costs nothing but the sponsor's patience.", 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(iv, CareerKit.glass(Color(0.30, 0.24, 0.10, 0.92), Color(0.07, 0.07, 0.10, 0.96), 22.0, 22.0)))
	if not k.is_empty():
		var s := SponsorManager.by_id(String(k["sponsor_id"]))
		body.add_child(CareerKit.section("Your contract", "settled" if String(k["status"]) == "settled" else "active"))
		body.add_child(_sponsor_card(s, [["Fee / event", CareerKit.money_short(int(s["appearance_fee"]))], ["Events", str(int(k["events"]))],
			["Earned", CareerKit.money_short(int(k["fees"]) + int(k["bonuses"])), CareerKit.C_UP]], SponsorManager.objective_rows(k), true))
	else:
		if offers.is_empty():
			body.add_child(CareerKit.info_card("No offers yet", ["No sponsor wants to talk yet. Climb the world ranking to attract better offers."]))
		else:
			body.add_child(CareerKit.section("Offers on the table", "pick one"))
		for id in offers:
			var s := SponsorManager.by_id(String(id))
			var ov := UiKit.vbox(10)
			ov.add_child(_sponsor_card(s, [["Signing", CareerKit.money_short(int(s["signing_bonus"])), CareerKit.C_UP], ["Fee / event", CareerKit.money_short(int(s["appearance_fee"]))]],
				_offer_rows(s), false))
			var sid_c := String(id)
			ov.add_child(CareerKit.ghost("Sign with %s" % String(s["name"]), func() -> void:
				var r := SponsorManager.sign(c.data, sid_c, sid, c.season_number())
				if bool(r["ok"]) and not c.store.commit(c.data):
					CareerPages._present_save_error(menu, c.store, Callable())
				CareerPages._replace(menu, func() -> void: open_sponsor_review(menu)), "sponsor_sign_%s" % sid_c, CareerKit.C_LIME))
			body.add_child(ov)
	var pat: Dictionary = c.data["sponsorships"]["patience"]
	var cool: Array = []
	for s in SponsorManager.all():
		if int(pat.get(String(s["id"]), 0)) >= SponsorManager.PATIENCE_MAX:
			cool.append(String(s["name"]))
	if not cool.is_empty():
		body.add_child(CareerKit.text("Not offering this season after missed seasons: %s." % ", ".join(cool), 18, UiKit.C_WARN, "", true))
	body.add_child(CareerKit.text("Regional sponsors need world rank %d or better, global sponsors %d or better." % [
		int(_tier_rank("regional")), int(_tier_rank("global"))], 18, CareerKit.C_MUTED, "", true))
	c.store.commit(c.data)  # persists the generated offers (deterministic anyway)
	menu._push(pg["root"])


static func _tier_rank(tier: String) -> int:
	for s in SponsorManager.all():
		if String(s["tier"]) == tier:
			return int(s["unlock_rank"])
	return 0
