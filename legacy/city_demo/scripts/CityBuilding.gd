@tool
class_name DemoCityBuilding
extends StaticBody2D

enum Archetype {
	SKYSCRAPER,
	MEDIUM_APARTMENT,
	COMMERCIAL_SHOP,
	SUBURBAN_HOUSE,
	WAREHOUSE,
	PARK_PLAZA,
	CUSTOM
}

enum RoofStyle {
	FLAT_PARAPET,
	TAR_GRAVEL,
	PITCHED_GABLE,
	CORRUGATED_CURVED,
	PLAZA_TILES,
	CUSTOM
}

const BUILDING_ATLAS: Texture2D = preload("res://assets/art/building-atlas.png")
const TREE_TEXTURE: Texture2D = preload("res://assets/art/tree-street-small.png")
const SHRUB_TEXTURE: Texture2D = preload("res://assets/art/shrub-cluster.png")

# --- ARCHETYPE & GENERAL PROPERTIES ---
@export var archetype: Archetype = Archetype.MEDIUM_APARTMENT:
	set(value):
		archetype = value
		_apply_archetype_defaults()
		_update_building()

@export_range(0, 23, 1) var variant: int = 0:
	set(v):
		variant = v
		_update_building()

@export var visual_width: float = 168.0:
	set(w):
		visual_width = maxf(w, 40.0)
		_update_building()

@export var visual_height: float = 0.0:
	set(h):
		visual_height = maxf(h, 0.0)
		_update_building()

@export var rooftop_height: float = 120.0:
	set(h):
		rooftop_height = maxf(h, 0.0)
		_update_building()

@export var footprint: Vector2 = Vector2(142.0, 78.0):
	set(f):
		footprint = f
		_update_building()

@export var collider_offset: Vector2 = Vector2.ZERO:
	set(o):
		collider_offset = o
		_update_building()

@export var is_passable: bool = false:
	set(p):
		is_passable = p
		_update_building()

@export var tint: Color = Color.WHITE:
	set(t):
		tint = t
		_update_building()

@export var roof_color: Color = Color(0.32, 0.34, 0.38):
	set(rc):
		roof_color = rc
		_update_building()

@export var roof_style: RoofStyle = RoofStyle.FLAT_PARAPET:
	set(rs):
		roof_style = rs
		_update_building()

# --- SIGNAGE ---
@export_group("Signage")
@export var building_title: String = "":
	set(text):
		building_title = text
		_update_sign()

@export var sign_color: Color = Color.WHITE:
	set(sc):
		sign_color = sc
		_update_sign()

# --- ROOFTOP PROPS ---
@export_group("Rooftop Props")
@export var has_helipad: bool = false:
	set(val):
		has_helipad = val
		queue_redraw()

@export var has_antenna: bool = false:
	set(val):
		has_antenna = val
		queue_redraw()

@export var has_water_tower: bool = false:
	set(val):
		has_water_tower = val
		queue_redraw()

@export var has_hvac_units: bool = true:
	set(val):
		has_hvac_units = val
		queue_redraw()

@export var has_solar_panels: bool = false:
	set(val):
		has_solar_panels = val
		queue_redraw()

@export var has_chimney: bool = false:
	set(val):
		has_chimney = val
		queue_redraw()

@export var has_roof_access: bool = true:
	set(val):
		has_roof_access = val
		queue_redraw()

@export var has_exhaust_vents: bool = false:
	set(val):
		has_exhaust_vents = val
		queue_redraw()

# --- FACADE & GROUND PROPS ---
@export_group("Facade & Ground Props")
@export var has_awning: bool = false:
	set(val):
		has_awning = val
		queue_redraw()

@export var awning_color: Color = Color(0.85, 0.22, 0.22):
	set(val):
		awning_color = val
		queue_redraw()

@export var has_cargo_doors: bool = false:
	set(val):
		has_cargo_doors = val
		queue_redraw()

@export var has_fountain: bool = false:
	set(val):
		has_fountain = val
		_update_props()
		queue_redraw()

@export var has_park_benches: bool = false:
	set(val):
		has_park_benches = val
		queue_redraw()

@export var has_planters: bool = false:
	set(val):
		has_planters = val
		_update_props()
		queue_redraw()

@export var has_trees: bool = false:
	set(val):
		has_trees = val
		_update_props()
		queue_redraw()

