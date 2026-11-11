class_name CareerShopPages
extends RefCounted
## Career Shop screen (cosmetics only). Presentation only: rules live in ShopManager. Entry point `open_shop(menu)`
## is used by the Hub tile, the Me tab and the off-season flow (off_season_hook_shop).
## Equipped ball colour and flag colour are applied in career rounds (RoundController / CourseView, visuals only);
## the other slots are stored and shown in the preview card.

const SLOT_ORDER := ["ball_color", "ball_trail", "flag", "outfit", "scorecard", "celebration"]


static func hub_subtitle(c: CareerManager) -> String:
	var n := ShopManager.new_count(c.data)
	return "%s%s" % [CareerPages.money(int((c.data["economy"] as Dictionary)["balance"])), ("  ·  %d new" % n) if n > 0 else ""]


static func _swatch(color: Color, d: float = 44.0) -> Control:
	var p := PanelContainer.new()
	var has := color.a > 0.0
	p.add_theme_stylebox_override("panel", CareerKit.flat(color if has else Color(1, 1, 1, 0.08), int(d * 0.5), 0.0, Color(1, 1, 1, 0.45 if has else 0.2), 2))
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func _preview_card(c: CareerManager) -> Control:
	var v := UiKit.vbox(10)
	v.add_child(CareerKit.section("Equipped", "cosmetics only"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 10)
	var slots := ShopManager.slots()
	for slot in SLOT_ORDER:
		var id := ShopManager.equipped_id(c.data, slot)
		var it := ShopManager.item(id)
		var h := UiKit.hbox(10)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(_swatch(ShopManager.equipped_color(c.data, slot), 36))
		var tv := UiKit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(CareerKit.text(String(slots.get(slot, slot)).to_upper(), 14, CareerKit.C_MUTED, "caps"))
		tv.add_child(CareerKit.trim(CareerKit.text(String(it["name"]) if not it.is_empty() else "Default", 19, Color.WHITE, "semi")))
		h.add_child(tv)
		g.add_child(h)
	v.add_child(g)
	v.add_child(CareerKit.text("They never change how a shot plays or scores.", 17, CareerKit.C_MUTED, "", true))
	return CareerKit.card(v)


static func _item_row(menu: MainMenu, c: CareerManager, it: Dictionary, new_ids: Dictionary, refresh: Callable) -> Control:
	var id := String(it["id"])
	var owned := ShopManager.is_owned(c.data, id)
	var eq := ShopManager.equipped_id(c.data, String(it["slot"])) == id
	var lock := ShopManager.lock_state(c.data, it)
	var v := UiKit.vbox(10)
	var h := UiKit.hbox(14)
	h.add_child(_swatch(Color(String(it["color"])) if it.has("color") else Color.TRANSPARENT, 52))
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(CareerKit.trim(CareerKit.text(String(it["name"]), 24, Color.WHITE, "semi")))
	if not owned and not bool(lock["ok"]):
		tv.add_child(CareerKit.text("Locked: %s" % String(lock["label"]), 17, UiKit.C_WARN, "", true))
	else:
		tv.add_child(CareerKit.text(String(ShopManager.slots().get(String(it["slot"]), "")) if not owned else "In your locker", 17, CareerKit.C_MUTED))
	h.add_child(tv)
	if new_ids.has(id):
		h.add_child(CareerKit.chip("New", CareerKit.C_UP, true))
	if owned or not bool(lock["ok"]):
		h.add_child(CareerKit.chip("Equipped" if eq else ("Owned" if owned else "Locked"), CareerKit.C_LIME if eq else (CareerKit.C_UP if owned else UiKit.C_WARN)))
	v.add_child(h)
	var status := CareerKit.text("", 18, UiKit.C_WARN, "", true)
	if owned:
		v.add_child(CareerKit.ghost("Unequip" if eq else "Equip", func() -> void:
			if eq:
				ShopManager.unequip(c.data, String(it["slot"]))
			else:
				ShopManager.equip(c.data, id)
			if not c.store.commit(c.data):
				CareerPages._present_save_error(menu, c.store, Callable())
			refresh.call(), "shop_equip_%s" % id, Color.WHITE if eq else CareerKit.C_LIME))
	elif bool(lock["ok"]):
		var why := ShopManager.why_not(c.data, id)
		var b := CareerKit.ghost("Buy for %s" % CareerPages.money(int(it["price"])), func() -> void:
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
				status.visible = true, "shop_buy_%s" % id, CareerKit.C_LIME)
		b.disabled = why != ""
		v.add_child(b)
		if why != "":
			status.text = why
	status.visible = status.text != ""
	v.add_child(status)
	return CareerKit.card(v, CareerKit.striped(CareerKit.C_CARD, CareerKit.C_LIME) if eq else null)


static func open_shop(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = CareerKit.page(menu, "Shop", "Cosmetics", CareerKit.C_FLAGSHIP)
	var body: VBoxContainer = pg["body"]
	var new_ids := {}  # NEW badges shown on this visit; the items count as seen once the page has been opened
	for id in c.data["cosmetics"]["owned"]:
		if not bool((c.data["cosmetics"]["owned"][id] as Dictionary).get("seen", true)):
			new_ids[String(id)] = true
	if not new_ids.is_empty():
		ShopManager.mark_all_seen(c.data)
		c.store.commit(c.data)
	var money_label := CareerKit.text("", 44, Color.WHITE, "display")
	var state := {"slot": 0}
	var preview_box := UiKit.vbox(0)
	var list := UiKit.vbox(12)
	var fn := {}
	fn["refresh"] = func() -> void:
		money_label.text = CareerPages.money(int((c.data["economy"] as Dictionary)["balance"]))
		UiKit.clear(preview_box)
		preview_box.add_child(_preview_card(c))
		UiKit.clear(list)
		for it in ShopManager.items_in_slot(String(SLOT_ORDER[int(state["slot"])])):
			list.add_child(_item_row(menu, c, it, new_ids, fn["refresh"]))
	var labels: Array = []
	for s in SLOT_ORDER:
		labels.append(String(ShopManager.slots().get(s, s)))
	var bv := UiKit.vbox(0)
	bv.add_child(CareerKit.caption("Balance", CareerKit.C_MUTED))
	bv.add_child(money_label)
	body.add_child(CareerKit.card(bv, CareerKit.glass(Color(0.26, 0.17, 0.42, 0.92), Color(0.07, 0.06, 0.14, 0.96), 22.0, 22.0)))
	body.add_child(preview_box)
	body.add_child(CareerPages._choice_buttons(labels, 0, func(i: int) -> void:
		state["slot"] = i
		(fn["refresh"] as Callable).call(), "shop_slot"))
	body.add_child(list)
	(fn["refresh"] as Callable).call()
	menu._push(pg["root"])
