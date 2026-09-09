extends "res://world/mountain_pass/MountainGunCounterSupport.gd"
## Mountain-only presentation; keeps Harbor's vendor and purchasing contracts.
var room_view: Node2D
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var _active := false
var _render_clock := 0.0
func _build_walls_and_floor() -> void: pass
func _build_lights() -> void: pass


func _setup_interior_content() -> void:
	room_view = preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	add_child(room_view)
	room_view.build_view(preload("res://world/mountain_pass/art/review_0908/MountainGunShopInterior3D.gd"),13.0,48.0,Vector3(0,0.8,0))
	_prepare_showcase_glass()
	viewport_3d = room_view.viewport_3d
	camera_3d = room_view.camera_3d
	sprite_3d = room_view.sprite_3d
	_build_projected_solids()
	_build_gunsmith()
	gunsmith_npc.position = project_floor(Vector2(-1.4,-0.9))
	gunsmith_npc.model_root.reparent(room_view.model,false)
	gunsmith_npc.model_root.position = Vector3(-1.4,0.1,-0.9)
	gunsmith_npc.model_root.scale = Vector3.ONE*1.25
	gunsmith_npc.sprite_3d_display.hide()
	gunsmith_npc.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	gunsmith_npc.set_process_unhandled_input(false)
	gunsmith_npc.prompt_badge.modulate.a = 0.0
	gunsmith_npc.dialogue_opened.connect(func(): modal_opened.emit())
	gunsmith_npc.dialogue_closed.connect(func(): modal_closed.emit())
	_build_interaction_counter()
	counter_area.body_exited.connect(func(body: Node2D):
		if body.is_in_group("player") and gunsmith_npc.is_talking: gunsmith_npc._close_dialogue()
	)
	counter_area.position = project_floor(Vector2(-1.2,1.35))
	counter_area.get_child(0).shape.size = Vector2(170,55)
	counter_badge.position = project_floor(Vector2(-1.2,1.5))-Vector2(150,0)
	counter_badge.text = "[E] ARMAS / MUNIÇÃO    [F] CONVERSAR"
	counter_dialog.offset_top = -335
	counter_text.get_parent().get_child(0).text = "AMMU-NATION — EQUIPAMENTO PARA A SERRA"
	_build_purchase_buttons()
	_create_spawn_and_exit(project_floor(Vector2(0,2.8)),project_floor(Vector2(0,3.7)),&"ammunation_exterior_return","SAIR DA AMMU-NATION")
	exit_door.get_node("Facade").hide()
	exit_door.custom_prompt_text = "[E] SAIR DA AMMU-NATION"
func _prepare_showcase_glass() -> void:
	# The supplied glass was opaque and enclosed by a full-height wooden box.
	# Keep its authored frame, lower the plinth and reveal the actual stock.
	var material: StandardMaterial3D = room_view.model._materials["showcase_glass"]
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.20
	for part in room_view.model.get_children():
		if not part is MeshInstance3D or not part.mesh is BoxMesh: continue
		if part.position.distance_to(Vector3(-1.2,0.45,0.60))<0.01:
			part.mesh = part.mesh.duplicate()
			part.mesh.size.y = 0.46
			part.position.y = 0.23
		elif part.position.distance_to(Vector3(-1.2,0.92,0.60))<0.01:
			part.material_override = material
func project_floor(point: Vector2) -> Vector2: return room_view.project_floor(point)
func _build_projected_solids() -> void:
	var footprints := {
		"NorthWall":Rect2(-4.8,-3.9,9.6,0.2),
		"WestWall":Rect2(-4.9,-3.8,0.2,7.6),
		"EastWall":Rect2(4.7,-3.8,0.2,7.6),
		"SouthWall":Rect2(-4.8,3.8,9.6,0.2),
		"ShowcaseCounter":Rect2(-3.25,0.23,4.15,0.8),
		"CounterReturn":Rect2(0.30,-1.85,0.80,2.50),
		"RangePartition":Rect2(2.9,-3.8,0.20,5.1),
		"ShootingBench":Rect2(3.0,0.95,1.65,0.5),
		"Workbench":Rect2(0.75,-3.3,1.8,0.95),
		"Safe":Rect2(-4.65,-3.65,0.95,1.0),
		"Stove":Rect2(-4.3,1.9,1.0,1.0)
	}
	for key in footprints: room_view.add_solid(footprints[key],key)
func set_npc_rendering_active(active: bool) -> void:
	super.set_npc_rendering_active(active)
	_active = active
	if not active:
		is_near_counter = false
		if is_instance_valid(counter_badge): counter_badge.hide()
		if is_instance_valid(counter_dialog) and counter_dialog.visible:
			counter_dialog.hide()
			modal_closed.emit()
		if is_instance_valid(gunsmith_npc) and gunsmith_npc.is_talking: gunsmith_npc._close_dialogue()
	if viewport_3d: viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED
	if is_instance_valid(gunsmith_npc): gunsmith_npc.viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
func _process(delta: float) -> void:
	if not _active: return
	_render_clock += delta
	if _render_clock >= 0.05:
		_render_clock = 0.0
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
func _unhandled_input(event: InputEvent) -> void:
	if not _active or not is_near_counter: return
	if event is InputEventKey and event.pressed and not event.echo:
		if gunsmith_npc.is_talking:
			if event.keycode == KEY_ESCAPE: gunsmith_npc._close_dialogue()
			elif event.keycode in [KEY_E,KEY_F,KEY_SPACE,KEY_ENTER]: gunsmith_npc._advance_dialogue()
			else: return
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F and not counter_dialog.visible:
			gunsmith_npc._open_dialogue()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)
func _resupply_ammo() -> void:
	super._resupply_ammo()
	_refresh_weapon_buttons()
	counter_text.text = "Vance: equipamento revisado para a serra. Escolha sua arma ou reponha a munição."