@export var has_night_lighting: bool = true:
	set(val):
		has_night_lighting = val
		queue_redraw()

# Internal nodes
var visual: Sprite2D
var collision: CollisionShape2D
var obstacle_collision: CollisionShape2D
var sign_label: Label
var props_container: Node2D

var _beacon_timer: float = 0.0
var _water_anim_timer: float = 0.0

func _ready() -> void:
	_update_building()
	add_to_group("city_building")

func _process(delta: float) -> void:
	var needs_redraw := false
	if has_antenna and has_night_lighting:
		_beacon_timer += delta * 2.5
		needs_redraw = true
	if has_fountain:
		_water_anim_timer += delta * 3.0
		needs_redraw = true
	if needs_redraw:
		queue_redraw()

func _apply_archetype_defaults() -> void:
	match archetype:
		Archetype.SKYSCRAPER:
			visual_width = 210.0
			visual_height = 360.0
			rooftop_height = 280.0
			footprint = Vector2(185.0, 90.0)
			is_passable = false
			tint = Color("e0ecf8")
			roof_color = Color("2c3540")
			roof_style = RoofStyle.FLAT_PARAPET
			has_helipad = true
			has_antenna = true
			has_water_tower = false
			has_hvac_units = true
			has_solar_panels = false
			has_chimney = false
			has_roof_access = true
			has_exhaust_vents = false
			has_awning = false
			has_cargo_doors = false
			has_fountain = false
			has_park_benches = false
			has_planters = false
			has_trees = false

		Archetype.MEDIUM_APARTMENT:
			visual_width = 168.0
			visual_height = 240.0
			rooftop_height = 140.0
			footprint = Vector2(142.0, 78.0)
			is_passable = false
			tint = Color("f5efe6")
			roof_color = Color("3e4247")
			roof_style = RoofStyle.TAR_GRAVEL
			has_helipad = false
			has_antenna = false
			has_water_tower = true
			has_hvac_units = true
			has_solar_panels = false
			has_chimney = false
			has_roof_access = true
			has_exhaust_vents = false
			has_awning = false
			has_cargo_doors = false
			has_fountain = false
			has_park_benches = false
			has_planters = false
			has_trees = false

		Archetype.COMMERCIAL_SHOP:
			visual_width = 110.0
			visual_height = 130.0
			rooftop_height = 70.0
			footprint = Vector2(96.0, 68.0)
			is_passable = false
			tint = Color("faf0e6")
			roof_color = Color("50535a")
			roof_style = RoofStyle.FLAT_PARAPET
			has_helipad = false
			has_antenna = false
			has_water_tower = false
			has_hvac_units = true
			has_solar_panels = false
			has_chimney = false
			has_roof_access = false
			has_exhaust_vents = true
			has_awning = true
			awning_color = Color("c93b2b")
			has_cargo_doors = false
			has_fountain = false
			has_park_benches = false
			has_planters = true
			has_trees = false

		Archetype.SUBURBAN_HOUSE:
			visual_width = 92.0
			visual_height = 100.0
			rooftop_height = 60.0
			footprint = Vector2(80.0, 64.0)
			is_passable = false
			tint = Color("fdfbf7")
			roof_color = Color("8c432d")
			roof_style = RoofStyle.PITCHED_GABLE
			has_helipad = false
			has_antenna = false
			has_water_tower = false
			has_hvac_units = false
			has_solar_panels = true
			has_chimney = true
			has_roof_access = false
			has_exhaust_vents = false
			has_awning = false
			has_cargo_doors = false
			has_fountain = false
			has_park_benches = false
			has_planters = true
			has_trees = true

		Archetype.WAREHOUSE:
			visual_width = 260.0
			visual_height = 140.0
			rooftop_height = 80.0
			footprint = Vector2(230.0, 86.0)
			is_passable = false
			tint = Color("dbe1e8")
			roof_color = Color("68717a")
			roof_style = RoofStyle.CORRUGATED_CURVED
			has_helipad = false
			has_antenna = false
			has_water_tower = false
			has_hvac_units = false
			has_solar_panels = true
			has_chimney = false
			has_roof_access = false
			has_exhaust_vents = true
			has_awning = false
			has_cargo_doors = true
			has_fountain = false
			has_park_benches = false
			has_planters = false
			has_trees = false

		Archetype.PARK_PLAZA:
			visual_width = 220.0
			visual_height = 180.0
			rooftop_height = 0.0
			footprint = Vector2(200.0, 160.0)
			is_passable = true
			tint = Color("6b9e59")
			roof_color = Color("7fa668")
			roof_style = RoofStyle.PLAZA_TILES
			has_helipad = false
			has_antenna = false
			has_water_tower = false
			has_hvac_units = false
			has_solar_panels = false
			has_chimney = false
			has_roof_access = false
			has_exhaust_vents = false
			has_awning = false
			has_cargo_doors = false
			has_fountain = true
			has_park_benches = true
			has_planters = true
			has_trees = true

		Archetype.CUSTOM:
			pass

