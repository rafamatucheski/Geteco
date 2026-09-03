class_name ProceduralBuilding
extends Node2D

## Cartoony 2.5D building made entirely from Godot drawing primitives.
## It is deliberately not a raster sprite: the roof, façade, windows and
## mechanical units stay crisp at any lot size and can later be animated.

@export var footprint := Vector2(180, 150)
@export var building_kind := "commercial"
@export var variant_seed := 0

func _ready() -> void:
	# `LotBuildings` lives above actors so façades can occlude them. A park is
	# ground art, therefore cancel that inherited elevation and keep actors,
	# birds and props visibly above its paving.
	if "park" in building_kind:
		z_index = -19
	queue_redraw()

func _palette() -> Dictionary:
	# POIs come first because their kind names also contain generic words such
	# as `shop`.  This keeps their identity deterministic and unmistakable.
	if "ammunation" in building_kind:
		return {"roof": Color("#292c31"), "edge": Color("#111419"), "front": Color("#4a3030"), "accent": Color("#d4483f"), "window": Color("#7f9aa0"), "mortar": Color("#342326")}
	if "clothing" in building_kind:
		return {"roof": Color("#49364f"), "edge": Color("#241d2a"), "front": Color("#6e506c"), "accent": Color("#53b0a3"), "window": Color("#91c9c4"), "mortar": Color("#513d52")}
	if "hospital" in building_kind:
		return {"roof": Color("#86989a"), "edge": Color("#40545b"), "front": Color("#aebfbd"), "accent": Color("#4ca1ac"), "window": Color("#7fc4cb"), "mortar": Color("#748789")}
	if "morgue" in building_kind or "iml" in building_kind:
		return {"roof": Color("#181d24"), "edge": Color("#090b0d"), "front": Color("#2b3e50"), "accent": Color("#8e44ad"), "window": Color("#4a6572"), "mortar": Color("#19222d")}
	if "fire_station" in building_kind or "firehouse" in building_kind:
		return {"roof": Color("#3d3332"), "edge": Color("#1e1b1c"), "front": Color("#75413a"), "accent": Color("#d7503f"), "window": Color("#8da9aa"), "mortar": Color("#4f302d")}
	if "police_precinct" in building_kind:
		return {"roof": Color("#263a50"), "edge": Color("#101e30"), "front": Color("#4f6878"), "accent": Color("#4ba4d8"), "window": Color("#a8dce2"), "mortar": Color("#344f63")}
	if "police_substation" in building_kind:
		return {"roof": Color("#36414b"), "edge": Color("#1b2730"), "front": Color("#647078"), "accent": Color("#76a9bf"), "window": Color("#afd6d5"), "mortar": Color("#465960")}
	if "police" in building_kind:
		return {"roof": Color("#344558"), "edge": Color("#172334"), "front": Color("#586d7c"), "accent": Color("#3b91c1"), "window": Color("#9bc9d0"), "mortar": Color("#405567")}
	if "warehouse" in building_kind:
		return {"roof": Color("#4e5151"), "edge": Color("#282c2e"), "front": Color("#6f6258"), "accent": Color("#b58a42"), "window": Color("#2f4248"), "mortar": Color("#514842")}
	if "garage" in building_kind:
		return {"roof": Color("#665047"), "edge": Color("#352a29"), "front": Color("#806c5e"), "accent": Color("#c69a43"), "window": Color("#2d373b"), "mortar": Color("#59483f")}
	if "park" in building_kind:
		return {"roof": Color("#526f55"), "edge": Color("#293f30"), "front": Color("#78936d"), "accent": Color("#c2c879"), "window": Color("#426554"), "mortar": Color("#60775a")}
	if "corner_shop" in building_kind or "shop" in building_kind:
		var shop_palettes := [
			{"roof": Color("#673a3e"), "edge": Color("#321f28"), "front": Color("#986849"), "accent": Color("#d4a947"), "window": Color("#477d83"), "mortar": Color("#704b3d")},
			{"roof": Color("#405653"), "edge": Color("#243230"), "front": Color("#786d56"), "accent": Color("#c59045"), "window": Color("#4e858d"), "mortar": Color("#5b5548")},
		]
		return shop_palettes[posmod(variant_seed, shop_palettes.size())]
	if "rowhouse" in building_kind or "brownstone" in building_kind:
		var brick_palettes := [
			{"roof": Color("#513b3a"), "edge": Color("#2c2527"), "front": Color("#75483e"), "accent": Color("#ae8252"), "window": Color("#567e83"), "mortar": Color("#593a35")},
			{"roof": Color("#484346"), "edge": Color("#29272b"), "front": Color("#685a50"), "accent": Color("#9e8056"), "window": Color("#587783"), "mortar": Color("#50463f")},
			{"roof": Color("#3f494c"), "edge": Color("#252c30"), "front": Color("#59666a"), "accent": Color("#a78250"), "window": Color("#537b86"), "mortar": Color("#465357")},
		]
		return brick_palettes[posmod(variant_seed, brick_palettes.size())]
	if "office" in building_kind:
		return {"roof": Color("#455258"), "edge": Color("#252f34"), "front": Color("#6f7977"), "accent": Color("#a89358"), "window": Color("#5b8998"), "mortar": Color("#586361")}
	return {"roof": Color("#5a4840"), "edge": Color("#302824"), "front": Color("#776354"), "accent": Color("#b3955c"), "window": Color("#537d87"), "mortar": Color("#5e5045")}

