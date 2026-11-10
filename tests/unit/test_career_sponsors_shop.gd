extends TestCase
## Career sponsors and shop: deterministic offers, objective progress applied once per event, signing bonus once,
## shop purchases atomic / idempotent / never negative, ensure_defaults on a v2 save, ledger consistency.


func _dir() -> String:
	return "user://test_career_sps_%d" % (randi() % 1000000)


func _cleanup(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _career(dir: String) -> CareerManager:
	var c := CareerManager.new(CareerSaveManager.new(dir))
	CareerManager.course_source = Callable()
	CareerManager.sim = CareerSim
	assert(c.create("Test Golfer", "England", "short", 777))
	return c


func _ledger_sum(c: CareerManager) -> int:
	var s := 0
	for t in c.data["ledger"]:
		s += int(t["amount"])
	return s


func _fake_event(id: String) -> Dictionary:
	return {"id": id, "name": id}


func _result(place: int, field: int = 72, missed: bool = false, won: bool = false, rank: int = 170) -> Dictionary:
	return {"human_played": true, "human_place": place, "field": field, "human_missed_cut": missed, "human_won": won, "world_rank_after": rank}


func _sign_first(c: CareerManager, force_id: String = "") -> String:
	var offers := SponsorManager.ensure_offers(c.data, c.season_id(), c.world_rank(), c.career_seed())
	var id := force_id if force_id != "" else String(offers[0])
	if force_id != "" and not offers.has(force_id):
		offers.append(force_id)  # test setup only
	assert_true(bool(SponsorManager.sign(c.data, id, c.season_id(), 1)["ok"]))
	return id


# ------------------------------------------------------------------ data

func test_sponsor_data_is_fictional_tiered_and_valid() -> void:
	var all := SponsorManager.all()
	assert_eq(all.size(), 12)
	var tiers := {}
	var ids := {}
	for s in all:
		tiers[String(s["tier"])] = int(tiers.get(String(s["tier"]), 0)) + 1
		assert_false(ids.has(String(s["id"])), "unique id")
		ids[String(s["id"])] = true
		assert_false((s["objectives"] as Array).is_empty())
	assert_eq(tiers.size(), 3)
	for it in ShopManager.items():
		assert_false(it.has("effect") or it.has("gameplay"), "cosmetics carry no gameplay fields")


# ------------------------------------------------------------------ offers

func test_offers_deterministic_unlocked_and_stable() -> void:
	var dir := _dir()
	var c := _career(dir)
	var a := SponsorManager.ensure_offers(c.data, "season_1", 180, 777).duplicate()
	assert_eq(a.size(), SponsorManager.OFFERS_PER_SEASON)
	for id in a:
		assert_eq(String(SponsorManager.by_id(String(id))["tier"]), "local", "rank 180 only unlocks local sponsors")
	var d2 := {"sponsorships": {}, "cosmetics": {}}
	assert_eq(SponsorManager.ensure_offers(d2, "season_1", 180, 777), a, "same seed, same offers")
	# stored offers do not change when the rank later improves
	assert_eq(SponsorManager.ensure_offers(c.data, "season_1", 5, 777), a)
	var top := {"sponsorships": {}, "cosmetics": {}}
	var hi := SponsorManager.ensure_offers(top, "season_1", 5, 777)
	assert_eq(hi.size(), 3)
	var d3 := {"sponsorships": {}, "cosmetics": {}}
	assert_eq(SponsorManager.ensure_offers(d3, "season_2", 180, 777).size(), 3)
	_cleanup(dir)


# ------------------------------------------------------------------ signing and progress

func test_signing_bonus_paid_once_and_one_sponsor_per_season() -> void:
	var dir := _dir()
	var c := _career(dir)
	var offers := SponsorManager.ensure_offers(c.data, c.season_id(), c.world_rank(), c.career_seed())
	var id := String(offers[0])
	var bonus := int(SponsorManager.by_id(id)["signing_bonus"])
	assert_true(bool(SponsorManager.sign(c.data, id, c.season_id(), 1)["ok"]))
	assert_true(bool(SponsorManager.sign(c.data, id, c.season_id(), 1)["ok"]), "re-signing is a no-op")
	assert_false(bool(SponsorManager.sign(c.data, String(offers[1]), c.season_id(), 1)["ok"]), "one primary sponsor per season")
	assert_eq(int(c.data["economy"]["balance"]), bonus, "signing bonus paid exactly once")
	assert_eq(int(c.data["economy"]["balance"]), _ledger_sum(c))
	assert_false(bool(SponsorManager.sign(c.data, "aurelian_airways", "season_9", 9)["ok"]), "not offered = refused")
	_cleanup(dir)


func test_objective_progress_applied_once_per_event() -> void:
	var dir := _dir()
	var c := _career(dir)
	var id := _sign_first(c, "fernbank_hardware")  # cuts 3 (3000), top10 1 (5000), no_last (2000); fee 1000
	var s := SponsorManager.by_id(id)
	var bal0 := int(c.data["economy"]["balance"])
	var ev := _fake_event("s1_e01")
	for i in 3:  # the same event applied repeatedly (failed-save retry)
		SponsorManager.apply_event(c.data, ev, _result(5), "season_1", 1)
	var k := SponsorManager.contract_for(c.data, "season_1")
	assert_eq(int(k["events"]), 1, "event counted once")
	assert_eq(int(k["progress"]["cuts"]["value"]), 1)
	assert_true(bool(k["progress"]["top10"]["done"]))
	# fee + top10 bonus, nothing twice
	assert_eq(int(c.data["economy"]["balance"]) - bal0, int(s["appearance_fee"]) + 5000)
	SponsorManager.apply_event(c.data, _fake_event("s1_e02"), _result(20), "season_1", 1)
	SponsorManager.apply_event(c.data, _fake_event("s1_e03"), _result(30), "season_1", 1)
	k = SponsorManager.contract_for(c.data, "season_1")
	assert_true(bool(k["progress"]["cuts"]["done"]), "3 cuts made")
	assert_eq(int(c.data["economy"]["balance"]) - bal0, 3 * int(s["appearance_fee"]) + 5000 + 3000)
	# a missed cut: fee still paid, no cut credited
	SponsorManager.apply_event(c.data, _fake_event("s1_e04"), _result(70, 72, true), "season_1", 1)
	assert_eq(int(k["progress"]["cuts"]["value"]), 3)
	# settle pays "never finish last" once
	var before := int(c.data["economy"]["balance"])
	SponsorManager.settle(c.data, "season_1")
	SponsorManager.settle(c.data, "season_1")
	assert_eq(int(c.data["economy"]["balance"]) - before, 2000)
	assert_eq(int(c.data["economy"]["balance"]), _ledger_sum(c), "ledger sums to the balance")
	var seen := {}
	for t in c.data["ledger"]:
		assert_false(seen.has(String(t["id"])), "ledger ids are unique")
		seen[String(t["id"])] = true
	_cleanup(dir)


func test_last_place_fails_objective_and_missed_season_costs_patience() -> void:
	var dir := _dir()
	var c := _career(dir)
	_sign_first(c, "fernbank_hardware")
	SponsorManager.apply_event(c.data, _fake_event("s1_e01"), _result(72, 72, true), "season_1", 1)
	SponsorManager.settle(c.data, "season_1")
	var k := SponsorManager.contract_for(c.data, "season_1")
	assert_true(bool(k["progress"]["no_last"]["failed"]))
	assert_eq(int(c.data["sponsorships"]["patience"]["fernbank_hardware"]), 1, "missed season: patience +1")
	assert_eq(String(k["status"]), "settled")
	_cleanup(dir)


func test_win_and_rank_objectives() -> void:
	var dir := _dir()
	var c := _career(dir)
	_sign_first(c, "halcyon_greens")  # win 1 (15000), cuts 3
	var b := int(c.data["economy"]["balance"])
	SponsorManager.apply_event(c.data, _fake_event("s1_e01"), _result(1, 72, false, true), "season_1", 1)
	assert_eq(int(c.data["economy"]["balance"]) - b, 1000 + 15000)
	SponsorManager.apply_event(c.data, _fake_event("s1_e01"), _result(1, 72, false, true), "season_1", 1)
	assert_eq(int(c.data["economy"]["balance"]) - b, 16000, "no double pay")
	var d := {"sponsorships": {}, "cosmetics": {}, "ledger": [], "economy": {"balance": 0, "season_earnings": 0, "career_earnings": 0}}
	d["sponsorships"] = {"contracts": {}, "offers": {"season_1": ["gullwing_cafe"]}, "patience": {}, "history": [], "applied": {}}
	SponsorManager.sign(d, "gullwing_cafe", "season_1", 1)
	SponsorManager.apply_event(d, _fake_event("e1"), _result(10, 72, false, false, 140), "season_1", 1)
	assert_true(bool(d["sponsorships"]["contracts"]["season_1"]["progress"]["rank"]["done"]), "reached rank 150")
	_cleanup(dir)


func test_skipped_event_pays_nothing_and_missing_contract_is_safe() -> void:
	var dir := _dir()
	var c := _career(dir)
	SponsorManager.apply_event(c.data, _fake_event("s1_e01"), _result(3), "season_1", 1)  # no contract
	assert_eq(int(c.data["economy"]["balance"]), 0)
	_sign_first(c, "fernbank_hardware")
	var b := int(c.data["economy"]["balance"])
	SponsorManager.apply_event(c.data, _fake_event("s1_e02"), {"human_played": false}, "season_1", 1)
	assert_eq(int(c.data["economy"]["balance"]), b)
	_cleanup(dir)


func test_real_event_flow_hooks_sponsor_once() -> void:
	var dir := _dir()
	var c := _career(dir)
	var id := _sign_first(c)
	var b := int(c.data["economy"]["balance"])
	var e := c.next_event()
	assert_true(c.enter_event(int(e["serial"])))
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	var holes: int = ((t["snapshot"] as Dictionary)["holes"] as Array).size()
	while String(c.tournament()["status"]) != "complete":
		c.begin_round({}, 0)
		c.complete_round(par, par, holes)
	var res := c.finalize_tournament()
	assert_true(bool(res["human_played"]))
	var fee := int(SponsorManager.by_id(id)["appearance_fee"])
	var paid := 0
	for tr in c.data["ledger"]:
		if String(tr["id"]) == "sponsor_fee:%s" % String(e["id"]):
			paid += int(tr["amount"])
	assert_eq(paid, fee, "appearance fee in the ledger once")
	assert_true(int(c.data["economy"]["balance"]) >= b + fee)
	assert_eq(int(c.data["economy"]["balance"]), _ledger_sum(c))
	# survives a save / load round trip
	var r := CareerSaveManager.new(dir).load_career()
	assert_true(bool(r.ok))
	assert_eq(int((r.data["sponsorships"]["contracts"]["season_1"] as Dictionary)["events"]), 1)
	_cleanup(dir)


# ------------------------------------------------------------------ shop

func _fund(c: CareerManager, amount: int) -> void:
	CareerRecords.ledger_add(c.data, "test_fund_%d" % amount, "test", "fund", amount, "", 1)


func test_purchase_atomic_idempotent_never_negative() -> void:
	var dir := _dir()
	var c := _career(dir)
	var item := ShopManager.item("ball_lime")
	var price := int(item["price"])
	var r := ShopManager.buy(c.data, "ball_lime", 1)
	assert_false(bool(r["ok"]), "no money, no purchase")
	assert_false(ShopManager.is_owned(c.data, "ball_lime"))
	assert_eq(int(c.data["economy"]["balance"]), 0)
	assert_eq((c.data["ledger"] as Array).size(), 0, "a refused purchase leaves no trace")
	_fund(c, price + 100)
	assert_true(bool(ShopManager.buy(c.data, "ball_lime", 1)["ok"]))
	assert_eq(int(c.data["economy"]["balance"]), 100)
	assert_false(bool(ShopManager.buy(c.data, "ball_lime", 1)["ok"]), "second buy refused")
	assert_eq(int(c.data["economy"]["balance"]), 100, "no second charge")
	# interrupted purchase: charged in the ledger but not owned yet (failed-save retry) -> completed without charging again
	_fund(c, 50000)
	var cid := "flag_red"
	var p2 := int(ShopManager.item(cid)["price"])
	CareerRecords.ledger_add(c.data, "shop:%s" % cid, "shop", "x", -p2, "", 1)
	var bal := int(c.data["economy"]["balance"])
	assert_true(bool(ShopManager.buy(c.data, cid, 1)["ok"]))
	assert_eq(int(c.data["economy"]["balance"]), bal, "retry does not charge twice")
	assert_true(ShopManager.is_owned(c.data, cid))
	assert_eq(int(c.data["economy"]["balance"]), _ledger_sum(c))
	# spending everything is allowed, going below is not
	var left := int(c.data["economy"]["balance"])
	CareerRecords.ledger_add(c.data, "test_drain", "test", "drain", -(left - 1000), "", 1)
	assert_false(bool(ShopManager.buy(c.data, "ball_gold", 1)["ok"]))
	assert_true(int(c.data["economy"]["balance"]) >= 0)
	_cleanup(dir)


func test_locks_equip_and_new_badge() -> void:
	var dir := _dir()
	var c := _career(dir)
	_fund(c, 200000)
	assert_false(bool(ShopManager.buy(c.data, "trail_aurelian", 1)["ok"]), "sponsor-locked")
	assert_false(bool(ShopManager.buy(c.data, "flag_tour_gold", 1)["ok"]), "rank-locked")
	assert_false(bool(ShopManager.buy(c.data, "ball_midnight", 1)["ok"]), "trophy-locked")
	c.data["records"]["best_world_rank"] = 90
	assert_true(bool(ShopManager.buy(c.data, "flag_tour_gold", 1)["ok"]))
	CareerRecords.trophy_add(c.data, "win:x", "event_win", "X", 1, "x")
	assert_true(bool(ShopManager.buy(c.data, "ball_midnight", 1)["ok"]))
	assert_eq(ShopManager.new_count(c.data), 2, "bought items are NEW until seen")
	ShopManager.mark_all_seen(c.data)
	assert_eq(ShopManager.new_count(c.data), 0)
	assert_false(ShopManager.equip(c.data, "ball_lime"), "cannot equip what you do not own")
	assert_true(ShopManager.equip(c.data, "ball_midnight"))
	assert_eq(ShopManager.equipped_color(c.data, "ball_color").to_html(false), "2b2f66")
	assert_eq(ShopManager.equipped_color(c.data, "ball_trail"), Color.TRANSPARENT)
	ShopManager.unequip(c.data, "ball_color")
	assert_eq(ShopManager.equipped_id(c.data, "ball_color"), "")
	# persistence
	ShopManager.equip(c.data, "flag_tour_gold")
	assert_true(c.store.commit(c.data))
	var r := CareerSaveManager.new(dir).load_career()
	assert_true(ShopManager.is_owned(r.data, "flag_tour_gold"))
	assert_eq(ShopManager.equipped_id(r.data, "flag"), "flag_tour_gold")
	_cleanup(dir)


func test_sponsor_lock_opens_after_signing() -> void:
	var dir := _dir()
	var c := _career(dir)
	_fund(c, 100000)
	_sign_first(c, "copperleaf_insurance")
	assert_true(bool(ShopManager.buy(c.data, "outfit_copperleaf", 1)["ok"]))
	_cleanup(dir)


# ------------------------------------------------------------------ defaults

func test_ensure_defaults_on_v2_save() -> void:
	var dir := _dir()
	var c := _career(dir)
	# a v2 save written before this feature: placeholders only
	c.data["sponsorships"] = {}
	c.data["cosmetics"] = {}
	assert_true(c.store.commit(c.data))
	var c2 := CareerManager.new(CareerSaveManager.new(dir))
	assert_true(bool(c2.load_saved().ok))
	assert_eq(int(c2.data["schema_version"]), CareerConfig.SCHEMA_VERSION, "schema version unchanged")
	for k in ["contracts", "offers", "patience", "applied"]:
		assert_true(c2.data["sponsorships"].has(k))
	assert_true(c2.data["cosmetics"].has("owned") and c2.data["cosmetics"].has("equipped"))
	var before := JSON.stringify(c2.data)
	CareerDefaultsSponsorsShop.ensure_defaults(c2.data)
	assert_eq(JSON.stringify(c2.data), before, "idempotent")
	# existing content is preserved
	c2.data["cosmetics"]["owned"]["x"] = {"season": 1, "seen": true}
	CareerDefaultsSponsorsShop.ensure_defaults(c2.data)
	assert_true(c2.data["cosmetics"]["owned"].has("x"))
	_cleanup(dir)
