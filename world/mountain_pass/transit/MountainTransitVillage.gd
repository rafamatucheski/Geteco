extends "res://world/mountain_pass/MountainStaticModelView.gd"
## One small terminal, four chalets and a real winter outfitter facade.
## Root installs gameplay entrances/passengers using the shared mountain coords.
const LAYOUT := preload("res://world/mountain_pass/transit/MountainTransitVillageLayout.gd")
const ARCHITECTURE := preload("res://world/mountain_pass/transit/MountainTransitArchitecture3D.gd")
var region_ready := false
var heat_source: Node2D
const INLINE_BODIES := {
	&"mountain_village_outfitters": "WinterClothingShop",
	&"mountain_cabin_village_1": "Chalet01",
	&"mountain_cabin_village_2": "Chalet02",
	&"mountain_cabin_village_3": "Chalet03",
	&"mountain_cabin_village_4": "Chalet04",
}

func _ready() -> void:
	position = LAYOUT.ORIGIN
	z_index = 4
	build_view(ARCHITECTURE,40.0,18.0,Vector3(4.0,0,0),Vector3(0,24,20))
	viewport_3d.size = Vector2i(1920,1600)
	_recalibrate()
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	for child in viewport_3d.get_children():
		if child is DirectionalLight3D:
			child.light_energy = 0.72
			child.shadow_enabled = true
			child.directional_shadow_max_distance = 75
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.45
	for footprint in model.solids:
		var body := StaticBody2D.new()
		body.name = footprint.name
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("mountain_geodata")
		body.set_meta("geometry_contract","projected_mesh_volume" if footprint.get("projected_volume",false) else "ground_footprint")
		if footprint.name in INLINE_BODIES.values():
			_build_inline_shell(body, footprint.mountain_rect, footprint.name == "WinterClothingShop")
		else:
			var shape := CollisionPolygon2D.new()
			var projected := PackedVector2Array()
			for point in footprint.polygon:
				projected.append(project_point(point))
			shape.polygon = Geometry2D.convex_hull(projected)
			body.add_child(shape)
		add_child(body)
		for seat_point in footprint.get("seats",[]):
			var floor_point := ARCHITECTURE.floor_from_local(seat_point-LAYOUT.ORIGIN)
			var marker := preload("res://world/mountain_pass/transit/MountainBenchGeometry.gd").seat(self,project_point(floor_point),project_point(floor_point+Vector3.UP*float(footprint.seat_height)),body,float(footprint.seat_height),"village")
			var access: Array[Vector2] = []
			for waypoint in LAYOUT.bench_access_route(seat_point): access.append(waypoint-seat_point)
			marker.set_meta("access_route",access)
	await preload("res://world/mountain_pass/transit/MountainWinterDressing.gd").install_village(self)
	_add_heat_source()
	var visible := VisibleOnScreenNotifier2D.new()
	visible.rect = Rect2(-275,-180,725,560)
	visible.screen_entered.connect(func(): viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE)
	add_child(visible)
	region_ready = true

func _build_inline_shell(body: StaticBody2D, rect: Rect2, shop: bool) -> void:
	var edge := 5.0
	var half_gap := 12.0 if shop else 10.0
	var center_x := rect.get_center().x
	var segments := [
		["BackWall", Rect2(rect.position.x, rect.position.y, rect.size.x, edge)],
		["WestWall", Rect2(rect.position.x, rect.position.y, edge, rect.size.y)],
		["EastWall", Rect2(rect.end.x - edge, rect.position.y, edge, rect.size.y)],
		["WestFront", Rect2(rect.position.x, rect.end.y - edge, center_x - half_gap - rect.position.x, edge)],
		["EastFront", Rect2(center_x + half_gap, rect.end.y - edge, rect.end.x - center_x - half_gap, edge)],
		["DoorLeaf", Rect2(center_x - half_gap, rect.end.y - edge, half_gap * 2.0, edge)],
	]
	for entry in segments:
		var segment: Rect2 = entry[1]
		var shape := CollisionPolygon2D.new()
		shape.name = entry[0]
		shape.polygon = PackedVector2Array([
			project_point(ARCHITECTURE.floor_from_local(segment.position-LAYOUT.ORIGIN)),
			project_point(ARCHITECTURE.floor_from_local(Vector2(segment.end.x, segment.position.y)-LAYOUT.ORIGIN)),
			project_point(ARCHITECTURE.floor_from_local(segment.end-LAYOUT.ORIGIN)),
			project_point(ARCHITECTURE.floor_from_local(Vector2(segment.position.x, segment.end.y)-LAYOUT.ORIGIN)),
		])
		body.add_child(shape)

func _recalibrate() -> void:
	var rendered_metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * 18.0 / rendered_metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*0.5)*sprite_3d.scale

func _add_heat_source() -> void:
	var fire_view := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	fire_view.name = "VillageBrazier"
	fire_view.position = LAYOUT.HEAT_SOURCE-LAYOUT.ORIGIN
	add_child(fire_view)
	fire_view.build_view(preload("res://world/mountain_pass/transit/MountainTransitBrazier3D.gd"),5.5,18.0,Vector3(0,1.25,0),Vector3(0,24,20))
	fire_view.viewport_3d.size = Vector2i(384,320)
	var rendered_metre: float = fire_view.camera_3d.unproject_position(Vector3.RIGHT).distance_to(fire_view.camera_3d.unproject_position(Vector3.ZERO))
	fire_view.sprite_3d.scale = Vector2.ONE * 18.0 / rendered_metre
	fire_view.sprite_3d.position = -(fire_view.camera_3d.unproject_position(Vector3.ZERO)-Vector2(fire_view.viewport_3d.size)*0.5)*fire_view.sprite_3d.scale
	fire_view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	fire_view.add_solid(Rect2(-0.63,-0.63,1.26,1.26),"BrazierBody")
	fire_view.add_to_group("heat_source")
	heat_source = fire_view
	var visible := VisibleOnScreenNotifier2D.new()
	visible.rect = Rect2(-65,-85,130,130)
	visible.screen_entered.connect(func(): fire_view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE)
	visible.screen_exited.connect(func(): fire_view.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED)
	fire_view.add_child(visible)

func floor_from_local(point: Vector2) -> Vector3:
	return ARCHITECTURE.floor_from_local(point)

func mountain_point(point: Vector2) -> Vector2:
	return to_global(point-LAYOUT.ORIGIN)

func set_building_passable(id: StringName, passable: bool) -> void:
	var body := get_node_or_null(INLINE_BODIES.get(id, "")) as StaticBody2D
	if body == null: return
	var shape := body.get_node_or_null("DoorLeaf") as CollisionPolygon2D
	if shape != null: shape.set_deferred("disabled", passable)

func set_building_open(id: StringName, open: bool) -> void:
	if not is_instance_valid(model): return
	model.set_inline_building_hidden(id, open)
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func set_building_door_amount(id: StringName, amount: float) -> void:
	if not is_instance_valid(model): return
	model.set_inline_door_amount(id, amount)
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