func _height_px() -> float:
	# Screen-space extrusion: readable height in a top-down, cartoony world.
	if "hospital" in building_kind:
		return 72.0
	if "morgue" in building_kind or "iml" in building_kind:
		return 58.0
	if "police_precinct" in building_kind:
		return 82.0
	if "police_substation" in building_kind:
		return 64.0
	if "police" in building_kind:
		return 76.0
	if "fire_station" in building_kind or "firehouse" in building_kind:
		return 64.0
	if "garage" in building_kind:
		return 46.0
	if "park" in building_kind:
		return 0.0
	if "ammunation" in building_kind:
		return 42.0
	if "clothing" in building_kind:
		return 38.0
	if "corner_shop" in building_kind or "shop" in building_kind:
		return 32.0
	if "rowhouse" in building_kind or "brownstone" in building_kind:
		return 40.0
	if "office" in building_kind:
		return 58.0
	return clampf(footprint.y * 0.30, 36.0, 52.0)

func get_collision_rect() -> Rect2:
	# `footprint` is the complete visible bounds.  The roof extrusion is drawn
	# inside it, keeping collision out of the surrounding sidewalk.
	var bounds := Rect2(-footprint * 0.5, footprint).grow(-1)
	return Rect2(global_position + bounds.position, bounds.size)

func _draw() -> void:
	var p := _palette()
	var bounds := Rect2(-footprint * 0.5, footprint).grow(-5)
	# Parks are terrain, not short buildings.  The old code extruded the lot and
	# placed four green circles on its roof, which read as trees growing from a
	# building.  A paved pocket plaza makes the intention legible at once.
	if "park" in building_kind:
		_draw_park_plaza(bounds)
		return
	var height := minf(_height_px(), bounds.size.y * 0.62)
	# Reserve the height within the lot, rather than pushing a roof out through
	# the north sidewalk.  The base sits at the lower part of its own bounds.
	var r := Rect2(bounds.position + Vector2(0, height), Vector2(bounds.size.x, bounds.size.y - height))
	var roof_base := r.grow(-7)
	var roof := Rect2(roof_base.position + Vector2(0, -height), roof_base.size)
	# The footprint remains on the ground; the roof is lifted above it.  This
	# makes each building a volume rather than a flat stamp.
	draw_rect(Rect2(r.position + Vector2(12, 15), r.size), Color(0.05, 0.07, 0.10, 0.46))
	draw_rect(r, p.edge)
	_draw_extruded_facades(r, roof, p)
	draw_rect(roof, p.roof)
	_draw_roof_surface(roof, p)
	draw_rect(roof.grow(-4), p.edge, false, 2.0)
	_draw_roof_detail(roof, p)
	_draw_upper_volume(roof, p)
	# Street-facing awning and repeated windows establish a human scale.
	var facade := Rect2(r.position.x + 6, r.end.y - minf(height, r.size.y * 0.70) - 6, r.size.x - 12, minf(height, r.size.y * 0.70))
	draw_rect(Rect2(facade.position, Vector2(facade.size.x, 5)), p.accent)
	if "garage" in building_kind:
		_draw_garage_identity(roof, facade, p)
	if "hospital" in building_kind:
		_draw_hospital_roof(roof, p.accent)
	if "police" in building_kind:
		_draw_police_identity(roof, facade, p)
	if "fire_station" in building_kind or "firehouse" in building_kind:
		_draw_fire_station_identity(roof, facade, p)
	if "ammunation" in building_kind:
		_draw_ammunation_identity(roof, facade, p)
	elif "clothing" in building_kind:
		_draw_clothing_identity(roof, facade, p)
	elif "shop" in building_kind:
		_draw_storefront(facade, p.accent)
	_draw_facade_material(facade, p)
	if "corner_shop" in building_kind:
		_draw_corner_front(facade, p)

