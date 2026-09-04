@tool
class_name LandmarkBuilding
extends Node2D

## LandmarkBuilding.gd
## Edificio ou espaco de marco urbano autoral para o Bairro 1 V2.
## Combina geometria vetorial precisa, texturas retro 2.5D, props tematicos,
## neons compactos e iluminacao noturna sem introduzir colisoes fisicas solidas
## e sem invadir faixas de rolamento ou calcadas.

enum LandmarkType {
	MARKET,            # Mercado Municipal / Feira
	BUS_TERMINAL,      # Terminal de Onibus Rodoviario
	PARK_SPORTS,       # Parque Urbano & Quadras
	AUTO_GARAGE,       # Oficina Mecanica / Preparacao
	WAREHOUSE,         # Galpao Industrial / Logistica
	BAR_BOTECO,        # Bar do Bairro (Boteco / Sinuca)
	LAUNDROMAT,        # Lavanderia 24h
	COMMUNITY_SCHOOL,  # Escola / Centro Comunitario
	RAIL_UNDERPASS     # Passagem Ferroviaria
}

@export var landmark_type: LandmarkType = LandmarkType.MARKET
@export var landmark_title: String = ""
@export var footprint_size: Vector2 = Vector2(220, 150)
@export var primary_color: Color = Color("#8c3a2b")
@export var accent_color: Color = Color("#fbc531")

const COLOR_NEON_BLUE := Color("#00d2ff")
const COLOR_NEON_ORANGE := Color("#ff6b1a")
const COLOR_NEON_GREEN := Color("#25e661")
const COLOR_NEON_PINK := Color("#ff2a8d")
const COLOR_NEON_AMBER := Color("#ffc83b")

var _fade_tween: Tween = null
var _overlapping_actors: int = 0
var _lights: Array[Light2D] = []
var _is_night: bool = false

func _ready() -> void:
	add_to_group("bairro1_v2_landmarks")
	_build_landmark_content()
	_setup_pass_through_fade()
	_connect_day_night()

func _build_landmark_content() -> void:
	for child in get_children():
		if child.name != "PassThroughArea":
			child.queue_free()

	match landmark_type:
		LandmarkType.MARKET:
			_build_market()
		LandmarkType.BUS_TERMINAL:
			_build_bus_terminal()
		LandmarkType.PARK_SPORTS:
			_build_park_sports()
		LandmarkType.AUTO_GARAGE:
			_build_auto_garage()
		LandmarkType.WAREHOUSE:
			_build_warehouse()
		LandmarkType.BAR_BOTECO:
			_build_bar_boteco()
		LandmarkType.LAUNDROMAT:
			_build_laundromat()
		LandmarkType.COMMUNITY_SCHOOL:
			_build_community_school()
		LandmarkType.RAIL_UNDERPASS:
			_build_rail_underpass()

# ==============================================================================
# 1. MERCADO MUNICIPAL / FEIRA
# ==============================================================================
func _build_market() -> void:
	var ground := _MarketGroundDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	# Galpao principal do mercado (recuado ao fundo do lote)
	var hall_size := Vector2(footprint_size.x * 0.85, footprint_size.y * 0.55)
	var hall_pos := Vector2(-hall_size.x * 0.5, -footprint_size.y * 0.5 + 8.0)
	var hall := _BuildingRoofDrawer.new(hall_size, Color("#8a5a36"), Color("#5c3c24"), "zinc_arch")
	hall.position = hall_pos
	hall.z_index = 5
	add_child(hall)
	
	# Letreiro compacto no topo da platibanda (sem avançar na rua)
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, hall_pos.y + 12.0),
		"MERCADO MUNICIPAL",
		Color("#ffc048"),
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	# Barracas de Feira na frente (área de pedestres interna do lote)
	var stall_y := footprint_size.y * 0.28
	var stall_colors := [Color("#e84118"), Color("#44bd32"), Color("#00a8ff"), Color("#fbc531")]
	for i in range(3):
		var sx := -footprint_size.x * 0.28 + float(i) * (footprint_size.x * 0.28)
		var stall := ModularUrbanKit.create_market_stall(Vector2(sx, stall_y), stall_colors[i % stall_colors.size()])
		stall.z_index = 3
		add_child(stall)
		
	# Caixas e paletes nas laterais internas
	var pallets := ModularUrbanKit.create_pallet_stack(Vector2(footprint_size.x * 0.40, -10.0), 3)
	pallets.z_index = 3
	add_child(pallets)
	
	var lamp := ModularUrbanKit.create_street_lamp(Vector2(-footprint_size.x * 0.40, footprint_size.y * 0.40))
	lamp.z_index = 10
	add_child(lamp)

