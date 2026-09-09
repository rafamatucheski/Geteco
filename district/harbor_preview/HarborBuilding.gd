@tool
extends "res://ProceduralBuilding.gd"

## Reuses the game's building vocabulary with real, footprint-bounded solids.
@export var business_name := ""
@export var accent := Color("#e4b76c")
@export var height_override: float = 0.0
@export var entrance_offset: float = 0.0
@export var entrance_north := false
const ENTRANCE_SCENE := preload("res://scripts/entrances/BuildingEntrance.tscn")
const ENTRANCE_SCRIPT := preload("res://district/harbor_preview/HarborEntrance.gd")
const L_MAIN_DEPTH := 0.55
const L_WING_WIDTH := 0.50

func _height_px() -> float:
	return height_override if height_override > 0.0 else super._height_px()

func _ready() -> void:
	super._ready()
	z_index = 5
	var body := StaticBody2D.new()
	body.name = "BuildingSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	for solid in get_solid_rects():
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = solid.size
		collision.shape = shape
		collision.position = solid.get_center()
		body.add_child(collision)
	add_child(body)
	_build_entrances()
	var mgr := get_tree().get_first_node_in_group("day_night_manager")
	if mgr and mgr.has_signal("time_changed"):
		mgr.connect("time_changed", func(_dark): queue_redraw())

func get_solid_rects() -> Array[Rect2]:
	if building_kind != "l_shaped_block":
		# Preserve every existing non-L building's collision exactly.
		return [Rect2(-footprint*0.5+Vector2.ONE,footprint-Vector2(2,2))]
	# Same inset and wing ratios as the visible L. The southwest courtyard is
	# intentionally empty, not part of a bounding-box invisible wall.
	var bounds := Rect2(-footprint*0.5,footprint).grow(-5)
	var main_depth := bounds.size.y*L_MAIN_DEPTH
	var wing_width := bounds.size.x*L_WING_WIDTH
	var solids: Array[Rect2] = [
		Rect2(bounds.position,Vector2(bounds.size.x,main_depth)),
		Rect2(bounds.position+Vector2(bounds.size.x-wing_width,main_depth),Vector2(wing_width,bounds.size.y-main_depth)),
	]
	if entrance_north:
		for i in solids.size():
			solids[i] = Rect2(-solids[i].end,solids[i].size)
	return solids

func _entrance_role() -> String:
	for role in ["garage", "police", "hospital", "fire_station", "ammunation", "morgue"]:
		if role in building_kind:
			return role
	return "morgue" if "iml" in building_kind else ""

func _build_entrances() -> void:
	var role := _entrance_role()
	if role.is_empty():
		return
	var count := 3 if role == "fire_station" else 1
	for i in count:
		var door := ENTRANCE_SCENE.instantiate()
		door.set_script(ENTRANCE_SCRIPT)
		door.name = "Entrance%d" % i if count > 1 else "Entrance"
		door.role = role
		door.entrance_kind = BuildingEntrance.EntranceKind.GARAGE if role in ["garage", "fire_station"] else (BuildingEntrance.EntranceKind.SHOP if role == "ammunation" else BuildingEntrance.EntranceKind.BUILDING)
		door.accent_color = accent
		door.door_width = {"garage": 120.0 if footprint.x > 300 else 112.0, "police": 54.0, "hospital": 64.0, "fire_station": 72.0, "ammunation": 58.0, "morgue": 60.0}[role]
		door.door_width = minf(door.door_width, footprint.x - 24)
		door.door_height = 36.0 if role in ["garage", "fire_station"] else 29.0
		var x := entrance_offset + (float(i - 1) * 90.0 if count == 3 else 0.0)
		door.position = Vector2(x, (-1.0 if entrance_north else 1.0) * (footprint.y / 2 - 5))
		door.rotation = PI if entrance_north else 0.0
		door.z_index = 1
		door.destination_id = StringName("harbor/%s/%s/%s" % [get_parent().name, name, door.name])
		door.display_name = ""
		add_child(door)

func _palette() -> Dictionary:
	var colors := super._palette()
	colors.accent = accent
	return colors

func _draw() -> void:
	if entrance_north:
		draw_set_transform(Vector2.ZERO, PI)

	var is_dark := false
	var is_rain := false
	var mgr := get_tree().get_first_node_in_group("day_night_manager")
	if mgr:
		is_dark = bool(mgr.get("is_dark"))
		if mgr.has_method("is_raining"):
			is_rain = mgr.is_raining()

	var bounds := Rect2(-footprint * 0.5, footprint).grow(-5)

	if building_kind == "corner_shop" or building_kind == "corner_diner":
		_draw_corner_shop(bounds, is_dark, is_rain)
	elif building_kind == "rowhouse_terrace":
		_draw_rowhouse_terrace(bounds, is_dark, is_rain)
	elif building_kind == "l_shaped_block":
		_draw_l_shaped_block(bounds, is_dark, is_rain)
	elif building_kind == "commercial_laundromat":
		_draw_laundromat(bounds, is_dark, is_rain)
	elif building_kind == "artisan_workshop":
		_draw_artisan_workshop(bounds, is_dark, is_rain)
	else:
		super._draw()


	draw_set_transform(Vector2.ZERO)

