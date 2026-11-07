class_name WorldTextures
extends RefCounted
## Procedural textures generated in code at runtime (no external/copyrighted assets).
## One shared tileable RGBA noise texture drives turf, grass blades, foliage, bark and water:
##   R, G: smooth fBm (~16 px features, independent seeds)
##   B:    finer fBm (~6 px features)
##   A:    cellular clumps (~12 px cells)
## Shaders sample it at several world-space scales; mipmaps keep distant detail from shimmering.

const SIZE := 256

static var _noise_tex: ImageTexture
static var _noise_img: Image


static func noise_texture() -> ImageTexture:
	if _noise_tex == null:
		_noise_tex = ImageTexture.create_from_image(noise_image())
	return _noise_tex


## CPU copy (no mipmaps used) so gameplay-side visuals (grass tufts) can reproduce shader lookups.
static func noise_image() -> Image:
	if _noise_img != null:
		return _noise_img
	var chans: Array[PackedByteArray] = []
	var specs := [
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 16.0, 3, 101],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 16.0, 3, 202],
		[FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 1.0 / 6.0, 3, 303],
		[FastNoiseLite.TYPE_CELLULAR, 1.0 / 12.0, 1, 404],
	]
	for s in specs:
		var n := FastNoiseLite.new()
		n.noise_type = s[0]
		n.frequency = s[1]
		n.seed = s[3]
		if int(s[2]) > 1:
			n.fractal_type = FastNoiseLite.FRACTAL_FBM
			n.fractal_octaves = s[2]
		else:
			n.fractal_type = FastNoiseLite.FRACTAL_NONE
		if s[0] == FastNoiseLite.TYPE_CELLULAR:
			n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
		var img := n.get_seamless_image(SIZE, SIZE, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var data := PackedByteArray()
	data.resize(SIZE * SIZE * 4)
	var r := chans[0]
	var g := chans[1]
	var b := chans[2]
	var a := chans[3]
	var k := 0
	for i in SIZE * SIZE:
		data[k] = r[i]
		data[k + 1] = g[i]
		data[k + 2] = b[i]
		data[k + 3] = a[i]
		k += 4
	_noise_img = Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGBA8, data)
	_noise_img.generate_mipmaps()
	return _noise_img


## Bilinear, wrapping sample of the noise image (mip 0) at uv (tiles every 1.0) — matches the
## shader's texture(noise_tex, uv) up close.
static func sample(uv: Vector2) -> Color:
	var img := noise_image()
	var x := uv.x * SIZE - 0.5
	var y := uv.y * SIZE - 0.5
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var c00 := img.get_pixel(posmod(x0, SIZE), posmod(y0, SIZE))
	var c10 := img.get_pixel(posmod(x0 + 1, SIZE), posmod(y0, SIZE))
	var c01 := img.get_pixel(posmod(x0, SIZE), posmod(y0 + 1, SIZE))
	var c11 := img.get_pixel(posmod(x0 + 1, SIZE), posmod(y0 + 1, SIZE))
	return c00.lerp(c10, fx).lerp(c01.lerp(c11, fx), fy)