# ==============================================================================
# 2. TERMINAL DE ÔNIBUS RODOVIÁRIO
# ==============================================================================
func _build_bus_terminal() -> void:
	var ground := _TerminalGroundDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	# Predio administrativo do terminal (lateral)
	var bldg_size := Vector2(footprint_size.x * 0.38, footprint_size.y * 0.50)
	var bldg_pos := Vector2(-footprint_size.x * 0.44, -footprint_size.y * 0.42)
	var bldg := _BuildingRoofDrawer.new(bldg_size, Color("#3d566e"), Color("#273746"), "flat_ac")
	bldg.position = bldg_pos
	bldg.z_index = 5
	add_child(bldg)
	
	# Cobertura metálica das plataformas
	var canopy_size := Vector2(footprint_size.x * 0.50, footprint_size.y * 0.70)
	var canopy_pos := Vector2(footprint_size.x * 0.08, -footprint_size.y * 0.30)
	var canopy := _CanopyDrawer.new(canopy_size, Color("#487eb0"))
	canopy.position = canopy_pos
	canopy.z_index = 7
	add_child(canopy)
	
	# Letreiro compacto no topo
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(-footprint_size.x * 0.25, bldg_pos.y + 12.0),
		"TERMINAL DISTRITAL",
		Color("#00d2ff"),
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	var shelter := ModularUrbanKit.create_bus_shelter(Vector2(footprint_size.x * 0.25, footprint_size.y * 0.28))
	shelter.z_index = 4
	add_child(shelter)
	
	var lamp := ModularUrbanKit.create_street_lamp(Vector2(footprint_size.x * 0.40, -footprint_size.y * 0.35), "halogen", Color("#dff9fb"))
	lamp.z_index = 10
	add_child(lamp)

# ==============================================================================
# 3. PARQUE URBANO & QUADRAS POLIESPORTIVAS
# ==============================================================================
func _build_park_sports() -> void:
	var park_ground := _ParkGroundDrawer.new(footprint_size)
	park_ground.z_index = 1
	add_child(park_ground)
	
	# Quadra de basquete
	var court_size := Vector2(footprint_size.x * 0.44, footprint_size.y * 0.60)
	var court_pos := Vector2(-footprint_size.x * 0.24, -footprint_size.y * 0.15)
	var court := _BasketballCourtDrawer.new(court_size)
	court.position = court_pos
	court.z_index = 2
	add_child(court)
	
	# Árvores no bosque lateral
	var tree_positions := [
		Vector2(footprint_size.x * 0.24, -footprint_size.y * 0.28),
		Vector2(footprint_size.x * 0.38, -footprint_size.y * 0.10),
		Vector2(footprint_size.x * 0.28, footprint_size.y * 0.22)
	]
	for idx in range(tree_positions.size()):
		var tree := ModularUrbanKit.create_street_tree(tree_positions[idx], idx % 2)
		tree.z_index = 8
		add_child(tree)
		
	var flowerbed := ModularUrbanKit.create_flowerbed(Rect2(Vector2(footprint_size.x * 0.12, -footprint_size.y * 0.05), Vector2(55, 28)), 6)
	flowerbed.z_index = 2
	add_child(flowerbed)
	
	var bench := ModularUrbanKit.create_park_bench(Vector2(footprint_size.x * 0.18, footprint_size.y * 0.12), 0.0)
	bench.z_index = 3
	add_child(bench)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, -footprint_size.y * 0.44),
		"PARQUE CENTRAL",
		Color("#4cd137"),
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)