func _draw_roof_surface(roof: Rect2, p: Dictionary) -> void:
	# Small, deterministic marks keep roofs authored-looking without texture noise.
	var inner := roof.grow(-8)
	if inner.size.x <= 20 or inner.size.y <= 20:
		return
	if "warehouse" in building_kind:
		var bay_count := maxi(2, int(inner.size.x / 42.0))
		var bay_width := inner.size.x / float(bay_count)
		for i in bay_count:
			var bay_x := inner.position.x + bay_width * i
			draw_line(Vector2(bay_x, inner.position.y), Vector2(bay_x, inner.end.y), p.edge.lightened(0.08), 2.0)
			var skylight := Rect2(bay_x + 7, inner.position.y + 10, maxf(10.0, bay_width - 14), 10)
			draw_rect(skylight, Color("#50646a"))
			draw_rect(skylight, Color("#252e32"), false, 1.0)
		return
	# Tar seams and repaired patches suit the darker GTA-like urban roofs.
	for stripe in range(1, maxi(2, int(inner.size.y / 34.0))):
		var y := inner.position.y + stripe * 32.0
		if y < inner.end.y:
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), p.edge.lightened(0.08), 1.0)
	var patch_w := minf(34.0, inner.size.x * 0.22)
	var patch := Rect2(inner.position + Vector2(inner.size.x * 0.12, inner.size.y * 0.62), Vector2(patch_w, 9))
	draw_rect(patch, p.edge.lightened(0.10))
	draw_rect(patch, p.edge.darkened(0.12), false, 1.0)

func _draw_facade_material(facade: Rect2, p: Dictionary) -> void:
	if "rowhouse" in building_kind or "brownstone" in building_kind:
		# Chunky brick courses: readable at gameplay zoom, not photorealistic.
		for y in range(int(facade.position.y + 4), int(facade.end.y - 4), 8):
			draw_line(Vector2(facade.position.x + 3, y), Vector2(facade.end.x - 3, y), p.mortar, 1.0)
			var offset := 7 if int(y / 8) % 2 == 0 else 15
			for x in range(int(facade.position.x + offset), int(facade.end.x - 3), 22):
				draw_line(Vector2(x, y - 8), Vector2(x, y), p.mortar, 1.0)
	elif "office" in building_kind or "hospital" in building_kind or "police" in building_kind:
		for x in range(int(facade.position.x + 22), int(facade.end.x - 8), 34):
			draw_line(Vector2(x, facade.position.y + 5), Vector2(x, facade.end.y - 3), p.mortar, 1.0)
	if not ("garage" in building_kind or "warehouse" in building_kind or "park" in building_kind):
		var sill_y := facade.end.y - 9
		draw_line(Vector2(facade.position.x + 4, sill_y), Vector2(facade.end.x - 4, sill_y), p.edge.darkened(0.20), 2.0)

func _draw_corner_front(facade: Rect2, p: Dictionary) -> void:
	# A wraparound canopy makes corner buildings distinct from a repeated row.
	var canopy_y := facade.position.y + 17
	draw_line(Vector2(facade.position.x - 5, canopy_y), Vector2(facade.end.x + 5, canopy_y), p.accent, 7.0)
	draw_line(Vector2(facade.end.x + 2, canopy_y), Vector2(facade.end.x + 2, facade.end.y - 3), p.accent.darkened(0.25), 4.0)

func _draw_upper_volume(roof: Rect2, p: Dictionary) -> void:
	if not ("hospital" in building_kind or "police" in building_kind or "office" in building_kind):
		return
	var annex_size := Vector2(roof.size.x * 0.34, roof.size.y * 0.23)
	var annex := Rect2(roof.position + Vector2(roof.size.x * 0.54, roof.size.y * 0.16), annex_size)
	draw_rect(Rect2(annex.position + Vector2(4, 5), annex.size), Color(0.06, 0.08, 0.10, 0.36))
	draw_rect(annex, p.edge)
	draw_rect(annex.grow(-3), p.roof.lightened(0.10))
	draw_rect(annex.grow(-3), p.edge, false, 1.5)

