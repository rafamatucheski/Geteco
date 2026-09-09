@tool
class_name ModularUrbanKit
extends RefCounted

## ModularUrbanKit.gd
## Kit modular de componentes urbanos, fachadas, telhados, props, vegetacao,
## iluminacao e murais para o Bairro 1 V2 (LandmarksV2).
## Nao cria colisoes solidas fisicas que interfiram com o Layout de Claude.

const TEXTURE_TREE_ROUND := preload("res://assets/art/tree-round-crown.png")
const TEXTURE_TREE_SMALL := preload("res://assets/art/tree-street-small.png")
const TEXTURE_SHRUB := preload("res://assets/art/shrub-cluster.png")

# Paleta Urbana do Bairro 1 V2
const COLOR_CONCRETE := Color("#6c7278")
const COLOR_CONCRETE_LIGHT := Color("#8a9096")
const COLOR_ASPHALT := Color("#23272b")
const COLOR_PAVEMENT := Color("#9a9890")
const COLOR_CURB := Color("#73777a")
const COLOR_BRICK_RED := Color("#8c3a2b")
const COLOR_BRICK_DARK := Color("#59241b")
const COLOR_STUCCO_YELLOW := Color("#d6aa5c")
const COLOR_STUCCO_BLUE := Color("#3b5f7e")
const COLOR_ZINC_ROOF := Color("#4d555c")
const COLOR_ZINC_RUST := Color("#704f3b")
const COLOR_PARK_GRASS := Color("#3b6b3e")
const COLOR_PARK_GRASS_LIGHT := Color("#4d8451")
const COLOR_BASKET_COURT := Color("#bf5728")
const COLOR_BASKET_GREEN := Color("#2f6140")
const COLOR_NEON_BLUE := Color("#00d2ff")
const COLOR_NEON_ORANGE := Color("#ff6b1a")
const COLOR_NEON_GREEN := Color("#25e661")
const COLOR_NEON_PINK := Color("#ff2a8d")
const COLOR_NEON_AMBER := Color("#ffc83b")
const COLOR_WARM_LAMP := Color("#fff1c7")

# ==============================================================================
# 1. ILUMINACAO: POSTES, REFLETORES E LUZES NOTURNAS
# ==============================================================================

static func create_street_lamp(pos: Vector2, lamp_type: String = "city", light_color: Color = COLOR_WARM_LAMP) -> Node2D:
	var lamp := Node2D.new()
	lamp.name = "StreetLamp_" + str(randi() % 9999)
	lamp.position = pos
	lamp.z_index = 8
	
	var post_draw := _StreetLampDrawer.new(lamp_type, light_color)
	lamp.add_child(post_draw)
	
	var light := PointLight2D.new()
	light.name = "LampLight"
	light.color = light_color
	light.energy = 0.95
	light.texture = _get_radial_light_texture(128)
	light.texture_scale = 1.3
	light.shadow_enabled = false
	lamp.add_child(light)
	
	lamp.add_to_group("bairro1_v2_lamps")
	return lamp

static func create_industrial_floodlight(pos: Vector2, facing_angle: float = 0.0, light_color: Color = Color("#ffe9aa")) -> Node2D:
	var floodlight := Node2D.new()
	floodlight.name = "Floodlight_" + str(randi() % 9999)
	floodlight.position = pos
	floodlight.z_index = 8
	
	var drawer := _FloodlightDrawer.new(facing_angle, light_color)
	floodlight.add_child(drawer)
	
	var light := PointLight2D.new()
	light.name = "SpotLight"
	light.color = light_color
	light.energy = 1.1
	light.texture = _get_radial_light_texture(160)
	light.texture_scale = 1.5
	light.position = Vector2(cos(facing_angle), sin(facing_angle)) * 16.0
	floodlight.add_child(light)
	
	floodlight.add_to_group("bairro1_v2_lamps")
	return floodlight