# ==============================================================================
# 4. OFICINA MECÂNICA / PREPARAÇÃO
# ==============================================================================
func _build_auto_garage() -> void:
	var ground := _GarageGroundDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	var garage_size := Vector2(footprint_size.x * 0.86, footprint_size.y * 0.58)
	var garage_pos := Vector2(-garage_size.x * 0.5, -footprint_size.y * 0.5 + 8.0)
	var garage := _BuildingRoofDrawer.new(garage_size, Color("#57606f"), Color("#2f3542"), "corrugated")
	garage.position = garage_pos
	garage.z_index = 5
	add_child(garage)
	
	# Portão de rolo industrial
	var bay := _GarageBayDrawer.new(Vector2(90, 32))
	bay.position = Vector2(-45, garage_pos.y + garage_size.y - 10.0)
	bay.z_index = 6
	add_child(bay)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, garage_pos.y + 12.0),
		"OFICINA VELOZ",
		COLOR_NEON_ORANGE,
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	var tires := _TireStackDrawer.new(Vector2(footprint_size.x * 0.35, footprint_size.y * 0.25))
	tires.z_index = 3
	add_child(tires)
	
	var dumpster := ModularUrbanKit.create_dumpster(Vector2(-footprint_size.x * 0.35, footprint_size.y * 0.28), Color("#27ae60"))
	dumpster.z_index = 3
	add_child(dumpster)
	
	var floodlight := ModularUrbanKit.create_industrial_floodlight(Vector2(0, garage_pos.y + garage_size.y), PI * 0.5, Color("#fffa65"))
	floodlight.z_index = 10
	add_child(floodlight)

# ==============================================================================
# 5. GALPÃO INDUSTRIAL / LOGÍSTICA
# ==============================================================================
func _build_warehouse() -> void:
	var ground := _ConcreteYardDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	var wh_size := Vector2(footprint_size.x * 0.88, footprint_size.y * 0.62)
	var wh_pos := Vector2(-wh_size.x * 0.5, -footprint_size.y * 0.5 + 8.0)
	var wh := _BuildingRoofDrawer.new(wh_size, Color("#535c68"), Color("#30336b"), "warehouse_vents")
	wh.position = wh_pos
	wh.z_index = 5
	add_child(wh)
	
	var dock := ModularUrbanKit.create_loading_dock(Vector2(-55, wh_pos.y + wh_size.y - 6.0), Vector2(110, 30))
	dock.z_index = 4
	add_child(dock)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, wh_pos.y + 12.0),
		"LOGÍSTICA & CARGAS",
		COLOR_NEON_AMBER,
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	var pallets := ModularUrbanKit.create_pallet_stack(Vector2(footprint_size.x * 0.35, footprint_size.y * 0.28), 4)
	pallets.z_index = 3
	add_child(pallets)
	
	var floodlight := ModularUrbanKit.create_industrial_floodlight(Vector2(-footprint_size.x * 0.32, wh_pos.y + wh_size.y), PI * 0.5, Color("#fff200"))
	floodlight.z_index = 10
	add_child(floodlight)

# ==============================================================================
# 6. BAR DO BAIRRO (BOTECO / SINUCA)
# ==============================================================================
func _build_bar_boteco() -> void:
	var ground := _SidewalkTileDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	var bar_size := Vector2(footprint_size.x * 0.82, footprint_size.y * 0.56)
	var bar_pos := Vector2(-bar_size.x * 0.5, -footprint_size.y * 0.5 + 8.0)
	var bar_bldg := _BuildingRoofDrawer.new(bar_size, Color("#8c3a2b"), Color("#4a1f18"), "brick_awning")
	bar_bldg.position = bar_pos
	bar_bldg.z_index = 5
	add_child(bar_bldg)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, bar_pos.y + 12.0),
		"BOTECO ESQUINA",
		COLOR_NEON_PINK,
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	# Mesas na varanda frontal interna do lote
	var table_x := [-footprint_size.x * 0.25, footprint_size.x * 0.25]
	for tx in table_x:
		var table := _BarTableDrawer.new(Vector2(tx, footprint_size.y * 0.30))
		table.z_index = 4
		add_child(table)
		
	var lamp := ModularUrbanKit.create_street_lamp(Vector2(footprint_size.x * 0.38, footprint_size.y * 0.35), "city", Color("#ffbe76"))
	lamp.z_index = 10
	add_child(lamp)