func _draw_extruded_facades(base: Rect2, roof: Rect2, p: Dictionary) -> void:
	# South façade: the visible wall between the elevated roof and pavement.
	var south := PackedVector2Array([
		Vector2(roof.position.x, roof.end.y), Vector2(roof.end.x, roof.end.y),
		Vector2(base.end.x, base.end.y), Vector2(base.position.x, base.end.y)
	])
	draw_colored_polygon(south, p.front)
	# East edge gets a darker wall, making the roof read as elevated.
	var east := PackedVector2Array([
		Vector2(roof.end.x, roof.position.y), Vector2(base.end.x, base.position.y),
		Vector2(base.end.x, base.end.y), Vector2(roof.end.x, roof.end.y)
	])
	draw_colored_polygon(east, p.edge.darkened(0.18))
	var rows := maxi(1, int(_height_px() / 14.0))
	for row in rows:
		var y := roof.end.y + 7 + row * 13
		if y + 7 >= base.end.y - 3:
			break
		for x in range(int(base.position.x + 14), int(base.end.x - 12), 26):
			draw_rect(Rect2(x, y, 14, 7), p.window)
			draw_rect(Rect2(x, y, 14, 7), Color("#233b47"), false, 1.0)

func _draw_roof_detail(roof: Rect2, p: Dictionary) -> void:
	if "ammunation" in building_kind:
		_draw_ammunation_roof(roof, p)
		return
	if "garage" in building_kind:
		_draw_garage_roof(roof, p)
		return
	if "clothing" in building_kind:
		_draw_clothing_roof(roof, p)
		return
	if "hospital" in building_kind:
		_draw_hospital_roof(roof, p.accent)
		return
	if "morgue" in building_kind or "iml" in building_kind:
		_draw_morgue_roof(roof, p)
		return
	if "police" in building_kind:
		_draw_police_roof(roof, p.accent)
		return
	if "fire_station" in building_kind or "firehouse" in building_kind:
		_draw_fire_station_roof(roof, p)
		return
	if "rowhouse" in building_kind or "brownstone" in building_kind:
		_draw_water_tank(roof.get_center() + Vector2(0, -8))
		return
	if "corner_shop" in building_kind:
		draw_rect(Rect2(roof.position + Vector2(12, 12), Vector2(roof.size.x * 0.44, 10)), p.accent.darkened(0.12))
		return
	if "park" in building_kind:
		return
	var unit_size := Vector2(clampf(roof.size.x * 0.15, 14, 25), clampf(roof.size.y * 0.13, 12, 20))
	var count := 1 + (variant_seed % 3)
	for i in count:
		var span_x := maxf(20.0, roof.size.x - unit_size.x - 22)
		var span_y := maxf(16.0, roof.size.y - unit_size.y - 22)
		var at := Vector2(roof.position.x + 14 + fmod(float(i) * (unit_size.x + 12), span_x), roof.position.y + 14 + fmod(float(i * 19), span_y))
		draw_rect(Rect2(at, unit_size), Color("#58616a"))
		draw_rect(Rect2(at + Vector2(3, 3), unit_size - Vector2(6, 6)), Color("#8c9695"), false, 1.5)

func _draw_water_tank(at: Vector2) -> void:
	draw_rect(Rect2(at - Vector2(10, 8), Vector2(20, 16)), Color("#44545a"))
	draw_circle(at + Vector2(0, -8), 10, Color("#718077"))
	draw_line(at + Vector2(-7, 8), at + Vector2(-10, 17), Color("#2d3537"), 2.0)
	draw_line(at + Vector2(7, 8), at + Vector2(10, 17), Color("#2d3537"), 2.0)

func _draw_storefront(facade: Rect2, accent: Color) -> void:
	var awning := Rect2(facade.position.x + 6, facade.position.y + 7, facade.size.x - 12, 7)
	draw_rect(awning, accent)
	for x in range(int(awning.position.x + 4), int(awning.end.x - 3), 10):
		draw_line(Vector2(x, awning.position.y), Vector2(x, awning.end.y), Color("#f0e1b6"), 2.0)
	var door := Rect2(facade.get_center().x - 7, facade.end.y - 17, 14, 17)
	draw_rect(door, Color("#273941"))
	draw_circle(door.position + Vector2(10, 9), 1.5, Color("#e8ca64"))