# ==============================================================================
# 2. VEGETACAO: ARVORES DE CALCADA, BOSQUE E JARDINEIRAS
# ==============================================================================

static func create_street_tree(pos: Vector2, variant: int = 0) -> Node2D:
	var tree_node := Node2D.new()
	tree_node.name = "StreetTree_" + str(randi() % 9999)
	tree_node.position = pos
	tree_node.z_index = 7
	
	var shadow := _TreeShadowDrawer.new(30.0 if variant == 0 else 24.0)
	tree_node.add_child(shadow)
	
	var grate := _TreeGrateDrawer.new(28.0)
	tree_node.add_child(grate)
	
	var sprite := Sprite2D.new()
	sprite.name = "Crown"
	sprite.texture = TEXTURE_TREE_ROUND if variant == 0 else TEXTURE_TREE_SMALL
	sprite.position = Vector2(0, -4)
	sprite.scale = Vector2(0.36, 0.36) if variant == 0 else Vector2(0.40, 0.40)
	tree_node.add_child(sprite)
	return tree_node

static func create_flowerbed(rect: Rect2, flower_density: int = 6) -> Node2D:
	var bed := Node2D.new()
	bed.name = "Flowerbed_" + str(randi() % 9999)
	bed.position = rect.position
	bed.z_index = 2
	
	var drawer := _FlowerbedDrawer.new(rect.size, flower_density)
	bed.add_child(drawer)
	
	if rect.size.x >= 50.0 and rect.size.y >= 26.0:
		var shrub := Sprite2D.new()
		shrub.texture = TEXTURE_SHRUB
		shrub.position = rect.size * 0.5
		shrub.scale = Vector2(0.15, 0.15)
		shrub.z_index = 1
		bed.add_child(shrub)
	return bed

static func create_park_bench(pos: Vector2, rotation_rad: float = 0.0) -> Node2D:
	var bench := Node2D.new()
	bench.name = "ParkBench_" + str(randi() % 9999)
	bench.position = pos
	bench.rotation = rotation_rad
	bench.z_index = 3
	var drawer := _BenchDrawer.new()
	bench.add_child(drawer)
	return bench

# ==============================================================================
# 3. PROPS URBANOS: CAIXAS, LIXEIRAS, PALETES E BARRACAS
# ==============================================================================

static func create_dumpster(pos: Vector2, color: Color = Color("#2d5a3f"), rotation_rad: float = 0.0) -> Node2D:
	var dumpster := Node2D.new()
	dumpster.name = "Dumpster_" + str(randi() % 9999)
	dumpster.position = pos
	dumpster.rotation = rotation_rad
	dumpster.z_index = 4
	var drawer := _DumpsterDrawer.new(color)
	dumpster.add_child(drawer)
	return dumpster

static func create_pallet_stack(pos: Vector2, count: int = 3) -> Node2D:
	var stack := Node2D.new()
	stack.name = "PalletStack_" + str(randi() % 9999)
	stack.position = pos
	stack.z_index = 3
	var drawer := _PalletDrawer.new(count)
	stack.add_child(drawer)
	return stack

static func create_market_stall(pos: Vector2, stripe_color1: Color, stripe_color2: Color = Color.WHITE) -> Node2D:
	var stall := Node2D.new()
	stall.name = "MarketStall_" + str(randi() % 9999)
	stall.position = pos
	stall.z_index = 5
	var drawer := _MarketStallDrawer.new(stripe_color1, stripe_color2)
	stall.add_child(drawer)
	return stall

static func create_bus_shelter(pos: Vector2, rotation_rad: float = 0.0) -> Node2D:
	var shelter := Node2D.new()
	shelter.name = "BusShelter_" + str(randi() % 9999)
	shelter.position = pos
	shelter.rotation = rotation_rad
	shelter.z_index = 5
	var drawer := _BusShelterDrawer.new()
	shelter.add_child(drawer)
	return shelter