func _update_building() -> void:
	if visual == null:
		visual = get_node_or_null("Visual") as Sprite2D
		if visual == null:
			visual = Sprite2D.new()
			visual.name = "Visual"
			add_child(visual)

	if collision == null:
		collision = get_node_or_null("Collision") as CollisionShape2D
		if collision == null:
			collision = CollisionShape2D.new()
			collision.name = "Collision"
			add_child(collision)

	var calculated_height := visual_height
	if calculated_height <= 0.0:
		var uniform_scale := visual_width / 418.0
		calculated_height = 627.0 * uniform_scale

	if archetype == Archetype.PARK_PLAZA:
		visual.visible = false
	else:
		visual.visible = true
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = BUILDING_ATLAS
		atlas_texture.region = Rect2(float((variant % 4) * 418), float(int(variant / 4.0) * 627), 418.0, 627.0)
		visual.texture = atlas_texture
		var uniform_scale := visual_width / 418.0
		visual.scale = Vector2(uniform_scale, (calculated_height / 627.0) if visual_height > 0.0 else uniform_scale)
		visual.position = Vector2(0.0, -calculated_height * 0.5)
		visual.modulate = tint

	# Configure Footprint Collision
	if is_passable:
		collision.disabled = true
		if has_fountain:
			if obstacle_collision == null:
				obstacle_collision = get_node_or_null("ObstacleCollision") as CollisionShape2D
				if obstacle_collision == null:
					obstacle_collision = CollisionShape2D.new()
					obstacle_collision.name = "ObstacleCollision"
					add_child(obstacle_collision)
			var circle := CircleShape2D.new()
			circle.radius = 24.0
			obstacle_collision.shape = circle
			obstacle_collision.position = Vector2(0.0, -footprint.y * 0.45)
			obstacle_collision.disabled = false
		elif obstacle_collision != null:
			obstacle_collision.disabled = true
	else:
		collision.disabled = false
		if obstacle_collision != null:
			obstacle_collision.disabled = true
		var rectangle := RectangleShape2D.new()
		var fp_size := footprint
		if fp_size.x <= 0.0:
			fp_size.x = visual_width * 0.85
		if fp_size.y <= 0.0:
			fp_size.y = 80.0
		rectangle.size = fp_size
		collision.shape = rectangle
		var base_y := -fp_size.y * 0.5
		collision.position = Vector2(collider_offset.x, base_y + collider_offset.y)

	_update_sign()
	_update_props()
	queue_redraw()

func _update_sign() -> void:
	if building_title.is_empty():
		if sign_label != null:
			sign_label.visible = false
		return

	if sign_label == null:
		sign_label = get_node_or_null("SignLabel") as Label
		if sign_label == null:
			sign_label = Label.new()
			sign_label.name = "SignLabel"
			add_child(sign_label)

	sign_label.visible = true
	sign_label.text = building_title
	var sign_w := minf(visual_width * 0.9, 160.0)
	sign_label.size = Vector2(sign_w, 22)
	sign_label.position = Vector2(-sign_w * 0.5, 6)
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sign_label.add_theme_font_size_override("font_size", 10)
	sign_label.add_theme_color_override("font_outline_color", Color.BLACK)
	sign_label.add_theme_constant_override("outline_size", 3)

	var col := sign_color
	if "AMMU" in building_title.to_upper():
		col = Color("f4d35e")
	elif "DELEGACIA" in building_title.to_upper() or "POLICIA" in building_title.to_upper():
		col = Color("72b8ff")
	elif "HOSPITAL" in building_title.to_upper() or "MEDICO" in building_title.to_upper():
		col = Color("7df1a4")
	elif "BOMBEIRO" in building_title.to_upper() or "FIRE" in building_title.to_upper():
		col = Color("ff6b6b")
	elif "AUTO" in building_title.to_upper() or "GARAGEM" in building_title.to_upper():
		col = Color("f9a03f")
	sign_label.add_theme_color_override("font_color", col)

