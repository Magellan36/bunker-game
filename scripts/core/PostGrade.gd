class_name PostGrade
extends RefCounted
## PostGrade.gd
## Procedural post-processing assets for the main WorldEnvironment (Sep 2026
## "tier 1" post pass): a subtle colour-grade 3D LUT
## (Environment.adjustment_color_correction) and a lens-dirt glow map
## (Environment.glow_map). Both are generated in code on first use and
## cached for the session, so there's no binary asset or import step to
## manage. The static Environment values (AgX tonemapper, SSAO retune,
## glow_map_strength, debanding) live in MainWorld.tscn / project.godot.
##
## Swapping in hand-authored art: drop a file at LUT_OVERRIDE_PATH (a PNG
## imported as Texture3D, e.g. a 32x32x32 horizontal-strip LUT graded in
## Photoshop/Resolve) or DIRT_OVERRIDE_PATH (any 16:9 texture) and it's used
## instead of the generated one — no code change.
##
## Pure static factory (same pattern as DustMotes.gd) — call
## PostGrade.apply(env) directly, no .new() needed.

const LUT_OVERRIDE_PATH: String = "res://assets/textures/post/grade_lut.png"
const DIRT_OVERRIDE_PATH: String = "res://assets/textures/post/lens_dirt.png"

## ── Colour grade ───────────────────────────────────────────────────────────
## Values are offsets in display (sRGB) space — Godot applies the LUT after
## tonemapping + brightness/contrast/saturation. Kept deliberately small: the
## goal is "cohesive", not "filtered". Split-tone: cool teal shadows, faint
## olive mids, warm sodium highlights.
const SHADOW_TINT: Vector3    = Vector3(-0.012, 0.004, 0.018)
const MID_TINT: Vector3       = Vector3(0.004, 0.008, -0.010)
const HIGHLIGHT_TINT: Vector3 = Vector3(0.025, 0.010, -0.025)
## Luminance where shadow tint has fully faded out / highlight tint starts.
const SHADOW_END: float      = 0.40
const HIGHLIGHT_START: float = 0.55
## Keeps true black neutral — shadow tint ramps in above this luminance so
## the darkest bunker corners don't turn visibly blue.
const BLACK_PROTECT: float = 0.06
## Gentle S-curve blend (0 = none). AgX is lower-contrast than ACES; this
## restores a little punch without crushing.
const CONTRAST: float = 0.10
## 64³ generates in ~0.15s once per session; the half-texel
## edge clamp (Godot samples the LUT without a half-texel remap) only lifts
## the darkest ~2/255 of black.
const LUT_SIZE: int = 64
const LUMA: Vector3 = Vector3(0.2126, 0.7152, 0.0722)

## ── Lens dirt ──────────────────────────────────────────────────────────────
## Glow is multiplied by mix(1, dirt, glow_map_strength): DIRT_BASE is the
## "clean glass" level, smudges/specks push toward 1.0. Only visible where
## something already blooms (wall lamps, emissives).
const DIRT_W: int = 384
const DIRT_H: int = 216   ## 16:9 — the map is stretched to the screen
const DIRT_SEED: int = 1947
const DIRT_BASE: float = 0.55
const DIRT_NOISE_AMP: float = 0.12
const SMUDGE_COUNT: int = 26
const SPECK_COUNT: int = 45

static var _lut_cache: Texture3D = null
static var _dirt_cache: Texture2D = null


static func apply(env: Environment) -> void:
	if env == null:
		return
	env.adjustment_color_correction = _get_lut()
	env.glow_map = _get_lens_dirt()


static func _get_lut() -> Texture3D:
	if _lut_cache == null:
		if ResourceLoader.exists(LUT_OVERRIDE_PATH):
			_lut_cache = load(LUT_OVERRIDE_PATH) as Texture3D
		if _lut_cache == null:
			_lut_cache = _build_lut()
	return _lut_cache


static func _get_lens_dirt() -> Texture2D:
	if _dirt_cache == null:
		if ResourceLoader.exists(DIRT_OVERRIDE_PATH):
			_dirt_cache = load(DIRT_OVERRIDE_PATH) as Texture2D
		if _dirt_cache == null:
			_dirt_cache = _build_lens_dirt()
	return _dirt_cache