# ==============================================================================
# 7. LAVANDERIA 24H
# ==============================================================================
func _build_laundromat() -> void:
	var ground := _SidewalkTileDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	var wash_size := Vector2(footprint_size.x * 0.80, footprint_size.y * 0.58)
	var wash_pos := Vector2(-wash_size.x * 0.5, -footprint_size.y * 0.5 + 8.0)
	var wash_bldg := _BuildingRoofDrawer.new(wash_size, Color("#2c3e50"), Color("#1a252f"), "modern_ac")
	wash_bldg.position = wash_pos
	wash_bldg.z_index = 5
	add_child(wash_bldg)
	
	var window_drawer := _LaundromatWindowDrawer.new(Vector2(wash_size.x * 0.70, 26))
	window_drawer.position = Vector2(-wash_size.x * 0.35, wash_pos.y + wash_size.y - 8.0)
	window_drawer.z_index = 6
	add_child(window_drawer)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, wash_pos.y + 12.0),
		"LAVANDERIA 24H",
		COLOR_NEON_BLUE,
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	var tree := ModularUrbanKit.create_street_tree(Vector2(-footprint_size.x * 0.38, footprint_size.y * 0.30), 1)
	tree.z_index = 8
	add_child(tree)

# ==============================================================================
# 8. ESCOLA / CENTRO COMUNITÁRIO
# ==============================================================================
func _build_community_school() -> void:
	var ground := _SchoolGroundDrawer.new(footprint_size)
	ground.z_index = 1
	add_child(ground)
	
	var school_size := Vector2(footprint_size.x * 0.85, footprint_size.y * 0.58)
	var school_pos := Vector2(-school_size.x * 0.5, -footprint_size.y * 0.5 + 8.0)
	var school := _BuildingRoofDrawer.new(school_size, Color("#95a5a6"), Color("#7f8c8d"), "school_clock")
	school.position = school_pos
	school.z_index = 5
	add_child(school)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, school_pos.y + 12.0),
		"CENTRO COMUNITÁRIO",
		Color("#f1f2f6"),
		11
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	var flagpole := _FlagpoleDrawer.new(Vector2(-footprint_size.x * 0.30, footprint_size.y * 0.25))
	flagpole.z_index = 6
	add_child(flagpole)
	
	var hopscotch := _HopscotchDrawer.new(Vector2(footprint_size.x * 0.12, footprint_size.y * 0.22))
	hopscotch.z_index = 2
	add_child(hopscotch)

# ==============================================================================
# 9. PASSAGEM FERROVIÁRIA (RAIL UNDERPASS) — VÃO LIVRE SOBRE A RUA
# ==============================================================================
func _build_rail_underpass() -> void:
	# SEM piso solido no meio da rua: apenas os pilares laterais de sustentacao
	# e o fascial superior do viaduto com aviso de altura.
	var pillars := _UnderpassPillarsDrawer.new(footprint_size)
	pillars.z_index = 7
	add_child(pillars)
	
	var sign_node := ModularUrbanKit.create_neon_sign(
		Vector2(0, -footprint_size.y * 0.30),
		"ALTURA MÁX 4.2M",
		Color("#f5cd79"),
		10
	)
	sign_node.z_index = 9
	add_child(sign_node)
	
	var lamp_l := ModularUrbanKit.create_street_lamp(Vector2(-footprint_size.x * 0.42, 0), "halogen", Color("#f3a683"))
	var lamp_r := ModularUrbanKit.create_street_lamp(Vector2(footprint_size.x * 0.42, 0), "halogen", Color("#f3a683"))
	lamp_l.z_index = 10
	lamp_r.z_index = 10
	add_child(lamp_l)
	add_child(lamp_r)

# ==============================================================================
# FADE SUAVE QUANDO O JOGADOR PASSA SOB TOLDOS E MARQUISES (SEM COLISÃO SÓLIDA)
# ==============================================================================
func _setup_pass_through_fade() -> void:
	if landmark_type == LandmarkType.PARK_SPORTS or landmark_type == LandmarkType.RAIL_UNDERPASS:
		return
		
	var area := Area2D.new()
	area.name = "PassThroughArea"
	area.collision_layer = 0
	area.collision_mask = 1 | 2
	area.monitorable = false
	area.monitoring = true
	
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = footprint_size * 0.70
	col.shape = shape
	area.add_child(col)
	
	area.body_entered.connect(_on_pass_through_entered)
	area.body_exited.connect(_on_pass_through_exited)
	add_child(area)

func _on_pass_through_entered(body: Node2D) -> void:
	if body == null: return
	if body.is_in_group("player") or body.name == "Player" or body.get("is_driven_by_player") == true:
		_overlapping_actors += 1
		_fade_to(0.38)

func _on_pass_through_exited(body: Node2D) -> void:
	if body == null: return
	if body.is_in_group("player") or body.name == "Player" or body.get("is_driven_by_player") == true:
		_overlapping_actors = maxi(0, _overlapping_actors - 1)
		if _overlapping_actors == 0:
			_fade_to(1.0)

