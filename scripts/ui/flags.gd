class_name Flags
extends RefCounted
## Small procedurally drawn national flags (60x40) for UI icons. Simplified designs, no external art.

const W := 60
const H := 40
static var _cache: Dictionary = {}


static func texture(code: String) -> Texture2D:
	if _cache.has(code):
		return _cache[code]
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.6, 0.58))
	match code:
		"ENG":
			img.fill(Color.WHITE)
			_rect(img, 0, 16, W, 8, Color(0.8, 0.07, 0.15))
			_rect(img, 26, 0, 8, H, Color(0.8, 0.07, 0.15))
		"SCO":
			img.fill(Color(0.0, 0.37, 0.72))
			_saltire(img, Color.WHITE, 5.0)
		"WAL":
			_rect(img, 0, 0, W, 20, Color.WHITE)
			_rect(img, 0, 20, W, 20, Color(0.0, 0.6, 0.25))
			_ellipse(img, 30, 20, 13, 9, Color(0.83, 0.07, 0.17))
		"NIR":
			img.fill(Color.WHITE)
			_rect(img, 0, 16, W, 8, Color(0.8, 0.07, 0.15))
			_rect(img, 26, 0, 8, H, Color(0.8, 0.07, 0.15))
			_ellipse(img, 30, 20, 5, 5, Color.WHITE)
			_ellipse(img, 30, 20, 3, 3, Color(0.8, 0.07, 0.15))
		"IRL":
			_vstripes(img, [Color(0.09, 0.61, 0.38), Color.WHITE, Color(1.0, 0.53, 0.24)])
		"ESP":
			_rect(img, 0, 0, W, 10, Color(0.67, 0.08, 0.11))
			_rect(img, 0, 10, W, 20, Color(0.95, 0.75, 0.0))
			_rect(img, 0, 30, W, 10, Color(0.67, 0.08, 0.11))
		"GER":
			_hstripes(img, [Color(0.05, 0.05, 0.05), Color(0.87, 0.0, 0.0), Color(1.0, 0.81, 0.0)])
		"FRA":
			_vstripes(img, [Color(0.0, 0.14, 0.58), Color.WHITE, Color(0.93, 0.16, 0.22)])
		"ITA":
			_vstripes(img, [Color(0.0, 0.57, 0.27), Color.WHITE, Color(0.81, 0.17, 0.22)])
		"NED":
			_hstripes(img, [Color(0.68, 0.11, 0.16), Color.WHITE, Color(0.13, 0.27, 0.55)])
		"POR":
			_rect(img, 0, 0, 24, H, Color(0.0, 0.4, 0.0))
			_rect(img, 24, 0, W - 24, H, Color(1.0, 0.0, 0.0))
			_ellipse(img, 24, 20, 8, 8, Color(1.0, 0.85, 0.0))
		"BEL":
			_vstripes(img, [Color(0.05, 0.05, 0.05), Color(0.99, 0.85, 0.15), Color(0.94, 0.2, 0.25)])
		"BRA":
			img.fill(Color(0.0, 0.61, 0.23))
			_diamond(img, Color(1.0, 0.87, 0.0))
			_ellipse(img, 30, 20, 9, 9, Color(0.0, 0.15, 0.46))
		"ARG":
			_hstripes(img, [Color(0.46, 0.67, 0.86), Color.WHITE, Color(0.46, 0.67, 0.86)])
			_ellipse(img, 30, 20, 4, 4, Color(0.96, 0.71, 0.05))
	_border(img, Color(0, 0, 0, 0.35))
	var tex := ImageTexture.create_from_image(img)
	_cache[code] = tex
	return tex


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


static func _hstripes(img: Image, cols: Array) -> void:
	var n := cols.size()
	for i in n:
		var y0 := int(H * i / float(n))
		var y1 := int(H * (i + 1) / float(n))
		_rect(img, 0, y0, W, y1 - y0, cols[i])


static func _vstripes(img: Image, cols: Array) -> void:
	var n := cols.size()
	for i in n:
		var x0 := int(W * i / float(n))
		var x1 := int(W * (i + 1) / float(n))
		_rect(img, x0, 0, x1 - x0, H, cols[i])


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


static func _saltire(img: Image, c: Color, half_w: float) -> void:
	var k := float(H) / float(W)
	for y in H:
		for x in W:
			var d1 := absf(y + 0.5 - (x + 0.5) * k)
			var d2 := absf(y + 0.5 - (H - (x + 0.5) * k))
			if d1 < half_w * 0.75 or d2 < half_w * 0.75:
				img.set_pixel(x, y, c)


static func _diamond(img: Image, c: Color) -> void:
	for y in H:
		for x in W:
			var dx := absf(x + 0.5 - W * 0.5) / (W * 0.44)
			var dy := absf(y + 0.5 - H * 0.5) / (H * 0.40)
			if dx + dy <= 1.0:
				img.set_pixel(x, y, c)


static func _border(img: Image, c: Color) -> void:
	for x in W:
		img.set_pixel(x, 0, img.get_pixel(x, 0).blend(c))
		img.set_pixel(x, H - 1, img.get_pixel(x, H - 1).blend(c))
	for y in H:
		img.set_pixel(0, y, img.get_pixel(0, y).blend(c))
		img.set_pixel(W - 1, y, img.get_pixel(W - 1, y).blend(c))
