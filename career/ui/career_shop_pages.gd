class_name CareerShopPages
extends RefCounted
## Career Shop screen (cosmetics only). Presentation only: rules live in ShopManager. Entry point `open_shop(menu)`
## is used by the Hub row and can be called from the off-season flow (off_season_hook_shop).
## Equipped ball colour and flag colour are applied in career rounds (RoundController / CourseView, visuals only);
## the other slots are stored and shown in the preview card.

const SLOT_ORDER := ["ball_color", "ball_trail", "flag", "outfit", "scorecard", "celebration"]


static func hub_subtitle(c: CareerManager) -> String:
	var n := ShopManager.new_count(c.data)
	return "%s%s" % [CareerPages.money(int((c.data["economy"] as Dictionary)["balance"])), ("  ·  %d new" % n) if n > 0 else ""]


static func _swatch(color: Color, w: int = 18, h: int = 34) -> Control:
	var r := ColorRect.new()
	r.color = color if color.a > 0.0 else Color(1, 1, 1, 0.12)
	r.custom_minimum_size = Vector2(w, h)
	return r


static func _preview_card(c: CareerManager) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 20, 14))
	var v := UiKit.vbox(6)
	var t := UiKit.label("PREVIEW (EQUIPPED)", 20, UiKit.C_CYAN)
	t.add_theme_font_override("font", UiKit.font_caps())
	v.add_child(t)
	var slots := ShopManager.slots()
	for slot in SLOT_ORDER:
		var id := ShopManager.equipped_id(c.data, slot)
		var it := ShopManager.item(id)
		var h := UiKit.hbox(10)
		h.add_child(_swatch(ShopManager.equipped_color(c.data, slot)))
		var l := UiKit.label("%s: %s" % [String(slots.get(slot, slot)), String(it["name"]) if not it.is_empty() else "default"], 21, Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(l)
		v.add_child(h)
	v.add_child(UiKit.text("Cosmetics only: they never change how a shot plays or scores.", 18, UiKit.C_MUTED))
	p.add_child(v)
	return p


static func _item_row(menu: MainMenu, c: CareerManager, it: Dictionary, new_ids: Dictionary, refresh: Callable) -> Control:
	var id := String(it["id"])
	var owned := ShopManager.is_owned(c.data, id)
	var eq := ShopManager.equipped_id(c.data, String(it["slot"])) == id
	var lock := ShopManager.lock_state(c.data, it)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 16, 10))
	var v := UiKit.vbox(4)
	var h := UiKit.hbox(10)
	h.add_child(_swatch(Color(String(it["color"])) if it.has("color") else Color.TRANSPARENT))
	var name := UiKit.label(String(it["name"]), 24, Color.WHITE)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name)
	if new_ids.has(id):
		h.add_child(UiKit.label("NEW", 19, Color("#9BFF7A")))
	h.add_child(UiKit.label("EQUIPPED" if eq else ("OWNED" if owned else CareerPages.money(int(it["price"]))), 20,
		Color("#9BFF7A") if owned else UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	v.add_child(h)
	if not owned and not bool(lock["ok"]):
		v.add_child(UiKit.text("Locked: %s" % String(lock["label"]), 19, UiKit.C_WARN))
	var status := UiKit.label("", 19, UiKit.C_WARN)
	if owned:
		var b := menu._secondary_button("Unequip" if eq else "Equip", func() -> void:
			if eq:
				ShopManager.unequip(c.data, String(it["slot"]))
			else:
				ShopManager.equip(c.data, id)
			if not c.store.commit(c.data):
				CareerPages._present_save_error(menu, c.store, Callable())
			refresh.call(), "shop_equip_%s" % id)
		v.add_child(b)
	elif bool(lock["ok"]):
		var why := ShopManager.why_not(c.data, id)
		var b := menu._secondary_button("Buy for %s" % CareerPages.money(int(it["price"])), func() -> void:
			var r := ShopManager.buy(c.data, id, c.season_number())
			if bool(r["ok"]):
				ShopManager.equip(c.data, id)
				new_ids[id] = true
				ShopManager.mark_all_seen(c.data)
				if not c.store.commit(c.data):
					CareerPages._present_save_error(menu, c.store, Callable())
				refresh.call()
			else:
				status.text = String(r["reason"])
				status.visible = true, "shop_buy_%s" % id)
		b.disabled = why != ""
		v.add_child(b)
		if why != "":
			status.text = why
	status.visible = status.text != ""
	v.add_child(status)
	p.add_child(v)
	return p


static func open_shop(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = menu._page("Shop")
	var body: VBoxContainer = pg["body"]
	var new_ids := {}  # NEW badges shown on this visit; the items count as seen once the page has been opened
	for id in c.data["cosmetics"]["owned"]:
		if not bool((c.data["cosmetics"]["owned"][id] as Dictionary).get("seen", true)):
			new_ids[String(id)] = true
	if not new_ids.is_empty():
		ShopManager.mark_all_seen(c.data)
		c.store.commit(c.data)
	var money_label := UiKit.label("", 24, Color.WHITE)
	var state := {"slot": 0}
	var preview_box := UiKit.vbox(0)
	var list := UiKit.vbox(8)
	var refresh: Callable
	refresh = func() -> void:
		money_label.text = "Balance: %s" % CareerPages.money(int((c.data["economy"] as Dictionary)["balance"]))
		UiKit.clear(preview_box)
		preview_box.add_child(_preview_card(c))
		UiKit.clear(list)
		for it in ShopManager.items_in_slot(String(SLOT_ORDER[int(state["slot"])])):
			list.add_child(_item_row(menu, c, it, new_ids, refresh))
	var labels: Array = []
	for s in SLOT_ORDER:
		labels.append(String(ShopManager.slots().get(s, s)))
	body.add_child(money_label)
	body.add_child(preview_box)
	body.add_child(CareerPages._choice_buttons(labels, 0, func(i: int) -> void:
		state["slot"] = i
		refresh.call()))
	body.add_child(list)
	refresh.call()
	menu._push(pg["root"])