func _draw_corner_shop(bounds: Rect2, is_dark: bool, is_rain: bool) -> void:
	var height := 38.0
	var r := Rect2(bounds.position + Vector2(0, height), Vector2(bounds.size.x, bounds.size.y - height))
	var roof := Rect2(r.position + Vector2(0, -height), r.size)
	
	# Drop shadow
	draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0.04, 0.05, 0.08, 0.42))
	
	# Chamfered corner on SW (position.x, end.y)
	var chamfer := 32.0
	var r_poly := PackedVector2Array([
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x + chamfer, r.end.y),
		Vector2(r.position.x, r.end.y - chamfer)
	])
	var roof_poly := PackedVector2Array([
		roof.position,
		Vector2(roof.end.x, roof.position.y),
		roof.end,
		Vector2(roof.position.x + chamfer, roof.end.y),
		Vector2(roof.position.x, roof.end.y - chamfer)
	])
	
	# Extrusion facade walls
	draw_colored_polygon(PackedVector2Array([
		Vector2(roof.position.x, roof.end.y - chamfer),
		roof.position,
		r.position,
		Vector2(r.position.x, r.end.y - chamfer)
	]), Color("#6a4538"))
	
	draw_colored_polygon(PackedVector2Array([
		Vector2(roof.position.x + chamfer, roof.end.y),
		roof.end,
		r.end,
		Vector2(r.position.x + chamfer, r.end.y)
	]), Color("#875945"))
	
	# Chamfered corner wall facet (faces SW directly)
	draw_colored_polygon(PackedVector2Array([
		Vector2(roof.position.x, roof.end.y - chamfer),
		Vector2(roof.position.x + chamfer, roof.end.y),
		Vector2(r.position.x + chamfer, r.end.y),
		Vector2(r.position.x, r.end.y - chamfer)
	]), Color("#a06a52"))
	
	# Roof surface
	var roof_col := Color("#4c4441") if not is_rain else Color("#393838")
	draw_colored_polygon(roof_poly, roof_col)
	draw_polyline(roof_poly, Color("#262220"), 2.5)
	
	# Rain sheen on roof
	if is_rain:
		draw_line(roof.position + Vector2(15, 15), Vector2(roof.end.x - 20, roof.position.y + 15), Color(0.7, 0.85, 1.0, 0.22), 2.0)
		draw_line(roof.position + Vector2(25, 30), Vector2(roof.end.x - 40, roof.position.y + 30), Color(0.7, 0.85, 1.0, 0.15), 1.5)
	
	# Rooftop mechanical units
	var hvac_pos := roof.get_center() + Vector2(20, -12)
	draw_rect(Rect2(hvac_pos, Vector2(34, 24)), Color("#323538"))
	draw_rect(Rect2(hvac_pos + Vector2(2, 2), Vector2(30, 20)), Color("#50565a"))
	for y in range(4, 20, 4):
		draw_line(hvac_pos + Vector2(4, y), hvac_pos + Vector2(30, y), Color("#272a2c"), 1.5)
	
	# Grease extraction flue stack
	var flue_pos := roof.position + Vector2(45, 24)
	draw_circle(flue_pos + Vector2(3, 4), 11, Color(0.05, 0.05, 0.05, 0.35))
	draw_circle(flue_pos, 10, Color("#3a3e42"))
	draw_circle(flue_pos, 8, Color("#60666b"))
	draw_circle(flue_pos, 4, Color("#222426"))
	
	# Roof skylight
	draw_rect(Rect2(roof.position + Vector2(roof.size.x * 0.5 - 20, 15), Vector2(38, 20)), Color("#2d3336"))
	draw_rect(Rect2(roof.position + Vector2(roof.size.x * 0.5 - 18, 17), Vector2(34, 16)), Color("#59828e") if not is_dark else Color("#a87b32"))
	
	# Ground-level facade storefronts & windows
	var win_color := Color("#ffdd88") if is_dark else Color("#56848c")
	
	# South facade display windows
	var win_y := r.end.y - 28.0
	for wx in [r.position.x + chamfer + 16.0, r.position.x + chamfer + 62.0, r.position.x + chamfer + 108.0]:
		if wx + 36.0 < r.end.x - 8.0:
			draw_rect(Rect2(wx, win_y, 36, 22), Color("#211915"))
			draw_rect(Rect2(wx + 2, win_y + 2, 32, 18), win_color)
			draw_line(Vector2(wx + 18, win_y + 2), Vector2(wx + 18, win_y + 20), Color("#211915"), 1.5)
			if is_dark:
				# Pendant lamp glow inside
				draw_circle(Vector2(wx + 18, win_y + 7), 3, Color(1.0, 1.0, 0.8, 0.8))
	
	# Chamfered corner entrance door
	var door_c := (Vector2(r.position.x + chamfer, r.end.y) + Vector2(r.position.x, r.end.y - chamfer)) * 0.5
	draw_rect(Rect2(door_c - Vector2(10, 15), Vector2(20, 26)), Color("#2b1e19"))
	draw_rect(Rect2(door_c - Vector2(8, 13), Vector2(16, 22)), Color("#4a332a"))
	draw_rect(Rect2(door_c - Vector2(6, 11), Vector2(12, 12)), win_color)
	draw_circle(door_c + Vector2(4, 2), 2, Color("#d4aa50")) # Brass handle
	
	# Striped wraparound corner awning canopy
	var awning_p := PackedVector2Array([
		Vector2(r.position.x - 6, r.end.y - chamfer - 2),
		Vector2(r.position.x + chamfer + 8, r.end.y + 6),
		Vector2(r.position.x + chamfer + 4, r.end.y - 4),
		Vector2(r.position.x - 2, r.end.y - chamfer - 8)
	])
	draw_colored_polygon(awning_p, Color("#d97845"))
	for step in 5:
		var t0 := float(step) / 5.0
		var t1 := float(step + 0.5) / 5.0
		var pa := (awning_p[0] as Vector2).lerp(awning_p[1], t0)
		var pb := (awning_p[3] as Vector2).lerp(awning_p[2], t0)
		var pc := (awning_p[0] as Vector2).lerp(awning_p[1], t1)
		var pd := (awning_p[3] as Vector2).lerp(awning_p[2], t1)
		draw_colored_polygon(PackedVector2Array([pa, pb, pd, pc]), Color("#f4e8cf"))
	
	# Vintage retro roof emblem (replacing text "DINER" with iconic coffee cup diamond plaque)
	var sign_pos := Vector2(roof.position.x + 14, roof.end.y - chamfer + 4)
	var emblem := PackedVector2Array([
		sign_pos + Vector2(22, -8),
		sign_pos + Vector2(44, 1),
		sign_pos + Vector2(22, 10),
		sign_pos + Vector2(0, 1)
	])
	draw_colored_polygon(emblem, Color("#1f1f22"))
	var emblem_border := Color("#ff6b4a") if not is_dark else Color("#ff8866")
	draw_polyline(emblem, emblem_border, 1.5)
	# Coffee cup icon silhouette inside
	draw_rect(Rect2(sign_pos + Vector2(17, -2), Vector2(10, 6)), Color("#f4e8cf"))
	draw_arc(sign_pos + Vector2(27, 1), 3, -PI * 0.5, PI * 0.5, 8, Color("#f4e8cf"), 1.2)
	# Rising steam curls
	draw_line(sign_pos + Vector2(20, -3), sign_pos + Vector2(20, -6), Color("#ffd4a8"), 1.0)
	draw_line(sign_pos + Vector2(24, -3), sign_pos + Vector2(24, -6), Color("#ffd4a8"), 1.0)
	if is_dark:
		# Subtle, gentle neon halo (controlled, not overblown)
		draw_circle(sign_pos + Vector2(22, 1), 14, Color(1.0, 0.45, 0.2, 0.08))