# ==============================================================================
# 4. NEON E LETREIROS COMPACTOS (NAO INVADEM RUAS)
# ==============================================================================

static func create_neon_sign(pos: Vector2, text: String, glow_color: Color = COLOR_NEON_ORANGE, font_size: int = 10) -> Node2D:
	var sign_node := Node2D.new()
	sign_node.name = "NeonSign_" + str(randi() % 9999)
	sign_node.position = pos
	sign_node.z_index = 9
	
	var label := Label.new()
	label.name = "Label"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", glow_color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-70, -10)
	label.size = Vector2(140, 20)
	label.custom_minimum_size = Vector2(140, 20)
	sign_node.add_child(label)
	
	var light := PointLight2D.new()
	light.name = "GlowLight"
	light.color = glow_color
	light.energy = 0.65
	light.texture = _get_radial_light_texture(96)
	light.texture_scale = 0.9
	sign_node.add_child(light)
	
	sign_node.add_to_group("bairro1_v2_neons")
	return sign_node

# ==============================================================================
# 5. BECOS: MURAIS, ESCADA DE INCENDIO, AREA DE CARGA, PONTO DE OBSERVACAO
# ==============================================================================

static func create_graffiti_mural(pos: Vector2, size: Vector2, title: String = "VIELA DA RESISTÊNCIA") -> Node2D:
	var mural := Node2D.new()
	mural.name = "GraffitiMural_" + str(randi() % 9999)
	mural.position = pos
	mural.z_index = 3
	var drawer := _MuralDrawer.new(size, title)
	mural.add_child(drawer)
	return mural

static func create_fire_escape_ladder(pos: Vector2, height_px: float = 70.0) -> Node2D:
	var ladder := Node2D.new()
	ladder.name = "FireEscape_" + str(randi() % 9999)
	ladder.position = pos
	ladder.z_index = 6
	var drawer := _FireEscapeDrawer.new(height_px)
	ladder.add_child(drawer)
	return ladder

static func create_loading_dock(pos: Vector2, size: Vector2 = Vector2(100, 36)) -> Node2D:
	var dock := Node2D.new()
	dock.name = "LoadingDock_" + str(randi() % 9999)
	dock.position = pos
	dock.z_index = 3
	var drawer := _LoadingDockDrawer.new(size)
	dock.add_child(drawer)
	return dock

static func create_rooftop_observation_point(pos: Vector2, size: Vector2 = Vector2(50, 32)) -> Node2D:
	var mirante := Node2D.new()
	mirante.name = "ObservationPoint_" + str(randi() % 9999)
	mirante.position = pos
	mirante.z_index = 8
	var drawer := _ObservationDrawer.new(size)
	mirante.add_child(drawer)
	return mirante

# ==============================================================================
# UTILITARIOS VISUAIS & TEXTURAS PROCEDURAIS
# ==============================================================================

static var _cached_radial_tex: Dictionary = {}

static func _get_radial_light_texture(size_px: int) -> GradientTexture2D:
	if _cached_radial_tex.has(size_px):
		return _cached_radial_tex[size_px]
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = size_px
	tex.height = size_px
	_cached_radial_tex[size_px] = tex
	return tex

# ==============================================================================
# CLASSES DE DESENHO VETORIAL PARA PROPS E DETALHES
# ==============================================================================

class _StreetLampDrawer extends Node2D:
	var _type: String
	var _col: Color
	func _init(p_type: String, p_col: Color) -> void:
		_type = p_type
		_col = p_col
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.0, Color(0.12, 0.14, 0.16, 0.8))
		draw_circle(Vector2.ZERO, 2.0, Color(0.35, 0.38, 0.42))
		draw_line(Vector2.ZERO, Vector2(0, -14), Color(0.2, 0.22, 0.25), 2.5)
		draw_circle(Vector2(0, -15), 3.5, _col)
		draw_circle(Vector2(0, -15), 1.6, Color.WHITE)