static func _grade(c: Vector3) -> Vector3:
	var lum: float = c.dot(LUMA)
	var shadow_ramp: float = smoothstep(0.0, SHADOW_END, lum)
	var s: float = (1.0 - shadow_ramp) * smoothstep(0.0, BLACK_PROTECT, lum)
	var h: float = smoothstep(HIGHLIGHT_START, 1.0, lum)
	var m: float = clampf(shadow_ramp - h, 0.0, 1.0)
	var out: Vector3 = c + SHADOW_TINT * s + MID_TINT * m + HIGHLIGHT_TINT * h
	out = out.clamp(Vector3.ZERO, Vector3.ONE)
	var curved: Vector3 = Vector3(smoothstep(0.0, 1.0, out.x), smoothstep(0.0, 1.0, out.y), smoothstep(0.0, 1.0, out.z))
	return out.lerp(curved, CONTRAST)


## x = red, y = green, z (slice) = blue — matches textureLod(lut, color.rgb).
## Texel i stores the grade of its own centre coordinate ((i + 0.5) / n) so
## linear filtering reproduces the curve exactly between texel centres.
static func _build_lut() -> ImageTexture3D:
	var n: int = LUT_SIZE
	var slices: Array[Image] = []
	for z: int in n:
		var data: PackedByteArray = PackedByteArray()
		data.resize(n * n * 4)
		var b: float = (float(z) + 0.5) / float(n)
		var i: int = 0
		for y: int in n:
			var g: float = (float(y) + 0.5) / float(n)
			for x: int in n:
				var o: Vector3 = _grade(Vector3((float(x) + 0.5) / float(n), g, b))
				data[i] = roundi(o.x * 255.0)
				data[i + 1] = roundi(o.y * 255.0)
				data[i + 2] = roundi(o.z * 255.0)
				data[i + 3] = 255
				i += 4
		slices.append(Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data))
	var tex: ImageTexture3D = ImageTexture3D.new()
	var err: Error = tex.create(Image.FORMAT_RGBA8, n, n, n, false, slices)
	if err != OK:
		push_warning("[PostGrade] LUT creation failed (%d) — colour grade disabled" % err)
		return null
	return tex


static func _build_lens_dirt() -> ImageTexture:
	var w: int = DIRT_W
	var h: int = DIRT_H
	var field: PackedFloat32Array = PackedFloat32Array()
	field.resize(w * h)
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = DIRT_SEED
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	for y: int in h:
		for x: int in w:
			field[y * w + x] = DIRT_BASE + noise.get_noise_2d(float(x), float(y)) * DIRT_NOISE_AMP

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = DIRT_SEED
	## Large soft smudges (fingerprints / grease)
	for _i: int in SMUDGE_COUNT:
		_stamp(field, w, h, rng.randf_range(0.0, w), rng.randf_range(0.0, h),
			rng.randf_range(18.0, 70.0), rng.randf_range(0.12, 0.30))
	## Small hard-ish dust specks that catch the bloom
	for _i: int in SPECK_COUNT:
		_stamp(field, w, h, rng.randf_range(0.0, w), rng.randf_range(0.0, h),
			rng.randf_range(0.8, 2.2), rng.randf_range(0.15, 0.35))

	var data: PackedByteArray = PackedByteArray()
	data.resize(w * h * 3)
	for p: int in w * h:
		var v: int = roundi(clampf(field[p], 0.0, 1.0) * 255.0)
		data[p * 3] = v
		data[p * 3 + 1] = v
		data[p * 3 + 2] = v
	var img: Image = Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data)
	return ImageTexture.create_from_image(img)


static func _stamp(field: PackedFloat32Array, w: int, h: int, cx: float, cy: float, r: float, amp: float) -> void:
	var x0: int = maxi(0, floori(cx - r))
	var x1: int = mini(w - 1, ceili(cx + r))
	var y0: int = maxi(0, floori(cy - r))
	var y1: int = mini(h - 1, ceili(cy + r))
	var inv_r2: float = 1.0 / (r * r)
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var d2: float = ((x - cx) * (x - cx) + (y - cy) * (y - cy)) * inv_r2
			if d2 < 1.0:
				var f: float = 1.0 - d2
				field[y * w + x] += amp * f * f
