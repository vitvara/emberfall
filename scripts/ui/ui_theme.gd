class_name UITheme
extends RefCounted
## Medieval UI kit, generated in code: dark stone panels in riveted iron frames,
## crimson lacquered buttons, inset slots, framed bars and parchment sheets.

const GOLD := Color(0.94, 0.84, 0.6)
const GOLD_DIM := Color(0.75, 0.62, 0.38)
const TEXT := Color(0.9, 0.86, 0.76)
const INK := Color(0.22, 0.14, 0.08)

static var _theme: Theme
static var _cache := {}
static var _title_font: FontVariation
static var _body_font: Font


# ------------------------------------------------------------------ fonts

static func title_font() -> Font:
	if _title_font == null:
		_title_font = FontVariation.new()
		var f = load("res://assets/fonts/Cinzel.ttf")
		if f != null:
			_title_font.base_font = f
			var ts := TextServerManager.get_primary_interface()
			_title_font.variation_opentype = {ts.name_to_tag("wght"): 700}
	return _title_font


static func body_font() -> Font:
	if _body_font == null:
		var f = load("res://assets/fonts/IMFell.ttf")
		_body_font = f if f != null else ThemeDB.fallback_font
	return _body_font


# ------------------------------------------------------------------ texture helpers

static func _noise(x: int, y: int, seed_v: int) -> float:
	var n := int(x * 374761393 + y * 668265263 + seed_v * 2147483647) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xffff) / 65535.0


static func _tex(img: Image) -> ImageTexture:
	return ImageTexture.create_from_image(img)


## Riveted iron frame around a stone fill. `fill` is the inner colour.
static func _iron_image(w: int, h: int, fill: Color, rivets := true) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var g := _noise(x, y, 7) * 0.5 + _noise(x / 3, y / 3, 11) * 0.5
			var c := fill.lerp(fill.lightened(0.25), g * 0.35)
			var edge := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
			if edge == 0:
				c = Color(0.02, 0.02, 0.02)
			elif edge <= 4:
				# Bevelled metal: lit from the top-left
				var lit := (x < w / 2 and y < h / 2) or (y < 5) or (x < 5)
				var dark := (y > h - 6) or (x > w - 6)
				var base := Color(0.42, 0.4, 0.38)
				if lit and not dark:
					base = Color(0.62, 0.58, 0.52)
				elif dark:
					base = Color(0.2, 0.19, 0.18)
				c = base.lerp(base.darkened(0.3), _noise(x, y, 3) * 0.5)
				if edge == 4:
					c = c.darkened(0.45)
			elif edge == 5:
				c = Color(0.04, 0.04, 0.05)
			img.set_pixel(x, y, c)
	if rivets:
		for p in [Vector2i(3, 3), Vector2i(w - 4, 3), Vector2i(3, h - 4), Vector2i(w - 4, h - 4)]:
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var d := sqrt(dx * dx + dy * dy)
					if d <= 2.2:
						var shade := 0.85 - (dx + dy) * 0.09
						img.set_pixel(p.x + dx, p.y + dy, Color(shade * 0.9, shade * 0.82, shade * 0.65))
	return img


static func _style_from(img: Image, margin: int, content := 10.0, tile := true) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = _tex(img)
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(content)
	if tile:
		sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return sb


# ------------------------------------------------------------------ public styles

static func iron_panel() -> StyleBoxTexture:
	if not _cache.has("panel"):
		_cache["panel"] = _style_from(_iron_image(64, 64, Color(0.085, 0.08, 0.085)), 10, 12.0)
	return _cache["panel"]


## Translucent variant for in-game frames so the world shows through a little.
static func iron_panel_hud() -> StyleBoxTexture:
	if not _cache.has("panel_hud"):
		var img := _iron_image(64, 64, Color(0.07, 0.065, 0.07))
		for y in range(6, 58):
			for x in range(6, 58):
				var c := img.get_pixel(x, y)
				c.a = 0.82
				img.set_pixel(x, y, c)
		_cache["panel_hud"] = _style_from(img, 10, 10.0)
	return _cache["panel_hud"]


## Inset dark slot (action bar, inputs, list rows).
static func slot(highlight := Color(0, 0, 0, 0)) -> StyleBoxTexture:
	var key := "slot_%s" % highlight.to_html()
	if not _cache.has(key):
		var w := 48
		var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
		for y in w:
			for x in w:
				var edge := mini(mini(x, y), mini(w - 1 - x, w - 1 - y))
				var c := Color(0.05, 0.05, 0.055).lerp(Color(0.1, 0.095, 0.1), _noise(x, y, 5) * 0.6)
				if edge <= 1:
					c = Color(0.36, 0.33, 0.3) if (x < w / 2 or y < w / 2) else Color(0.18, 0.17, 0.16)
				elif edge == 2:
					c = Color(0.02, 0.02, 0.02)
				elif edge <= 5:
					c = c.darkened(0.5 - edge * 0.08)  # inner shadow
				if highlight.a > 0.0 and edge <= 2:
					c = highlight
				img.set_pixel(x, y, c)
		_cache[key] = _style_from(img, 6, 6.0, false)
	return _cache[key]