func _update_props() -> void:
	if props_container == null:
		props_container = get_node_or_null("PropsContainer") as Node2D
		if props_container == null:
			props_container = Node2D.new()
			props_container.name = "PropsContainer"
			props_container.z_index = 1
			add_child(props_container)

	for child in props_container.get_children():
		child.queue_free()

	if archetype == Archetype.PARK_PLAZA or has_trees:
		var tree_coords := [
			Vector2(-visual_width * 0.38, -visual_height * 0.75),
			Vector2(visual_width * 0.38, -visual_height * 0.75),
			Vector2(-visual_width * 0.38, -visual_height * 0.15),
			Vector2(visual_width * 0.38, -visual_height * 0.15)
		]
		for pos in tree_coords:
			var tree_spr := Sprite2D.new()
			tree_spr.texture = TREE_TEXTURE
			tree_spr.position = pos
			var s := 0.055
			tree_spr.scale = Vector2(s, s)
			props_container.add_child(tree_spr)

	if archetype == Archetype.PARK_PLAZA or has_planters:
		var shrub_coords := [
			Vector2(-visual_width * 0.2, -visual_height * 0.82),
			Vector2(visual_width * 0.2, -visual_height * 0.82),
			Vector2(-visual_width * 0.2, -visual_height * 0.10),
			Vector2(visual_width * 0.2, -visual_height * 0.10)
		]
		for pos in shrub_coords:
			var shrub_spr := Sprite2D.new()
			shrub_spr.texture = SHRUB_TEXTURE
			shrub_spr.position = pos
			var s := 0.040
			shrub_spr.scale = Vector2(s, s)
			props_container.add_child(shrub_spr)

func _draw() -> void:
	var calculated_height := visual_height
	if calculated_height <= 0.0:
		var uniform_scale := visual_width / 418.0
		calculated_height = 627.0 * uniform_scale

	var roof_y := -calculated_height
	var roof_rect := Rect2(-visual_width * 0.48, roof_y, visual_width * 0.96, visual_width * 0.40)

	# 1. PARK PLAZA PROCEDURAL GROUND
	if archetype == Archetype.PARK_PLAZA:
		_draw_park_plaza(calculated_height)
		return

	# 2. ROOF BASE & PARAPET
	if archetype != Archetype.PARK_PLAZA:
		_draw_rooftop_surface(roof_rect)

	# 3. ROOF PROPS
	if has_helipad:
		_draw_helipad(roof_rect.get_center())

	if has_water_tower:
		_draw_water_tower(Vector2(roof_rect.position.x + roof_rect.size.x * 0.78, roof_rect.get_center().y))

	if has_hvac_units:
		_draw_hvac_units(roof_rect)

	if has_antenna:
		_draw_antenna(Vector2(roof_rect.position.x + roof_rect.size.x * 0.2, roof_rect.position.y - 4))

	if has_solar_panels:
		_draw_solar_panels(roof_rect)

	if has_chimney:
		_draw_chimney(Vector2(roof_rect.end.x - 14, roof_rect.position.y + 6))

	if has_roof_access:
		_draw_roof_access(Vector2(roof_rect.get_center().x - 16, roof_rect.position.y + 6))

	if has_exhaust_vents:
		_draw_exhaust_vents(roof_rect)

	# 4. FACADE PROPS
	if has_awning:
		_draw_awning(Vector2(0.0, -12), visual_width * 0.75)

	if has_cargo_doors:
		_draw_cargo_doors(Vector2(0.0, -10), visual_width * 0.85)