func _fade_to(target_alpha: float) -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_tween.tween_property(self, "modulate:a", target_alpha, 0.25)

func _connect_day_night() -> void:
	var dnm = get_tree().get_first_node_in_group("day_night_manager")
	if dnm and dnm.has_signal("time_changed"):
		dnm.connect("time_changed", Callable(self, "_on_day_night_changed"))
		_on_day_night_changed(bool(dnm.get("is_dark")))

func _on_day_night_changed(dark: bool) -> void:
	_is_night = dark
	for light in find_children("", "PointLight2D", true, false):
		var pl := light as PointLight2D
		if pl:
			pl.enabled = _is_night or pl.energy > 0.9

# ==============================================================================
# CLASSES AUXILIARES DE DESENHO VETORIAL PARA CADA EDIFÍCIO E MARCO
# ==============================================================================

class _BuildingRoofDrawer extends Node2D:
	var _size: Vector2
	var _c_top: Color
	var _c_edge: Color
	var _style: String
	func _init(s: Vector2, top: Color, edge: Color, style: String) -> void:
		_size = s
		_c_top = top
		_c_edge = edge
		_style = style
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5 + 6, -_size.y * 0.5 + 8, _size.x, _size.y), Color(0.08, 0.1, 0.12, 0.35), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), _c_edge, true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color(0.12, 0.14, 0.16), false, 2.0)
		var roof_inset := 6.0
		var r_top := Rect2(-_size.x * 0.5 + roof_inset, -_size.y * 0.5 + roof_inset, _size.x - roof_inset * 2.0, _size.y - roof_inset * 2.0)
		draw_rect(r_top, _c_top, true)
		draw_rect(r_top, _c_top.darkened(0.2), false, 1.5)
		
		if "zinc" in _style or "warehouse" in _style or "corrugated" in _style:
			var step := 12.0
			var num := int(r_top.size.x / step)
			for i in range(num):
				var x := r_top.position.x + float(i) * step
				draw_line(Vector2(x, r_top.position.y), Vector2(x, r_top.position.y + r_top.size.y), _c_top.darkened(0.18), 1.0)
		if "vents" in _style or "ac" in _style:
			draw_circle(Vector2(-r_top.size.x * 0.25, 0), 8.0, Color("#718093"))
			draw_circle(Vector2(-r_top.size.x * 0.25, 0), 3.0, Color("#2f3640"))
			draw_rect(Rect2(r_top.size.x * 0.15, -10, 22, 18), Color("#718093"), true)
		if "clock" in _style:
			draw_circle(Vector2(0, -r_top.size.y * 0.35), 7.0, Color.WHITE)
			draw_circle(Vector2(0, -r_top.size.y * 0.35), 7.0, Color.BLACK, false, 1.2)
			draw_line(Vector2(0, -r_top.size.y * 0.35), Vector2(0, -r_top.size.y * 0.35 - 4), Color.BLACK, 1.2)

class _CanopyDrawer extends Node2D:
	var _size: Vector2
	var _col: Color
	func _init(s: Vector2, c: Color) -> void:
		_size = s
		_col = c
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color(0.1, 0.1, 0.1, 0.3), true)
		draw_rect(Rect2(-_size.x * 0.5 - 2, -_size.y * 0.5 - 2, _size.x, _size.y), _col, true)
		draw_rect(Rect2(-_size.x * 0.5 - 2, -_size.y * 0.5 - 2, _size.x, _size.y), Color(0.15, 0.2, 0.25), false, 1.8)
		for i in range(4):
			var x := -_size.x * 0.5 + float(i) * (_size.x / 3.0)
			draw_line(Vector2(x, -_size.y * 0.5), Vector2(x, _size.y * 0.5), Color(0.1, 0.15, 0.2), 1.8)

class _MarketGroundDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#7f8c8d"), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#95a5a6"), false, 2.0)

class _TerminalGroundDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#34495e"), true)
		for i in range(2):
			var y := -_size.y * 0.2 + float(i) * 24.0
			draw_line(Vector2(0, y), Vector2(_size.x * 0.42, y), Color("#f1c40f"), 2.0)

class _ParkGroundDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#27ae60"), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#2ecc71"), false, 3.0)

