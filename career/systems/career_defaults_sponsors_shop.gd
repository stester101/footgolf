class_name CareerDefaultsSponsorsShop
extends RefCounted
## Fills the sponsor / shop fields of a career save (idempotent; schema_version is NOT bumped: v2 saves written
## before this feature just get the empty structures). Called from CareerManager.load_saved().
## sponsorships {contracts:{season_id:{...}}, offers:{season_id:[sponsor ids]}, patience:{sponsor_id:int}, history:[sponsor ids signed], applied:{event_id:true}}
## cosmetics    {owned:{item_id:{season:int, seen:bool}}, equipped:{slot:item_id}}


static func ensure_defaults(data: Dictionary) -> void:
	var sp = data.get("sponsorships")
	if typeof(sp) != TYPE_DICTIONARY:
		sp = {}
	for k in ["contracts", "offers", "patience", "applied"]:
		if typeof(sp.get(k)) != TYPE_DICTIONARY:
			sp[k] = {}
	if typeof(sp.get("history")) != TYPE_ARRAY:
		sp["history"] = []
	data["sponsorships"] = sp
	var co = data.get("cosmetics")
	if typeof(co) != TYPE_DICTIONARY:
		co = {}
	for k in ["owned", "equipped"]:
		if typeof(co.get(k)) != TYPE_DICTIONARY:
			co[k] = {}
	data["cosmetics"] = co
