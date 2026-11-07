class_name Footballer
extends RefCounted
## Editable test identity + stat record. Usage/consumption is match state (FootballerPool),
## never stored here.

var id := ""
var name := ""
var country_code := ""
var nationality := ""
var caps := 0
var goals := 0
var birth_year := 0
var career_years := ""
var notes := ""


static func from_dict(d: Dictionary) -> Footballer:
	var f := Footballer.new()
	f.id = String(d.get("id", ""))
	f.name = String(d.get("name", ""))
	f.country_code = String(d.get("country_code", ""))
	f.nationality = String(d.get("nationality", f.country_code))
	f.caps = int(d.get("senior_international_caps", 0))
	f.goals = int(d.get("senior_international_goals", 0))
	f.birth_year = int(d.get("birth_year", 0)) if d.get("birth_year") != null else 0
	f.career_years = String(d.get("career_years", "")) if d.get("career_years") != null else ""
	f.notes = String(d.get("notes", "")) if d.get("notes") != null else ""
	return f


func to_dict() -> Dictionary:
	var d := {
		"id": id,
		"name": name,
		"country_code": country_code,
		"nationality": nationality,
		"senior_international_caps": caps,
		"senior_international_goals": goals,
	}
	if birth_year > 0:
		d["birth_year"] = birth_year
	if career_years != "":
		d["career_years"] = career_years
	if notes != "":
		d["notes"] = notes
	return d


func copy() -> Footballer:
	return Footballer.from_dict(to_dict())


## Normal-play label: name + nationality (+ years for disambiguation). Never stats.
func display_label() -> String:
	var extra := ""
	if birth_year > 0:
		extra = " · b. %d" % birth_year
	elif career_years != "":
		extra = " · %s" % career_years
	return "%s (%s)%s" % [name, nationality, extra]


## Validate a raw dictionary (e.g. from JSON or the editor). Returns "" when valid.
static func validate_dict(d: Dictionary) -> String:
	var id_v = d.get("id")
	if typeof(id_v) != TYPE_STRING or String(id_v).strip_edges() == "":
		return "id must be a non-empty string"
	var nm = d.get("name")
	if typeof(nm) != TYPE_STRING or String(nm).strip_edges() == "":
		return "name must be a non-empty string"
	for key in ["senior_international_caps", "senior_international_goals"]:
		var err := validate_stat(d.get(key))
		if err != "":
			return "%s: %s" % [key, err]
	return ""


## Stats must be non-negative integers. Accepts int, integral float, or a digit-only string.
static func validate_stat(v) -> String:
	match typeof(v):
		TYPE_INT:
			return "" if int(v) >= 0 else "must be non-negative"
		TYPE_FLOAT:
			var fv := float(v)
			if is_nan(fv) or is_inf(fv):
				return "must be a finite number"
			if fv < 0.0:
				return "must be non-negative"
			if fv != floor(fv):
				return "must be a whole number"
			return ""
		TYPE_STRING:
			var s := String(v).strip_edges()
			if s == "" or not s.is_valid_int():
				return "must be a whole number"
			return "" if s.to_int() >= 0 else "must be non-negative"
		_:
			return "must be a whole number"


static func parse_stat(v) -> int:
	if typeof(v) == TYPE_STRING:
		return String(v).strip_edges().to_int()
	return int(v)