func _draw_rooftop_surface(rect: Rect2) -> void:
	match roof_style:
		RoofStyle.FLAT_PARAPET:
			# Parapet border
			draw_rect(rect, roof_color.darkened(0.35))
			var inner := rect.grow(-4.0)
			draw_rect(inner, roof_color)
			# Gravel grid texture lines
			var step := 16.0
			var x := inner.position.x + step
			while x < inner.end.x:
				draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), roof_color.darkened(0.12), 1.0)
				x += step
			var y := inner.position.y + step
			while y < inner.end.y:
				draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), roof_color.darkened(0.12), 1.0)
				y += step

		RoofStyle.TAR_GRAVEL:
			draw_rect(rect, roof_color.darkened(0.4))
			var inner := rect.grow(-3.0)
			draw_rect(inner, roof_color)
			# Tar seams
			draw_line(Vector2(inner.position.x, inner.get_center().y), Vector2(inner.end.x, inner.get_center().y), roof_color.darkened(0.3), 2.0)

		RoofStyle.PITCHED_GABLE:
			# Roof ridge
			var left_half := Rect2(rect.position.x, rect.position.y, rect.size.x * 0.5, rect.size.y)
			var right_half := Rect2(rect.position.x + rect.size.x * 0.5, rect.position.y, rect.size.x * 0.5, rect.size.y)
			draw_rect(left_half, roof_color.lightened(0.1))
			draw_rect(right_half, roof_color.darkened(0.15))
			draw_line(Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y), Color("f5e1c8"), 2.5)

		RoofStyle.CORRUGATED_CURVED:
			draw_rect(rect, roof_color)
			var step := 8.0
			var x := rect.position.x + step
			while x < rect.end.x:
				draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), roof_color.lightened(0.15), 1.5)
				draw_line(Vector2(x + 2, rect.position.y), Vector2(x + 2, rect.end.y), roof_color.darkened(0.2), 1.5)
				x += step

		_:
			draw_rect(rect, roof_color)

func _draw_helipad(center: Vector2) -> void:
	var radius := minf(visual_width * 0.16, 26.0)
	draw_circle(center, radius + 2.0, Color("1f2329"))
	draw_circle(center, radius, Color("2d333b"))
	draw_arc(center, radius - 3.0, 0, TAU, 32, Color("e5c07b"), 2.0)
	var h_size := radius * 0.55
	var h_col := Color.WHITE
	draw_line(center + Vector2(-h_size * 0.5, -h_size), center + Vector2(-h_size * 0.5, h_size), h_col, 3.5)
	draw_line(center + Vector2(h_size * 0.5, -h_size), center + Vector2(h_size * 0.5, h_size), h_col, 3.5)
	draw_line(center + Vector2(-h_size * 0.5, 0), center + Vector2(h_size * 0.5, 0), h_col, 3.5)
	for i in range(4):
		var angle := i * (PI / 2.0) + (PI / 4.0)
		var p := center + Vector2(cos(angle), sin(angle)) * (radius - 1.0)
		draw_circle(p, 2.5, Color("f9d71c"))

func _draw_water_tower(pos: Vector2) -> void:
	var r := 12.0
	draw_line(pos + Vector2(-r, r), pos + Vector2(-r * 1.3, r * 1.5), Color(0.1, 0.1, 0.1, 0.7), 2.0)
	draw_line(pos + Vector2(r, r), pos + Vector2(r * 1.3, r * 1.5), Color(0.1, 0.1, 0.1, 0.7), 2.0)
	draw_circle(pos, r + 1.0, Color("3b2f2f"))
	draw_circle(pos, r, Color("8b5a2b"))
	draw_circle(pos, r * 0.6, Color("6b4226"))
	draw_arc(pos, r, 0, TAU, 24, Color("4a4a4a"), 2.0)
	draw_circle(pos, 3.0, Color("2f2f2f"))

func _draw_hvac_units(rect: Rect2) -> void:
	var unit_w := 18.0
	var unit_h := 14.0
	var pos := Vector2(rect.position.x + 10.0, rect.get_center().y - unit_h * 0.5)
	draw_rect(Rect2(pos, Vector2(unit_w, unit_h)), Color("64748b"))
	draw_rect(Rect2(pos + Vector2(2, 2), Vector2(unit_w - 4, unit_h - 4)), Color("475569"))
	draw_circle(pos + Vector2(unit_w * 0.5, unit_h * 0.5), 4.0, Color("334155"))
	draw_line(pos + Vector2(unit_w * 0.5 - 3, unit_h * 0.5), pos + Vector2(unit_w * 0.5 + 3, unit_h * 0.5), Color("94a3b8"), 1.0)
	draw_line(pos + Vector2(unit_w * 0.5, unit_h * 0.5 - 3), pos + Vector2(unit_w * 0.5, unit_h * 0.5 + 3), Color("94a3b8"), 1.0)

	if rect.size.x > 120.0:
		var pos2 := Vector2(pos.x + unit_w + 6.0, pos.y)
		draw_rect(Rect2(pos2, Vector2(unit_w, unit_h)), Color("64748b"))
		draw_rect(Rect2(pos2 + Vector2(2, 2), Vector2(unit_w - 4, unit_h - 4)), Color("475569"))
		draw_circle(pos2 + Vector2(unit_w * 0.5, unit_h * 0.5), 4.0, Color("334155"))
		draw_line(pos2 + Vector2(unit_w * 0.5 - 3, unit_h * 0.5), pos2 + Vector2(unit_w * 0.5 + 3, unit_h * 0.5), Color("94a3b8"), 1.0)
		draw_line(pos2 + Vector2(unit_w * 0.5, unit_h * 0.5 - 3), pos2 + Vector2(unit_w * 0.5, unit_h * 0.5 + 3), Color("94a3b8"), 1.0)