## Crimson lacquered button with a gold-bronze rim. state: normal | hover | pressed | disabled
static func button(state := "normal") -> StyleBoxTexture:
	var key := "btn_" + state
	if not _cache.has(key):
		var w := 64
		var h := 32
		var top := Color(0.56, 0.12, 0.1)
		var bot := Color(0.3, 0.05, 0.05)
		match state:
			"hover":
				top = Color(0.72, 0.18, 0.13)
				bot = Color(0.4, 0.08, 0.06)
			"pressed":
				top = Color(0.3, 0.06, 0.05)
				bot = Color(0.45, 0.1, 0.08)
			"disabled":
				top = Color(0.25, 0.22, 0.22)
				bot = Color(0.14, 0.13, 0.13)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var edge := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
				var f := float(y) / h
				var c := top.lerp(bot, f).lerp(top.lightened(0.1), _noise(x, y, 9) * 0.12)
				if y == 3 and edge >= 3:
					c = c.lightened(0.25)  # gloss line
				if edge == 0:
					c = Color(0.03, 0.02, 0.02)
				elif edge <= 2:
					c = Color(0.72, 0.56, 0.3) if y < h / 2 else Color(0.45, 0.33, 0.16)
					if state == "disabled":
						c = Color(0.35, 0.33, 0.3)
				img.set_pixel(x, y, c)
		var sb := _style_from(img, 5, 8.0, false)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		_cache[key] = sb
	return _cache[key]


## Aged parchment sheet with burnt edges (tooltips, character sheet).
static func parchment() -> StyleBoxTexture:
	if not _cache.has("parchment"):
		var w := 128
		var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
		for y in w:
			for x in w:
				var g := _noise(x / 2, y / 2, 21) * 0.6 + _noise(x / 8, y / 8, 22) * 0.4
				var c := Color(0.86, 0.76, 0.56).lerp(Color(0.74, 0.6, 0.4), g * 0.5)
				var edge := mini(mini(x, y), mini(w - 1 - x, w - 1 - y))
				if edge < 10:
					c = c.lerp(Color(0.42, 0.28, 0.14), (10.0 - edge) / 10.0 * 0.75)
				if edge == 0:
					c = Color(0.2, 0.12, 0.06)
				img.set_pixel(x, y, c)
		_cache["parchment"] = _style_from(img, 14, 14.0, false)
	return _cache["parchment"]


static func bar_bg() -> StyleBoxTexture:
	if not _cache.has("bar_bg"):
		var w := 32
		var h := 16
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var edge := mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
				var c := Color(0.04, 0.035, 0.04, 0.92)
				if edge == 0:
					c = Color(0.48, 0.44, 0.38) if y < h / 2 else Color(0.22, 0.2, 0.18)
				elif edge == 1:
					c = Color(0.0, 0.0, 0.0)
				img.set_pixel(x, y, c)
		_cache["bar_bg"] = _style_from(img, 3, 2.0, false)
	return _cache["bar_bg"]


## Glossy bar fill in the given colour (lighter band on top, darker bottom).
static func bar_fill(c: Color) -> StyleBoxTexture:
	var key := "fill_" + c.to_html()
	if not _cache.has(key):
		var w := 16
		var h := 16
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var f := float(y) / (h - 1)
				var col := c.lightened(0.35).lerp(c, smoothstep(0.0, 0.4, f)).lerp(c.darkened(0.45), smoothstep(0.5, 1.0, f))
				if y == 2:
					col = col.lightened(0.3)
				if x == 0 or y == 0 or x == w - 1 or y == h - 1:
					col = Color(0, 0, 0, 0)
				img.set_pixel(x, y, col)
		_cache[key] = _style_from(img, 2, 0.0, false)
	return _cache[key]


# ------------------------------------------------------------------ theme

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 17
	t.set_stylebox("panel", "PanelContainer", iron_panel())
	t.set_stylebox("panel", "Panel", iron_panel())
	for st in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(st, "Button", button(st))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 15)
	t.set_color("font_color", "Button", GOLD)
	t.set_color("font_hover_color", "Button", Color(1, 0.96, 0.85))
	t.set_color("font_pressed_color", "Button", GOLD_DIM)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.52, 0.48))
	t.set_color("font_outline_color", "Button", Color(0, 0, 0))
	t.set_constant("outline_size", "Button", 4)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 4)
	t.set_stylebox("normal", "LineEdit", slot())
	t.set_stylebox("focus", "LineEdit", slot(Color(0.75, 0.6, 0.3)))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_font_size("font_size", "LineEdit", 17)
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed", "focus"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	t.set_font("font", "CheckBox", body_font())
	t.set_font_size("font_size", "CheckBox", 17)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", GOLD)
	t.set_color("font_hover_color", "CheckBox", GOLD)
	t.set_stylebox("panel", "TooltipPanel", parchment())
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 16)
	t.set_stylebox("background", "ProgressBar", bar_bg())
	t.set_stylebox("fill", "ProgressBar", bar_fill(Color(0.7, 0.1, 0.08)))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	_theme = t
	return t


## A big title label in the engraved serif.
static func title(text: String, size := 30, c := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Thin gold divider line.
static func divider() -> Control:
	var c := ColorRect.new()
	c.color = Color(0.6, 0.48, 0.26, 0.8)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
