extends "res://world/mountain_pass/MountainCabinInterior.gd"
var room_view: Node2D
var _active := false
var _render_clock := 0.0
func _init() -> void:
	interior_id = &"lumberjack_shelter"
	display_name = "ABRIGO DOS LENHADORES — ALOJAMENTO DE TRABALHO"
func _setup_interior_content() -> void:
	_setup_3d_cabin_viewport()
	_setup_heat_source()
	_build_projected_furniture()
	_create_spawn_and_exit(project_floor(Vector2(0,3.0)),project_floor(Vector2(0,4.15)),&"lumberjack_exterior_return","SAIR DO ABRIGO DOS LENHADORES")
	exit_door.custom_prompt_text = "[E] SAIR DO ABRIGO DOS LENHADORES"
	exit_door.get_node("Facade").hide()
func _setup_weapon_stations() -> void: pass
func _setup_3d_cabin_viewport() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/LumberjackBunkhouse3D.gd"),14.0,44.0,Vector3(0,0.8,0))
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	cabin_3d_world = room_view.model
func project_floor(point: Vector2) -> Vector2: return room_view.project_floor(point)
func _build_projected_furniture() -> void:
	var footprints := {
		"NorthWall":Rect2(-5,-4.8,10,0.2),"WestWall":Rect2(-5.1,-4.7,0.2,9.4),
		"EastWall":Rect2(4.9,-4.7,0.2,9.4),"SouthWall":Rect2(-5,4.7,10,0.2),
		"Workbench":Rect2(-1.85,-4.12,3.7,1.15),"CommunalTable":Rect2(-1.2,-0.27,2.4,1.24),
		"NorthBench":Rect2(-1.15,-0.80,2.3,0.4),"SouthBench":Rect2(-1.15,1.1,2.3,0.4),
		"Stove":Rect2(-4.35,2.35,1.2,1.3),"Woodpile":Rect2(3.0,2.55,1.2,1.3)
	}
	for key in footprints: room_view.add_solid(footprints[key],key)
	for side in [-1.0,1.0]:
		for row in 2: room_view.add_solid(Rect2(side*3.75-0.62,-3.67+row*2.8,1.24,2.34),"WorkerBunk")
func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	_active = active
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED
func _process(delta: float) -> void:
	if not _active: return
	_render_clock += delta
	if _render_clock >= 0.05:
		_render_clock = 0.0
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
