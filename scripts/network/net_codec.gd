class_name NetCodec
extends RefCounted
## Data-only codec. Network input cannot instantiate scripts or set arbitrary objects.
static func encode(value: Variant) -> Variant:
	if value is Vector3:
		return {"$v3": [value.x, value.y, value.z]}
	if value is Array:
		var a: Array = []
		for x in value:
			a.append(encode(x))
		return a
	if value is Dictionary:
		var d := {}
		for k in value:
			d[str(k)] = encode(value[k])
		return d
	if value is Object:
		var kind := ""
		if value is ShotRequest: kind = "request"
		elif value is ShotResult: kind = "result"
		elif value is HoleState: kind = "hole"
		elif value is RoundState: kind = "round"
		assert(kind != "", "Unsupported network object")
		var fields := {}
		for p in value.get_property_list():
			if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				fields[p.name] = encode(value.get(p.name))
		return {"$type": kind, "fields": fields}
	return value

static func decode(value: Variant) -> Variant:
	if value is Array:
		var a: Array = []
		for x in value: a.append(decode(x))
		return a
	if value is Dictionary:
		if value.has("$v3"):
			var a: Array = value["$v3"]
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if value.has("$type"):
			var obj: RefCounted
			match value["$type"]:
				"request": obj = ShotRequest.new()
				"result": obj = ShotResult.new()
				"hole": obj = HoleState.new()
				"round": obj = RoundState.new()
				_: return null
			var fields: Dictionary = value.get("fields", {})
			for p in obj.get_property_list():
				if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and fields.has(p.name):
					var v = decode(fields[p.name])
					if obj.get(p.name) is Array:
						(obj.get(p.name) as Array).assign(v)
					else:
						obj.set(p.name, v)
			return obj
		var d := {}
		for k in value: d[k] = decode(value[k])
		return d
	return value