class _FloodlightDrawer extends Node2D:
	var _angle: float
	var _col: Color
	func _init(p_angle: float, p_col: Color) -> void:
		_angle = p_angle
		_col = p_col
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 3.5, Color(0.1, 0.1, 0.1, 0.9))
		var dir := Vector2(cos(_angle), sin(_angle))
		draw_line(Vector2.ZERO, dir * 8.0, Color(0.3, 0.32, 0.35), 3.0)
		draw_rect(Rect2(dir * 8.0 - Vector2(5, 3), Vector2(10, 6)), _col)

class _TreeShadowDrawer extends Node2D:
	var _radius: float
	func _init(r: float) -> void:
		_radius = r
	func _draw() -> void:
		draw_circle(Vector2(3, 4), _radius, Color(0.06, 0.08, 0.1, 0.28))

class _TreeGrateDrawer extends Node2D:
	var _size: float
	func _init(s: float) -> void:
		_size = s
	func _draw() -> void:
		var half := _size * 0.5
		var r := Rect2(-half, -half, _size, _size)
		draw_rect(r, Color(0.28, 0.3, 0.32), false, 1.5)
		draw_line(Vector2(-half, 0), Vector2(half, 0), Color(0.24, 0.26, 0.28), 1.0)
		draw_line(Vector2(0, -half), Vector2(0, half), Color(0.24, 0.26, 0.28), 1.0)

class _FlowerbedDrawer extends Node2D:
	var _size: Vector2
	var _count: int
	func _init(s: Vector2, c: int) -> void:
		_size = s
		_count = c
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, _size), Color("#54585c"), true)
		draw_rect(Rect2(Vector2(2, 2), _size - Vector2(4, 4)), Color("#3b2b1e"), true)
		draw_rect(Rect2(Vector2(3, 3), _size - Vector2(6, 6)), COLOR_PARK_GRASS, true)
		var colors := [Color("#e84118"), Color("#fbc531"), Color("#9c88ff"), Color("#4cd137"), Color("#ffffff")]
		for i in range(_count):
			var fx := 5.0 + float(i * 11 % int(maxf(1.0, _size.x - 10.0)))
			var fy := 5.0 + float((i * 13) % int(maxf(1.0, _size.y - 10.0)))
			draw_circle(Vector2(fx, fy), 1.8, colors[i % colors.size()])

class _BenchDrawer extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-10, -3, 20, 6), Color(0.1, 0.1, 0.1, 0.3), true)
		draw_rect(Rect2(-11, -4, 22, 3), Color("#7a4f2e"), true)
		draw_rect(Rect2(-11, 0, 22, 3), Color("#613d22"), true)
		draw_line(Vector2(-9, -4), Vector2(-9, 2), Color("#202224"), 1.8)
		draw_line(Vector2(9, -4), Vector2(9, 2), Color("#202224"), 1.8)

class _DumpsterDrawer extends Node2D:
	var _color: Color
	func _init(c: Color) -> void:
		_color = c
	func _draw() -> void:
		draw_rect(Rect2(-14, -9, 28, 18), Color(0.1, 0.1, 0.1, 0.4), true)
		draw_rect(Rect2(-15, -10, 30, 20), _color, true)
		draw_rect(Rect2(-15, -10, 30, 20), Color(0.15, 0.18, 0.2), false, 1.5)
		draw_rect(Rect2(-13, -8, 12, 16), Color(0.18, 0.2, 0.22), true)
		draw_rect(Rect2(1, -8, 12, 16), Color(0.22, 0.25, 0.27), true)

class _PalletDrawer extends Node2D:
	var _count: int
	func _init(c: int) -> void:
		_count = c
	func _draw() -> void:
		draw_rect(Rect2(-10, -8, 20, 16), Color(0.08, 0.09, 0.1, 0.3), true)
		for i in range(_count):
			var off := Vector2(i * 1.0, -i * 1.5)
			draw_rect(Rect2(Vector2(-10, -8) + off, Vector2(20, 16)), Color("#b08958"), true)
			draw_rect(Rect2(Vector2(-10, -8) + off, Vector2(20, 16)), Color("#7d5e38"), false, 1.2)