func _draw_police_roof(roof: Rect2, accent: Color) -> void:
	var antenna := roof.get_center() + Vector2(roof.size.x * 0.20, -6)
	draw_line(antenna, antenna + Vector2(0, -24), Color("#263039"), 2.0)
	draw_line(antenna + Vector2(-7, -17), antenna + Vector2(7, -17), accent, 2.0)
	var access := Rect2(roof.position + Vector2(16, roof.size.y * 0.58), Vector2(roof.size.x * 0.28, roof.size.y * 0.22))
	draw_rect(access, Color("#40525b"))
	draw_rect(access, Color("#93acb4"), false, 2.0)

func _draw_police_identity(roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	# One broad motor-pool shutter plus a protected pedestrian entrance.  This
	# reads as an operational precinct rather than another office block.
	var bay := Rect2(facade.position.x + 8, facade.position.y + 9, facade.size.x * 0.48, facade.size.y - 12)
	draw_rect(bay, Color("#25333d"))
	for y in range(int(bay.position.y + 4), int(bay.end.y), 5):
		draw_line(Vector2(bay.position.x + 2, y), Vector2(bay.end.x - 2, y), Color("#526c7b"), 1.0)
	var entry := Rect2(facade.end.x - 35, facade.end.y - 24, 22, 24)
	draw_rect(entry, Color("#172532"))
	draw_rect(entry, p.accent, false, 2.0)
	# Shield: a compact, non-textual landmark above the entrance.
	var shield_at := Vector2(entry.get_center().x, facade.position.y + 4)
	draw_colored_polygon(PackedVector2Array([
		shield_at + Vector2(-7, -5), shield_at + Vector2(7, -5),
		shield_at + Vector2(6, 3), shield_at + Vector2(0, 9),
		shield_at + Vector2(-6, 3)
	]), p.accent)
	draw_circle(shield_at + Vector2(0, 1), 2.0, Color("#d9edf1"))
	# Blue-white curb lights are readable without spelling POLICE.
	for x in range(int(facade.position.x + 8), int(facade.end.x - 45), 14):
		draw_rect(Rect2(x, facade.position.y + 3, 7, 4), p.accent if int(x / 14) % 2 == 0 else Color("#d8e4e7"))

func _draw_fire_station_identity(roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	# Three equal appliance bays establish the classic firehouse rhythm.
	var gap := 5.0
	var margin := 7.0
	var bay_width := (facade.size.x - margin * 2.0 - gap * 2.0) / 3.0
	for i in 3:
		var bay := Rect2(facade.position + Vector2(margin + i * (bay_width + gap), 8), Vector2(bay_width, facade.size.y - 11))
		draw_rect(bay, Color("#282d2f"))
		for y in range(int(bay.position.y + 4), int(bay.end.y), 5):
			draw_line(Vector2(bay.position.x + 2, y), Vector2(bay.end.x - 2, y), p.accent.darkened(0.22), 1.5)
		draw_rect(bay, Color("#e2c76f"), false, 1.5)
	# Crossed ladder/hose emblem is unique at gameplay zoom.
	var icon := facade.get_center() + Vector2(0, -3)
	draw_line(icon + Vector2(-9, 7), icon + Vector2(9, -7), Color("#f0d97e"), 2.5)
	draw_line(icon + Vector2(-9, -7), icon + Vector2(9, 7), Color("#f0d97e"), 2.5)
	for offset in [-5.0, 0.0, 5.0]:
		draw_line(icon + Vector2(offset - 2, -5), icon + Vector2(offset + 2, -1), Color("#f0d97e"), 1.0)

func _draw_fire_station_roof(roof: Rect2, p: Dictionary) -> void:
	# Hose-drying tower and siren make a taller, asymmetric silhouette.
	var tower := Rect2(roof.position + Vector2(14, 12), Vector2(minf(34.0, roof.size.x * 0.22), minf(48.0, roof.size.y * 0.45)))
	draw_rect(Rect2(tower.position + Vector2(4, 5), tower.size), Color(0.05, 0.06, 0.07, 0.38))
	draw_rect(tower, p.edge)
	draw_rect(tower.grow(-3), p.front.darkened(0.08))
	for y in range(int(tower.position.y + 8), int(tower.end.y - 3), 9):
		draw_line(Vector2(tower.position.x + 4, y), Vector2(tower.end.x - 4, y), p.mortar, 1.0)
	var siren_at := roof.position + Vector2(roof.size.x * 0.72, 18)
	draw_circle(siren_at, 7, p.accent)
	draw_circle(siren_at, 3, Color("#ffd37a"))

func _draw_windows(facade: Rect2, window_color: Color) -> void:
	var count := maxi(2, int(facade.size.x / 30.0))
	var gap := facade.size.x / float(count)
	for i in count:
		var window := Rect2(facade.position.x + gap * i + 5, facade.position.y + 8, gap - 10, facade.size.y - 13)
		draw_rect(window, window_color)
		draw_rect(window, Color("#253b46"), false, 1.5)

func _draw_garage_doors(facade: Rect2, door_color: Color) -> void:
	for i in 2:
		var door := Rect2(facade.position.x + facade.size.x * (0.08 + 0.48 * i), facade.position.y + 6, facade.size.x * 0.37, facade.size.y - 12)
		draw_rect(door, door_color.darkened(0.35))
		for line_y in range(int(door.position.y + 5), int(door.end.y), 5):
			draw_line(Vector2(door.position.x + 2, line_y), Vector2(door.end.x - 2, line_y), Color("#1f2a31"), 1.0)

func _draw_hospital_roof(roof: Rect2, accent: Color) -> void:
	var pad := Rect2(roof.get_center() - Vector2(26, 26), Vector2(52, 52))
	draw_circle(pad.get_center(), 25, accent.darkened(0.20))
	draw_circle(pad.get_center(), 18, Color("#d9eff0"))
	draw_line(pad.get_center() + Vector2(-12, 0), pad.get_center() + Vector2(12, 0), accent, 5)
	draw_line(pad.get_center() + Vector2(0, -12), pad.get_center() + Vector2(0, 12), accent, 5)

func _draw_morgue_roof(roof: Rect2, p: Dictionary) -> void:
	var center := roof.get_center()
	
	# Heliponto / Emblema funerário com círculo roxo e cruz médica estilizada
	var pad_center := center + Vector2(-18, 0)
	draw_circle(pad_center, 22, p.edge)
	draw_circle(pad_center, 18, Color("#1f242d"))
	draw_circle(pad_center, 15, Color("#2c3e50"))
	draw_line(pad_center + Vector2(-10, 0), pad_center + Vector2(10, 0), p.accent, 4.0)
	draw_line(pad_center + Vector2(0, -10), pad_center + Vector2(0, 10), p.accent, 4.0)
	
	# Letreiro BOLD "I M L" desenhado no teto com tipografia vetorial nítida
	var text_center := center + Vector2(18, 0)
	_draw_bold_iml_letters(text_center, Color("#f1f2f6"), Color("#0c0d0e"))
	
	# Chiller / Exaustor Industrial Duplo de Refrigeração Criogênica
	var chiller_rect := Rect2(roof.position + Vector2(6, 6), Vector2(30, 18))
	draw_rect(chiller_rect, Color("#2f3640"))
	draw_rect(chiller_rect, Color("#1e272e"), false, 1.5)
	draw_circle(chiller_rect.get_center() + Vector2(-7, 0), 5, Color("#718093"))
	draw_circle(chiller_rect.get_center() + Vector2(7, 0), 5, Color("#718093"))

func _draw_bold_iml_letters(at: Vector2, col: Color, shadow_col: Color) -> void:
	for c in [shadow_col, col]:
		var offset: Vector2 = Vector2(1, 1) if c == shadow_col else Vector2.ZERO
		var i_x: float = at.x - 14.0 + offset.x
		var y_top: float = at.y - 10.0 + offset.y
		var y_bot: float = at.y + 10.0 + offset.y
		
		# Letra I
		draw_line(Vector2(i_x, y_top), Vector2(i_x, y_bot), c, 3.5)
		draw_line(Vector2(i_x - 4, y_top), Vector2(i_x + 4, y_top), c, 2.5)
		draw_line(Vector2(i_x - 4, y_bot), Vector2(i_x + 4, y_bot), c, 2.5)
		
		# Letra M
		var m_x: float = at.x + offset.x
		draw_line(Vector2(m_x - 6, y_bot), Vector2(m_x - 6, y_top), c, 3.0)
		draw_line(Vector2(m_x - 6, y_top), Vector2(m_x, y_top + 6), c, 3.0)
		draw_line(Vector2(m_x, y_top + 6), Vector2(m_x + 6, y_top), c, 3.0)
		draw_line(Vector2(m_x + 6, y_top), Vector2(m_x + 6, y_bot), c, 3.0)
		
		# Letra L
		var l_x: float = at.x + 14.0 + offset.x
		draw_line(Vector2(l_x - 4, y_top), Vector2(l_x - 4, y_bot), c, 3.5)
		draw_line(Vector2(l_x - 4, y_bot), Vector2(l_x + 5, y_bot), c, 3.5)

func _draw_park_plaza(bounds: Rect2) -> void:
	var plaza := bounds.grow(-3)
	draw_rect(plaza, Color("#77786f"))
	draw_rect(plaza, Color("#3f4746"), false, 3.0)
	# Large paving slabs ground this visually at sidewalk level.
	for x in range(int(plaza.position.x + 24), int(plaza.end.x), 34):
		draw_line(Vector2(x, plaza.position.y), Vector2(x, plaza.end.y), Color("#686b64"), 1.0)
	for y in range(int(plaza.position.y + 24), int(plaza.end.y), 28):
		draw_line(Vector2(plaza.position.x, y), Vector2(plaza.end.x, y), Color("#686b64"), 1.0)
	# Two unmistakable planters: visible soil, trunks and offset crowns.  These
	# are intentionally not symmetric circles sitting directly on the plaza.
	for tree_at in [plaza.position + Vector2(22, 24), plaza.end - Vector2(23, 26)]:
		draw_rect(Rect2(tree_at - Vector2(11, 8), Vector2(22, 16)), Color("#4b3a2e"))
		draw_rect(Rect2(tree_at - Vector2(13, 10), Vector2(26, 20)), Color("#b5a36f"), false, 2.0)
		draw_line(tree_at, tree_at + Vector2(0, -10), Color("#47372c"), 4.0)
		draw_circle(tree_at + Vector2(-4, -14), 8, Color("#315e42"))
		draw_circle(tree_at + Vector2(5, -17), 9, Color("#3f7450"))
	# Benches and a small central mosaic produce a public-space silhouette.
	var center := plaza.get_center()
	draw_rect(Rect2(center - Vector2(17, 11), Vector2(34, 22)), Color("#5f726f"))
	draw_rect(Rect2(center - Vector2(12, 7), Vector2(24, 14)), Color("#8ca29a"), false, 2.0)
	for bench_x in [plaza.position.x + 18.0, plaza.end.x - 46.0]:
		draw_rect(Rect2(bench_x, center.y - 3, 28, 6), Color("#77543a"))
		draw_line(Vector2(bench_x + 4, center.y + 3), Vector2(bench_x + 2, center.y + 8), Color("#292d2c"), 2.0)
		draw_line(Vector2(bench_x + 24, center.y + 3), Vector2(bench_x + 26, center.y + 8), Color("#292d2c"), 2.0)

func _draw_ammunation_identity(roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	# A low fortified canopy makes the weapon shop read as a destination even
	# when no label is present.
	var canopy := Rect2(facade.position + Vector2(4, 4), Vector2(facade.size.x - 8, 12))
	draw_rect(canopy, p.edge)
	for x in range(int(canopy.position.x + 4), int(canopy.end.x - 2), 14):
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, canopy.position.y), Vector2(x + 7, canopy.position.y),
			Vector2(x + 1, canopy.end.y), Vector2(x - 6, canopy.end.y)
		]), p.accent)
	var entry := Rect2(facade.get_center().x - 15, facade.end.y - 24, 30, 24)
	draw_rect(entry, Color("#151a1e"))
	draw_line(Vector2(entry.get_center().x, entry.position.y + 2), Vector2(entry.get_center().x, entry.end.y), Color("#59666a"), 2.0)
	for side in [-1.0, 1.0]:
		var guard := Rect2(entry.get_center() + Vector2(side * 22.0 - 4.0, -8.0), Vector2(8, 16))
		draw_rect(guard, p.accent.darkened(0.25))
	# Cartridge emblem: brass casing plus dark projectile, deliberately graphic.
	var icon := facade.get_center() + Vector2(0, -1)
	draw_rect(Rect2(icon - Vector2(4, 7), Vector2(8, 13)), Color("#d8ad45"))
	draw_colored_polygon(PackedVector2Array([
		icon + Vector2(-4, -7), icon + Vector2(4, -7), icon + Vector2(0, -13)
	]), Color("#25292e"))