func _draw_rowhouse_terrace(bounds: Rect2, is_dark: bool, is_rain: bool) -> void:
	var is_east := name.ends_with("East") or "East" in name
	var bay_w := bounds.size.x * 0.5
	
	# Four distinct unit profiles across West and East blocks
	var bays := []
	if not is_east:
		# FoundryTerraceWest: Units 0 & 1
		bays = [
			{
				"offset": 0.0, "w": bay_w - 4.0, "h": 42.0,
				"wall": Color("#7c463b"), "roof": Color("#343840"), "trim": Color("#b3967d"),
				"door_col": Color("#2d4a3b"), "door_transom": "fanlight", "stoop_prop": "flower_pot",
				"curtain_col": Color("#eae2cf"), "window_panes": 2, "chimney_flues": 2
			},
			{
				"offset": bay_w + 4.0, "w": bay_w - 4.0, "h": 46.0,
				"wall": Color("#685447"), "roof": Color("#38423f"), "trim": Color("#c4b29b"),
				"door_col": Color("#522527"), "door_transom": "square", "stoop_prop": "stone_rail",
				"curtain_col": Color("#c8b79b"), "window_panes": 6, "chimney_flues": 1
			}
		]
	else:
		# FoundryTerraceEast: Units 2 & 3
		bays = [
			{
				"offset": 0.0, "w": bay_w - 4.0, "h": 48.0,
				"wall": Color("#8e7a65"), "roof": Color("#3a3e46"), "trim": Color("#d4c3ae"),
				"door_col": Color("#26364d"), "door_transom": "fanlight", "stoop_prop": "bicycle",
				"curtain_col": Color("#f5ebd8"), "window_panes": 1, "chimney_flues": 2
			},
			{
				"offset": bay_w + 4.0, "w": bay_w - 4.0, "h": 43.0,
				"wall": Color("#78614e"), "roof": Color("#404642"), "trim": Color("#baa792"),
				"door_col": Color("#3a281c"), "door_transom": "arched", "stoop_prop": "milk_crate",
				"curtain_col": Color("#d8c19d"), "window_panes": 4, "chimney_flues": 1
			}
		]
	
	for bay in bays:
		var bx: float = bounds.position.x + bay.offset
		var bw: float = bay.w
		var bh: float = bay.h
		var by: float = bounds.position.y + bh
		var bsize_y: float = bounds.size.y - bh
		
		var r := Rect2(bx, by, bw, bsize_y)
		var roof := Rect2(bx, by - bh, bw, bsize_y)
		
		# Shadow
		draw_rect(Rect2(r.position + Vector2(7, 10), r.size), Color(0.04, 0.05, 0.08, 0.32))
		
		# Facade wall
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, bh), bay.wall)
		
		# Roof surface with subtle texture
		draw_rect(roof, bay.roof if not is_rain else bay.roof.darkened(0.12))
		draw_rect(roof, Color("#212529"), false, 1.5)
		
		# Roof cornice with dentil brackets
		var cornice_y := by
		draw_line(Vector2(bx - 2, cornice_y), Vector2(bx + bw + 2, cornice_y), bay.trim, 3.5)
		for dx in range(6, int(bw - 4), 14):
			draw_rect(Rect2(bx + dx, cornice_y - 2, 4, 5), bay.trim.darkened(0.2))
		
		# Chimney stack on party wall
		var chim_x := bx + bw - 14.0
		draw_rect(Rect2(chim_x, roof.position.y + 12, 12, 22), Color("#693e35"))
		draw_rect(Rect2(chim_x - 2, roof.position.y + 10, 16, 4), Color("#b0907c"))
		for c_idx in bay.chimney_flues:
			var pot_x := chim_x + 3.0 + float(c_idx) * 6.0
			draw_circle(Vector2(pot_x, roof.position.y + 10), 2.5, Color("#c77a58")) # Clay pot
		
		# Dormer on unit 3
		if bay.chimney_flues == 1 and is_east:
			var dormer_rect := Rect2(bx + 16, roof.position.y + 14, 18, 14)
			draw_rect(dormer_rect, Color("#3f4a47"))
			draw_rect(dormer_rect.grow(-2), Color("#2b3230"))
			draw_rect(Rect2(dormer_rect.position + Vector2(3, 3), Vector2(12, 8)), Color("#ffeaad") if is_dark else Color("#7f9da0"))
		
		# Windows with varied division, curtains and lighting
		var win_color := Color("#ffdd88") if is_dark else Color("#527a85")
		var floor1_y := r.position.y + 10.0
		for wx in [bx + 14.0, bx + bw - 44.0]:
			# Window lintel & sill
			draw_rect(Rect2(wx - 2, floor1_y - 4, 30, 4), bay.trim)
			draw_rect(Rect2(wx, floor1_y, 26, 20), Color("#1f2022"))
			draw_rect(Rect2(wx + 2, floor1_y + 2, 22, 16), win_color)
			# Curtains
			if not is_dark:
				draw_rect(Rect2(wx + 2, floor1_y + 2, 5, 16), bay.curtain_col)
				draw_rect(Rect2(wx + 19, floor1_y + 2, 5, 16), bay.curtain_col)
			# Sash divisions
			if bay.window_panes == 2:
				draw_line(Vector2(wx + 13, floor1_y + 2), Vector2(wx + 13, floor1_y + 18), Color("#211f20"), 1.2)
				draw_line(Vector2(wx + 2, floor1_y + 10), Vector2(wx + 24, floor1_y + 10), Color("#211f20"), 1.2)
			elif bay.window_panes == 6:
				draw_line(Vector2(wx + 9, floor1_y + 2), Vector2(wx + 9, floor1_y + 18), Color("#211f20"), 1.0)
				draw_line(Vector2(wx + 17, floor1_y + 2), Vector2(wx + 17, floor1_y + 18), Color("#211f20"), 1.0)
				draw_line(Vector2(wx + 2, floor1_y + 7), Vector2(wx + 24, floor1_y + 7), Color("#211f20"), 1.0)
				draw_line(Vector2(wx + 2, floor1_y + 13), Vector2(wx + 24, floor1_y + 13), Color("#211f20"), 1.0)
			draw_rect(Rect2(wx - 2, floor1_y + 20, 30, 3), bay.trim)
		
		# Authentic Brownstone Stoop (raised entrance stairs)
		var door_x := bx + (bw * 0.5) - 12.0
		var stoop_y := r.end.y - 32.0
		for s in 4:
			var sy := stoop_y + float(s) * 6.0
			var sw := 22.0 - float(s) * 1.5
			draw_rect(Rect2(door_x + (22.0 - sw) * 0.5, sy, sw, 5), Color("#a69f91"))
			draw_line(Vector2(door_x, sy), Vector2(door_x + 22, sy), Color("#c7c1b3"), 1.0)
		draw_rect(Rect2(door_x - 4, stoop_y, 4, 24), Color("#7b7468"))
		draw_rect(Rect2(door_x + 22, stoop_y, 4, 24), Color("#7b7468"))
		# Entry door with distinctive color
		draw_rect(Rect2(door_x + 2, stoop_y - 18, 18, 20), Color("#261c16"))
		draw_rect(Rect2(door_x + 4, stoop_y - 16, 14, 18), bay.door_col)
		# Transom light
		if bay.door_transom == "fanlight":
			draw_circle(Vector2(door_x + 11, stoop_y - 16), 4, win_color)
		else:
			draw_rect(Rect2(door_x + 5, stoop_y - 18, 12, 4), win_color)
		draw_circle(Vector2(door_x + 11, stoop_y - 8), 1.5, Color("#d9b252")) # Door handle
		
		# Stoop occupation prop
		if bay.stoop_prop == "flower_pot":
			# Potted fern/flower on landing
			draw_rect(Rect2(door_x - 8, stoop_y + 2, 6, 6), Color("#c47854"))
			draw_circle(Vector2(door_x - 5, stoop_y + 2), 4, Color("#487349"))
		elif bay.stoop_prop == "bicycle":
			# Slender commuter bicycle leaning on railing
			var bike_p := Vector2(door_x - 8, stoop_y + 12)
			draw_circle(bike_p + Vector2(0, 4), 3, Color("#26292b"), false, 1.2)
			draw_circle(bike_p + Vector2(8, 4), 3, Color("#26292b"), false, 1.2)
			draw_line(bike_p + Vector2(0, 4), bike_p + Vector2(4, 0), Color("#3e5771"), 1.2)
			draw_line(bike_p + Vector2(4, 0), bike_p + Vector2(8, 4), Color("#3e5771"), 1.2)
		elif bay.stoop_prop == "milk_crate":
			# Morning milk crate / parcel
			draw_rect(Rect2(door_x + 24, stoop_y + 4, 6, 6), Color("#baa788"))
			draw_rect(Rect2(door_x + 25, stoop_y + 5, 4, 4), Color("#dfd7c8"))