class _MarketStallDrawer extends Node2D:
	var _c1: Color
	var _c2: Color
	func _init(c1: Color, c2: Color) -> void:
		_c1 = c1
		_c2 = c2
	func _draw() -> void:
		draw_rect(Rect2(-18, -10, 36, 20), Color("#99704c"), true)
		draw_rect(Rect2(-15, -7, 13, 7), Color("#d98038"), true)
		draw_rect(Rect2(2, -7, 13, 7), Color("#4cd137"), true)
		var stripe_w := 4.5
		for i in range(8):
			var col := _c1 if i % 2 == 0 else _c2
			draw_rect(Rect2(-18.0 + float(i) * stripe_w, -12.0, stripe_w, 24.0), col, true)
		draw_rect(Rect2(-18, -12, 36, 24), Color(0.2, 0.2, 0.2, 0.35), false, 1.2)

class _BusShelterDrawer extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-20, -7, 40, 14), Color(0.1, 0.1, 0.1, 0.3), true)
		draw_rect(Rect2(-21, -8, 42, 16), Color(0.2, 0.5, 0.7, 0.5), true)
		draw_rect(Rect2(-21, -8, 42, 16), Color(0.3, 0.35, 0.4), false, 1.5)
		draw_rect(Rect2(-13, -2, 26, 3), Color("#b08958"), true)
		draw_rect(Rect2(15, -6, 4, 11), Color("#e84118"), true)

class _MuralDrawer extends Node2D:
	var _size: Vector2
	var _title: String
	func _init(s: Vector2, t: String) -> void:
		_size = s
		_title = t
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, _size), Color("#2a2d32"), true)
		draw_rect(Rect2(Vector2.ZERO, _size), Color("#18191c"), false, 1.5)
		draw_line(Vector2(4, _size.y * 0.75), Vector2(_size.x * 0.4, 4), COLOR_NEON_PINK, 3.5)
		draw_line(Vector2(_size.x * 0.2, _size.y - 4), Vector2(_size.x - 4, _size.y * 0.3), COLOR_NEON_BLUE, 4.0)
		draw_circle(Vector2(_size.x * 0.5, _size.y * 0.45), minf(_size.x, _size.y) * 0.22, COLOR_NEON_ORANGE)

class _FireEscapeDrawer extends Node2D:
	var _height: float
	func _init(h: float) -> void:
		_height = h
	func _draw() -> void:
		var c := Color("#353b42")
		draw_line(Vector2(-5, 0), Vector2(-5, -_height), c, 2.0)
		draw_line(Vector2(5, 0), Vector2(5, -_height), c, 2.0)
		var steps := int(_height / 8.0)
		for i in range(steps):
			var y := -float(i * 8)
			draw_line(Vector2(-5, y), Vector2(5, y), c, 1.5)
		draw_rect(Rect2(-10, -_height * 0.5 - 4, 20, 8), Color(0.2, 0.22, 0.25), true)

class _LoadingDockDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, _size), Color("#4b5056"), true)
		draw_rect(Rect2(Vector2.ZERO, _size), Color("#2f3337"), false, 1.5)
		var stripe_w := 8.0
		var num_stripes := int(_size.x / stripe_w)
		for i in range(num_stripes):
			var col := Color("#fbc531") if i % 2 == 0 else Color("#1e2124")
			draw_rect(Rect2(float(i) * stripe_w, _size.y - 4, stripe_w, 4), col, true)

class _ObservationDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#40464d"), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#fbc531"), false, 1.5)
		draw_circle(Vector2.ZERO, 3.0, Color("#dcdde1"))
		draw_line(Vector2.ZERO, Vector2(0, -5), Color("#718093"), 1.8)