class _BasketballCourtDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#d35400"), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color.WHITE, false, 1.8)
		draw_line(Vector2(0, -_size.y * 0.5), Vector2(0, _size.y * 0.5), Color.WHITE, 1.8)
		draw_circle(Vector2.ZERO, minf(_size.x, _size.y) * 0.20, Color.WHITE, false, 1.8)

class _GarageGroundDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#2c3e50"), true)

class _GarageBayDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#1e272e"), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#d2dae2"), false, 1.8)
		for i in range(4):
			var y := -_size.y * 0.5 + float(i * 6 + 3)
			draw_line(Vector2(-_size.x * 0.5 + 4, y), Vector2(_size.x * 0.5 - 4, y), Color("#485460"), 1.2)

class _TireStackDrawer extends Node2D:
	var _pos: Vector2
	func _init(p: Vector2) -> void:
		_pos = p
	func _draw() -> void:
		var offsets := [Vector2(0, 0), Vector2(12, 3), Vector2(6, -9)]
		for off in offsets:
			draw_circle(_pos + off, 6.5, Color("#1e272e"))
			draw_circle(_pos + off, 3.0, Color("#485460"))

class _ConcreteYardDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#3d3d3d"), true)

class _SidewalkTileDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#718093"), true)
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#2f3640"), false, 1.8)

class _BarTableDrawer extends Node2D:
	var _pos: Vector2
	func _init(p: Vector2) -> void:
		_pos = p
	func _draw() -> void:
		draw_circle(_pos, 12.0, Color("#e84118"))
		draw_circle(_pos, 12.0, Color.WHITE, false, 1.5)
		draw_circle(_pos, 5.0, Color("#f5f6fa"))
		draw_circle(_pos + Vector2(-9, 0), 2.5, Color("#2f3640"))
		draw_circle(_pos + Vector2(9, 0), 2.5, Color("#2f3640"))

class _LaundromatWindowDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, _size), Color(0.2, 0.8, 1.0, 0.35), true)
		draw_rect(Rect2(Vector2.ZERO, _size), Color("#00d2ff"), false, 1.8)
		var washer_w := 16.0
		var count := int(_size.x / washer_w)
		for i in range(count):
			var center := Vector2(float(i) * washer_w + washer_w * 0.5, _size.y * 0.5)
			draw_circle(center, 5.0, Color("#dcdde1"))
			draw_circle(center, 2.8, Color("#718093"))

class _SchoolGroundDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		draw_rect(Rect2(-_size.x * 0.5, -_size.y * 0.5, _size.x, _size.y), Color("#7f8c8d"), true)

class _FlagpoleDrawer extends Node2D:
	var _pos: Vector2
	func _init(p: Vector2) -> void:
		_pos = p
	func _draw() -> void:
		draw_circle(_pos, 4.0, Color("#2f3542"))
		draw_line(_pos, _pos + Vector2(0, -18), Color("#f1f2f6"), 2.0)
		draw_rect(Rect2(_pos + Vector2(0, -18), Vector2(11, 7)), Color("#2ed573"), true)

class _HopscotchDrawer extends Node2D:
	var _pos: Vector2
	func _init(p: Vector2) -> void:
		_pos = p
	func _draw() -> void:
		for i in range(4):
			draw_rect(Rect2(_pos + Vector2(0, float(i * 10)), Vector2(10, 9)), Color.WHITE, false, 1.2)

class _UnderpassPillarsDrawer extends Node2D:
	var _size: Vector2
	func _init(s: Vector2) -> void:
		_size = s
	func _draw() -> void:
		# Pilares laterais SEM cobrir a rua central
		var p_width := 20.0
		draw_rect(Rect2(-_size.x * 0.45, -_size.y * 0.45, p_width, _size.y * 0.9), Color("#57606f"), true)
		draw_rect(Rect2(_size.x * 0.45 - p_width, -_size.y * 0.45, p_width, _size.y * 0.9), Color("#57606f"), true)
		for y in range(int(-_size.y * 0.4), int(_size.y * 0.4), 16):
			draw_rect(Rect2(-_size.x * 0.45, float(y), p_width, 8), Color("#fbc531"), true)
			draw_rect(Rect2(_size.x * 0.45 - p_width, float(y), p_width, 8), Color("#fbc531"), true)
		# Viga de cobertura superior fina (fascia do viaduto)
		draw_rect(Rect2(-_size.x * 0.45, -_size.y * 0.45, _size.x * 0.9, 14), Color("#3d424a"), true)