func _draw_l_shaped_block(bounds: Rect2, is_dark: bool, is_rain: bool) -> void:
	var height := 44.0
	# L-shape: Main Wing occupies north, East Wing extends south
	var main_w := bounds.size.x
	var main_d := bounds.size.y * L_MAIN_DEPTH
	var wing_w := bounds.size.x * L_WING_WIDTH
	var wing_x := bounds.position.x + (main_w - wing_w)
	var wing_y := bounds.position.y + main_d
	var wing_d := bounds.size.y - main_d
	
	# Drop shadows
	draw_rect(Rect2(bounds.position + Vector2(10, height + 12), Vector2(main_w, main_d - height)), Color(0.04, 0.05, 0.08, 0.38))
	draw_rect(Rect2(Vector2(wing_x + 10, wing_y + height + 12), Vector2(wing_w, wing_d - height)), Color(0.04, 0.05, 0.08, 0.38))
	
	# Main wing volumes
	var r_main := Rect2(bounds.position.x, bounds.position.y + height, main_w, main_d - height)
	var roof_main := Rect2(bounds.position.x, bounds.position.y, main_w, main_d - height)
	draw_rect(r_main, Color("#755749")) # Brick facade
	draw_rect(roof_main, Color("#47423f"))
	draw_rect(roof_main, Color("#262220"), false, 2.0)
	
	# East wing volumes
	var r_wing := Rect2(wing_x, wing_y + height, wing_w, wing_d - height)
	var roof_wing := Rect2(wing_x, wing_y, wing_w, wing_d - height)
	draw_rect(r_wing, Color("#6e5043"))
	draw_rect(roof_wing, Color("#443f3c"))
	draw_rect(roof_wing, Color("#262220"), false, 2.0)
	
	# Rooftop Water Tower on Main Wing
	var wt_pos := roof_main.position + Vector2(35, 20)
	# Steel trestle legs
	draw_line(wt_pos + Vector2(4, 30), wt_pos + Vector2(12, 10), Color("#272c30"), 2.0)
	draw_line(wt_pos + Vector2(32, 30), wt_pos + Vector2(24, 10), Color("#272c30"), 2.0)
	draw_line(wt_pos + Vector2(8, 30), wt_pos + Vector2(28, 10), Color("#272c30"), 1.5)
	draw_line(wt_pos + Vector2(28, 30), wt_pos + Vector2(8, 10), Color("#272c30"), 1.5)
	# Wooden water tank cylinder
	draw_rect(Rect2(wt_pos + Vector2(6, 2), Vector2(24, 18)), Color("#634e3f"))
	# Metal hoops
	for hy in [5, 10, 16]:
		draw_line(wt_pos + Vector2(6, hy), wt_pos + Vector2(30, hy), Color("#26282b"), 1.5)
	# Conical roof cap
	draw_colored_polygon(PackedVector2Array([
		wt_pos + Vector2(4, 2),
		wt_pos + Vector2(32, 2),
		wt_pos + Vector2(18, -7)
	]), Color("#45372d"))
	
	# Loft Crittall multi-pane windows
	var win_color := Color("#ffd984") if is_dark else Color("#557d87")
	for wx in [bounds.position.x + 18.0, bounds.position.x + 65.0, bounds.position.x + 112.0]:
		var wy := r_main.position.y + 8.0
		draw_rect(Rect2(wx, wy, 34, 22), Color("#1c2022"))
		draw_rect(Rect2(wx + 2, wy + 2, 30, 18), win_color)
		# 3x3 Crittall grid
		draw_line(Vector2(wx + 12, wy + 2), Vector2(wx + 12, wy + 20), Color("#1c2022"), 1.5)
		draw_line(Vector2(wx + 22, wy + 2), Vector2(wx + 22, wy + 20), Color("#1c2022"), 1.5)
		draw_line(Vector2(wx + 2, wy + 8), Vector2(wx + 32, wy + 8), Color("#1c2022"), 1.5)
		draw_line(Vector2(wx + 2, wy + 14), Vector2(wx + 32, wy + 14), Color("#1c2022"), 1.5)
	
	# Courtyard loading dock doors on the recessed facade
	var dock_x := wing_x + 12.0
	var dock_y := r_wing.end.y - 28.0
	draw_rect(Rect2(dock_x, dock_y, 40, 24), Color("#26292b"))
	draw_rect(Rect2(dock_x + 2, dock_y + 2, 17, 20), Color("#546654"))
	draw_rect(Rect2(dock_x + 21, dock_y + 2, 17, 20), Color("#546654"))
	draw_line(Vector2(dock_x + 20, dock_y + 2), Vector2(dock_x + 20, dock_y + 22), Color("#1c1e20"), 2.0)