func _draw_antenna(pos: Vector2) -> void:
	var mast_len := 38.0
	draw_line(pos, pos + Vector2(0, -mast_len), Color("d1d5db"), 2.0)
	draw_line(pos + Vector2(-6, -mast_len * 0.6), pos + Vector2(6, -mast_len * 0.6), Color("9ca3af"), 1.5)
	draw_line(pos + Vector2(-4, -mast_len * 0.85), pos + Vector2(4, -mast_len * 0.85), Color("9ca3af"), 1.5)
	var is_lit := int(_beacon_timer) % 2 == 0
	var beacon_col := Color("ff3333") if is_lit else Color("661111")
	draw_circle(pos + Vector2(0, -mast_len - 2), 3.5, beacon_col)
	if is_lit:
		draw_circle(pos + Vector2(0, -mast_len - 2), 7.0, Color(1.0, 0.2, 0.2, 0.35))

func _draw_solar_panels(rect: Rect2) -> void:
	var panel_w := 28.0
	var panel_h := 16.0
	var start_x := rect.position.x + 8.0
	var y := rect.position.y + 6.0
	while start_x + panel_w < rect.end.x - 8.0:
		var panel_rect := Rect2(start_x, y, panel_w, panel_h)
		draw_rect(panel_rect, Color("1e3a8a"))
		draw_rect(panel_rect, Color("93c5fd"), false, 1.0)
		draw_line(Vector2(panel_rect.position.x + panel_w * 0.5, panel_rect.position.y), Vector2(panel_rect.position.x + panel_w * 0.5, panel_rect.end.y), Color("60a5fa"), 1.0)
		draw_line(Vector2(panel_rect.position.x, panel_rect.position.y + panel_h * 0.5), Vector2(panel_rect.end.x, panel_rect.position.y + panel_h * 0.5), Color("60a5fa"), 1.0)
		start_x += panel_w + 6.0

func _draw_chimney(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x - 5, pos.y - 8, 10, 14), Color("854d0e"))
	draw_rect(Rect2(pos.x - 7, pos.y - 11, 14, 3), Color("3f3f46"))
	draw_circle(pos + Vector2(0, -9), 2.5, Color("18181b"))

func _draw_roof_access(pos: Vector2) -> void:
	draw_rect(Rect2(pos.x, pos.y, 16, 12), Color("334155"))
	draw_rect(Rect2(pos.x + 2, pos.y + 2, 5, 8), Color("1e293b"))
	draw_circle(pos + Vector2(6, 6), 1.0, Color("fbbf24"))

func _draw_exhaust_vents(rect: Rect2) -> void:
	var vent_count := 3
	for i in range(vent_count):
		var t := float(i + 1) / float(vent_count + 1)
		var vx := rect.position.x + rect.size.x * t
		var vy := rect.get_center().y
		draw_circle(Vector2(vx, vy), 5.0, Color("94a3b8"))
		draw_circle(Vector2(vx, vy), 3.5, Color("475569"))
		draw_line(Vector2(vx - 2, vy), Vector2(vx + 2, vy), Color("cbd5e1"), 1.0)

func _draw_awning(pos: Vector2, width: float) -> void:
	var awning_h := 16.0
	var half_w := width * 0.5
	var start_x := pos.x - half_w
	var stripe_w := 12.0
	var count := int(width / stripe_w)
	for i in range(count):
		var sx := start_x + i * stripe_w
		var col := awning_color if i % 2 == 0 else Color.WHITE
		draw_rect(Rect2(sx, pos.y, stripe_w, awning_h), col)
		draw_line(Vector2(sx, pos.y + awning_h), Vector2(sx + stripe_w, pos.y + awning_h), col.darkened(0.25), 2.0)
	draw_line(Vector2(start_x, pos.y + awning_h + 1), Vector2(start_x + width, pos.y + awning_h + 1), Color(0, 0, 0, 0.4), 2.0)