func _draw_ammunation_roof(roof: Rect2, p: Dictionary) -> void:
	# Bunker parapets and paired exhausts replace generic HVAC boxes.
	for x in [roof.position.x + 8.0, roof.end.x - 18.0]:
		draw_rect(Rect2(x, roof.position.y + 8, 10, roof.size.y - 16), p.edge.darkened(0.08))
	var exhaust_y := roof.position.y + roof.size.y * 0.34
	for x in [roof.get_center().x - 19.0, roof.get_center().x + 19.0]:
		draw_circle(Vector2(x, exhaust_y), 8, Color("#697176"))
		draw_circle(Vector2(x, exhaust_y), 4, Color("#20262a"))

func _draw_garage_identity(roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	_draw_garage_doors(facade, p.window)
	# High-contrast hazard band is unique to vehicle service buildings.
	var band := Rect2(facade.position + Vector2(4, 3), Vector2(facade.size.x - 8, 8))
	draw_rect(band, Color("#d3a536"))
	for x in range(int(band.position.x), int(band.end.x), 18):
		draw_line(Vector2(x, band.end.y), Vector2(x + 9, band.position.y), Color("#272826"), 4.0)
	# Wrench icon between the shutters.
	var icon := facade.get_center() + Vector2(0, -2)
	draw_line(icon + Vector2(-7, 7), icon + Vector2(7, -7), Color("#d9dde0"), 4.0)
	draw_circle(icon + Vector2(-8, 8), 4, Color("#d9dde0"))
	draw_circle(icon + Vector2(-8, 8), 2, p.front)
	draw_line(icon + Vector2(5, -9), icon + Vector2(10, -4), Color("#d9dde0"), 3.0)

func _draw_garage_roof(roof: Rect2, p: Dictionary) -> void:
	# Saw-tooth skylights give the garage an industrial silhouette.
	for y in range(int(roof.position.y + 14), int(roof.end.y - 8), 24):
		draw_colored_polygon(PackedVector2Array([
			Vector2(roof.position.x + 12, y + 8), Vector2(roof.end.x - 12, y + 8),
			Vector2(roof.end.x - 20, y), Vector2(roof.position.x + 20, y)
		]), Color("#55666b"))
		draw_line(Vector2(roof.position.x + 20, y), Vector2(roof.end.x - 20, y), p.accent, 1.5)

func _draw_clothing_identity(roof: Rect2, facade: Rect2, p: Dictionary) -> void:
	# Boutique window bays use a different rhythm from generic shops.
	var window_size := Vector2(maxf(20.0, facade.size.x * 0.23), maxf(13.0, facade.size.y - 16))
	for side in [-1.0, 1.0]:
		var display := Rect2(facade.get_center() + Vector2(side * facade.size.x * 0.27 - window_size.x * 0.5, -window_size.y * 0.5 + 3), window_size)
		draw_rect(display, p.window.darkened(0.16))
		draw_rect(display, p.accent, false, 2.0)
		# Minimal mannequin form, readable without text.
		var mannequin := display.get_center()
		draw_circle(mannequin + Vector2(0, -4), 2.5, Color("#ead7bb"))
		draw_colored_polygon(PackedVector2Array([
			mannequin + Vector2(0, -1), mannequin + Vector2(-5, 7),
			mannequin + Vector2(5, 7)
		]), p.accent.lightened(0.18))
	var door := Rect2(facade.get_center().x - 8, facade.end.y - 21, 16, 21)
	draw_rect(door, Color("#26383d"))
	draw_rect(door, p.accent, false, 2.0)
	# Hanger icon above the entry.
	var hanger := Vector2(door.get_center().x, facade.position.y + 5)
	draw_arc(hanger + Vector2(0, -2), 3.0, PI, TAU, 8, Color("#e5d5c8"), 1.5)
	draw_line(hanger, hanger + Vector2(-8, 6), Color("#e5d5c8"), 2.0)
	draw_line(hanger, hanger + Vector2(8, 6), Color("#e5d5c8"), 2.0)
	draw_line(hanger + Vector2(-8, 6), hanger + Vector2(8, 6), Color("#e5d5c8"), 2.0)

func _draw_clothing_roof(roof: Rect2, p: Dictionary) -> void:
	# A stepped teal marquee creates a soft retail silhouette against the harder
	# garage and weapon-store roofs.
	var inset := roof.grow(-10)
	var marquee := PackedVector2Array([
		Vector2(inset.position.x, inset.position.y + 10),
		Vector2(inset.position.x + 12, inset.position.y),
		Vector2(inset.end.x - 12, inset.position.y),
		Vector2(inset.end.x, inset.position.y + 10),
		Vector2(inset.end.x, inset.position.y + 18),
		Vector2(inset.position.x, inset.position.y + 18)
	])
	draw_colored_polygon(marquee, p.accent.darkened(0.12))
	draw_polyline(marquee, p.accent.lightened(0.18), 2.0)