func _draw_laundromat(bounds: Rect2, is_dark: bool, is_rain: bool) -> void:
	var height := 36.0
	var r := Rect2(bounds.position + Vector2(0, height), Vector2(bounds.size.x, bounds.size.y - height))
	var roof := Rect2(r.position + Vector2(0, -height), r.size)
	
	# Drop shadow
	draw_rect(Rect2(r.position + Vector2(8, 12), r.size), Color(0.04, 0.05, 0.08, 0.38))
	
	# Facade wall: pale celadon plaster with glazed seafoam subway tile wainscot
	draw_rect(r, Color("#bccac7"))
	draw_rect(Rect2(r.position.x, r.end.y - 18, r.size.x, 18), Color("#2a4e52"))
	
	# Roof surface and parapet
	var roof_col := Color("#414447") if not is_rain else Color("#323538")
	draw_rect(roof, roof_col)
	draw_rect(roof, Color("#222527"), false, 2.0)
	if is_rain:
		draw_line(roof.position + Vector2(10, 12), Vector2(roof.end.x - 10, roof.position.y + 12), Color(0.7, 0.85, 1.0, 0.2), 1.5)
	
	# Rooftop dryer exhaust vents
	var vent1 := roof.position + Vector2(30, 22)
	draw_circle(vent1 + Vector2(2, 3), 9, Color(0.05, 0.05, 0.05, 0.3))
	draw_circle(vent1, 8, Color("#555c61"))
	draw_circle(vent1, 5, Color("#7b858c"))
	draw_circle(vent1, 2, Color("#282b2d"))
	var vent2 := roof.position + Vector2(58, 22)
	draw_circle(vent2 + Vector2(2, 3), 9, Color(0.05, 0.05, 0.05, 0.3))
	draw_circle(vent2, 8, Color("#555c61"))
	draw_circle(vent2, 5, Color("#7b858c"))
	draw_circle(vent2, 2, Color("#282b2d"))
	
	# Commercial HVAC / condenser box
	var ac_pos := roof.get_center() + Vector2(14, -6)
	draw_rect(Rect2(ac_pos, Vector2(28, 20)), Color("#3b4044"))
	draw_rect(Rect2(ac_pos + Vector2(2, 2), Vector2(24, 16)), Color("#565d63"))
	for ly in range(4, 16, 4):
		draw_line(ac_pos + Vector2(4, ly), ac_pos + Vector2(24, ly), Color("#272a2c"), 1.2)
	
	# Storefront display window showing front-load washing machines
	var win_color := Color("#d6f2f7") if not is_dark else Color("#ffea9f")
	var win_rect := Rect2(r.position.x + 14, r.end.y - 34, 92, 26)
	draw_rect(win_rect, Color("#181e20"))
	draw_rect(win_rect.grow(-2), win_color.darkened(0.1))
	for m in 3:
		var mx := win_rect.position.x + 16.0 + float(m) * 28.0
		var my := win_rect.position.y + 13.0
		draw_rect(Rect2(mx - 11, my - 10, 22, 20), Color("#eef5f4"))
		draw_rect(Rect2(mx - 11, my - 10, 22, 20), Color("#7a8f91"), false, 1.0)
		draw_circle(Vector2(mx, my), 7.5, Color("#445254"))
		draw_circle(Vector2(mx, my), 6.5, Color("#889ea0"))
		draw_circle(Vector2(mx, my), 5.0, Color("#3a728a") if not is_dark else Color("#d49842"))
		draw_arc(Vector2(mx, my), 3.5, 0.2, 1.8, 6, Color(1, 1, 1, 0.6), 1.2)
	
	# Commercial glazed entry door
	var door_x := r.end.x - 44.0
	var door_y := r.end.y - 36.0
	draw_rect(Rect2(door_x, door_y, 30, 34), Color("#20282b"))
	draw_rect(Rect2(door_x + 2, door_y + 2, 26, 30), Color("#324447"))
	draw_rect(Rect2(door_x + 4, door_y + 4, 22, 18), win_color)
	draw_line(Vector2(door_x + 8, door_y + 22), Vector2(door_x + 8, door_y + 28), Color("#d4d9db"), 2.0)
	
	# Drop Awning Canopy in turquoise and cream stripes
	var awn_p := PackedVector2Array([
		Vector2(r.position.x + 8, r.end.y - 28),
		Vector2(r.end.x - 8, r.end.y - 28),
		Vector2(r.end.x - 4, r.end.y - 18),
		Vector2(r.position.x + 4, r.end.y - 18)
	])
	draw_colored_polygon(awn_p, Color("#244a5e"))
	for s in 10:
		if s % 2 == 1:
			var t0 := float(s) / 10.0
			var t1 := float(s + 1) / 10.0
			var p0: Vector2 = awn_p[0].lerp(awn_p[1], t0)
			var p1: Vector2 = awn_p[0].lerp(awn_p[1], t1)
			var p2: Vector2 = awn_p[3].lerp(awn_p[2], t1)
			var p3: Vector2 = awn_p[3].lerp(awn_p[2], t0)
			draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]), Color("#f0ede6"))
	
	if is_dark:
		draw_circle(win_rect.get_center(), 20.0, Color(1.0, 0.9, 0.6, 0.08))