func _draw_cargo_doors(pos: Vector2, width: float) -> void:
	var door_w := minf(width * 0.4, 70.0)
	var door_h := 28.0
	var left_door := Rect2(pos.x - door_w - 6, pos.y - door_h, door_w, door_h)
	var right_door := Rect2(pos.x + 6, pos.y - door_h, door_w, door_h)
	for d in [left_door, right_door]:
		draw_rect(d, Color("475569"))
		var step: float = 4.0
		var ly: float = d.position.y + step
		while ly < d.end.y:
			draw_line(Vector2(d.position.x, ly), Vector2(d.end.x, ly), Color("64748b"), 1.0)
			ly += step
		var hazard_w: float = 6.0
		var hx: float = d.position.x
		var hz_idx: int = 0
		while hx < d.end.x:
			var hcol := Color("eab308") if hz_idx % 2 == 0 else Color("1e293b")
			draw_rect(Rect2(hx, d.position.y - 4, minf(hazard_w, d.end.x - hx), 4), hcol)
			hx += hazard_w
			hz_idx += 1

func _draw_park_plaza(height: float) -> void:
	var w: float = visual_width
	var h: float = height
	var plaza_rect := Rect2(-w * 0.5, -h, w, h)

	# 1. Paved outer promenade (Stone tiles)
	draw_rect(plaza_rect, Color("94a3b8"))
	var curb_inset: float = 8.0
	var inner_plaza := plaza_rect.grow(-curb_inset)
	draw_rect(inner_plaza, Color("cbd5e1"))

	var step: float = 24.0
	var px: float = inner_plaza.position.x + step
	while px < inner_plaza.end.x:
		draw_line(Vector2(px, inner_plaza.position.y), Vector2(px, inner_plaza.end.y), Color("94a3b8"), 1.0)
		px += step
	var py: float = inner_plaza.position.y + step
	while py < inner_plaza.end.y:
		draw_line(Vector2(inner_plaza.position.x, py), Vector2(inner_plaza.end.x, py), Color("94a3b8"), 1.0)
		py += step

	# 2. Central Lush Green Lawn
	var lawn_margin := 32.0
	var lawn_rect := inner_plaza.grow(-lawn_margin)
	draw_rect(lawn_rect, Color("4d7c0f"))
	draw_rect(lawn_rect.grow(-4.0), Color("65a30d"))

	# 3. Central Fountain
	if has_fountain:
		var center := lawn_rect.get_center()
		draw_circle(center, 24.0, Color("475569"))
		draw_circle(center, 22.0, Color("94a3b8"))
		draw_circle(center, 19.0, Color("0284c7"))
		var ripple_r := 6.0 + fmod(_water_anim_timer * 6.0, 12.0)
		draw_arc(center, ripple_r, 0, TAU, 32, Color(0.7, 0.9, 1.0, 0.6), 1.5)
		var ripple_r2 := 6.0 + fmod((_water_anim_timer + 1.0) * 6.0, 12.0)
		draw_arc(center, ripple_r2, 0, TAU, 32, Color(0.7, 0.9, 1.0, 0.4), 1.0)
		draw_circle(center, 6.0, Color("cbd5e1"))
		draw_circle(center, 3.5, Color.WHITE)

	# 4. Park Benches
	if has_park_benches:
		var center := lawn_rect.get_center()
		var bench_dist := 44.0
		var bench_positions := [
			Vector2(center.x - bench_dist, center.y),
			Vector2(center.x + bench_dist, center.y),
			Vector2(center.x, center.y - bench_dist),
			Vector2(center.x, center.y + bench_dist)
		]
		for bpos in bench_positions:
			var bw := 20.0
			var bh := 6.0
			draw_rect(Rect2(bpos.x - bw * 0.5, bpos.y - bh * 0.5, bw, bh), Color("78350f"))
			draw_rect(Rect2(bpos.x - bw * 0.5, bpos.y - bh * 0.5, bw, bh), Color("3f3f46"), false, 1.0)