func _draw_artisan_workshop(bounds: Rect2, is_dark: bool, is_rain: bool) -> void:
	var height := 40.0
	var r := Rect2(bounds.position + Vector2(0, height), Vector2(bounds.size.x, bounds.size.y - height))
	var roof := Rect2(r.position + Vector2(0, -height), r.size)
	
	# Drop shadow
	draw_rect(Rect2(r.position + Vector2(10, 14), r.size), Color(0.04, 0.05, 0.08, 0.40))
	
	# Weathered brick facade with piers
	draw_rect(r, Color("#693e32"))
	draw_rect(Rect2(r.position.x, r.position.y, 14, r.size.y), Color("#563025"))
	draw_rect(Rect2(r.position.x + 92, r.position.y, 14, r.size.y), Color("#563025"))
	draw_rect(Rect2(r.end.x - 14, r.position.y, 14, r.size.y), Color("#563025"))
	draw_rect(Rect2(r.position.x, r.end.y - 38, r.size.x, 6), Color("#baa995"))
	
	# Roof surface with sawtooth monitor skylight
	var roof_col := Color("#3a3c3d") if not is_rain else Color("#2e3030")
	draw_rect(roof, roof_col)
	draw_rect(roof, Color("#1f2021"), false, 2.0)
	
	var sm_rect := Rect2(roof.position.x + 30, roof.position.y + 12, roof.size.x - 60, 24)
	draw_rect(sm_rect, Color("#2c2d30"))
	var sm_glass := sm_rect.grow(-3)
	var win_craft_col := Color("#507682") if not is_dark else Color("#e0ab55")
	draw_rect(sm_glass, Color("#4c6670") if not is_dark else Color("#b88a44"))
	for gx in range(int(sm_glass.position.x + 12), int(sm_glass.end.x), 16):
		draw_line(Vector2(gx, sm_glass.position.y), Vector2(gx, sm_glass.end.y), Color("#222326"), 1.5)
	
	# Timber double carriage doors with iron strap hinges
	var door_rect := Rect2(r.position.x + 18, r.end.y - 32, 70, 30)
	draw_rect(door_rect, Color("#261c16"))
	draw_rect(Rect2(door_rect.position.x + 2, door_rect.position.y + 2, 31, 26), Color("#473225"))
	draw_rect(Rect2(door_rect.position.x + 37, door_rect.position.y + 2, 31, 26), Color("#473225"))
	for hy in [door_rect.position.y + 7, door_rect.position.y + 21]:
		draw_line(Vector2(door_rect.position.x + 2, hy), Vector2(door_rect.position.x + 22, hy), Color("#1b1b1c"), 2.0)
		draw_line(Vector2(door_rect.end.x - 2, hy), Vector2(door_rect.end.x - 22, hy), Color("#1b1b1c"), 2.0)
		draw_circle(Vector2(door_rect.position.x + 4, hy), 2.0, Color("#1b1b1c"))
		draw_circle(Vector2(door_rect.end.x - 4, hy), 2.0, Color("#1b1b1c"))
	draw_circle(Vector2(door_rect.position.x + 30, door_rect.position.y + 15), 2.0, Color("#a89052"), false, 1.2)
	draw_circle(Vector2(door_rect.position.x + 40, door_rect.position.y + 15), 2.0, Color("#a89052"), false, 1.2)
	
	# Industrial craft / display window
	var craft_win := Rect2(r.position.x + 110, r.end.y - 32, 66, 30)
	draw_rect(craft_win, Color("#1e1e20"))
	draw_rect(craft_win.grow(-2), win_craft_col)
	draw_line(Vector2(craft_win.position.x + 22, craft_win.position.y + 2), Vector2(craft_win.position.x + 22, craft_win.end.y - 2), Color("#1e1e20"), 1.5)
	draw_line(Vector2(craft_win.position.x + 44, craft_win.position.y + 2), Vector2(craft_win.position.x + 44, craft_win.end.y - 2), Color("#1e1e20"), 1.5)
	draw_line(Vector2(craft_win.position.x + 2, craft_win.position.y + 15), Vector2(craft_win.end.x - 2, craft_win.position.y + 15), Color("#1e1e20"), 1.5)
	if is_dark:
		draw_circle(craft_win.get_center() + Vector2(0, -4), 4.0, Color(1.0, 1.0, 0.8, 0.85))
		draw_circle(craft_win.get_center(), 18.0, Color(1.0, 0.7, 0.3, 0.10))
	else:
		draw_rect(Rect2(craft_win.position.x + 6, craft_win.end.y - 10, 54, 8), Color("#2a1f18"))
	
	# Clerestory transoms
	for cx in [r.position.x + 28, r.position.x + 120]:
		var cl_rect := Rect2(cx, r.position.y + 6, 44, 16)
		draw_rect(cl_rect, Color("#1e1e20"))
		draw_rect(cl_rect.grow(-2), win_craft_col.darkened(0.15))
		draw_line(Vector2(cx + 22, cl_rect.position.y + 2), Vector2(cx + 22, cl_rect.end.y - 2), Color("#1e1e20"), 1.2)
		draw_line(Vector2(cl_rect.position.x + 2, cl_rect.position.y + 8), Vector2(cl_rect.end.x - 2, cl_rect.position.y + 8), Color("#1e1e20"), 1.2)

func _draw_bold_iml_letters(_at: Vector2, _col: Color, _shadow_col: Color) -> void:
	pass

func _draw_garage_doors(_facade: Rect2, _door_color: Color) -> void:
	# The animated child replaces the old painted shutters.
	pass

func _draw_police_identity(_roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	var center := Vector2(facade.get_center().x, facade.position.y + 6)
	draw_colored_polygon(PackedVector2Array([center + Vector2(-12, -8), center + Vector2(12, -8), center + Vector2(10, 5), center + Vector2(0, 14), center + Vector2(-10, 5)]), p.accent)
	draw_circle(center, 3, Color("#d9edf1"))
	for side in [-1, 1]:
		draw_rect(Rect2(facade.get_center().x + side * 40 - 10, facade.position.y + 4, 20, 4), p.accent if side < 0 else Color("#d9edf1"))

func _draw_fire_station_identity(_roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	draw_rect(Rect2(facade.position + Vector2(4, 3), Vector2(facade.size.x - 8, 5)), p.accent)
	var center := facade.get_center() + Vector2(0, -15)
	draw_line(center + Vector2(-9, -6), center + Vector2(9, 6), Color("#f0d97e"), 3)
	draw_line(center + Vector2(-9, 6), center + Vector2(9, -6), Color("#f0d97e"), 3)

func _draw_ammunation_identity(_roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	draw_rect(Rect2(facade.position + Vector2(4, 3), Vector2(facade.size.x - 8, 8)), p.edge)
	var icon := facade.get_center() + Vector2(0, -14)
	draw_rect(Rect2(icon - Vector2(4, 5), Vector2(8, 12)), Color("#d8ad45"))
	draw_colored_polygon(PackedVector2Array([icon + Vector2(-4, -5), icon + Vector2(4, -5), icon + Vector2(0, -12)]), p.accent)
