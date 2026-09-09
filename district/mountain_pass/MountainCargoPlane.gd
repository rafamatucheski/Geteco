extends "res://district/mountain_pass/MountainStaticModelView.gd"
## Continuous on-foot exploration: there is no scene change or actor relocation.
const PICKUP_ID := "mountain_cargo_plane_treasure_01"
const REWARD := 1800
var inside := false
var collected := false
var _actor: Node2D
var _clock := 0.0
var _camera: Camera2D
var _old_zoom_meta: Variant
var _had_zoom_meta := false
var _roof_parts: Array[Node3D] = []
var treasure_model: Node3D
var treasure_lid: Node3D
var gold: Node3D
var prompt: Label
var entrance_hint: Label
signal treasure_claimed(amount: int)
func _ready() -> void:
	z_as_relative = false
	z_index = 4
	build_view(preload("res://district/mountain_pass/art/review_0908/CrashedCargoPlane3D.gd"),36.0,16.0,Vector3(0,1.4,-2.0))
	_open_cargo_aisle()
	_build_solids()
	_build_treasure()
	_build_smg_pickup()
	prompt = Label.new()
	prompt.text = "[E] ABRIR CAIXA DE CONTRABANDO"
	prompt.position = project_floor(Vector2(0,-6.7))-Vector2(110,0)
	prompt.add_theme_font_size_override("font_size",11)
	prompt.add_theme_color_override("font_shadow_color",Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_x",1)
	prompt.add_theme_constant_override("shadow_offset_y",1)
	prompt.z_index = 20
	prompt.hide()
	add_child(prompt)
	entrance_hint = Label.new()
	entrance_hint.text = "CARGUEIRO DOS LOBOS / ENTRE PELA RAMPA"
	entrance_hint.position = project_floor(Vector2(0,10))-Vector2(125,0)
	entrance_hint.add_theme_font_size_override("font_size",11)
	entrance_hint.z_index = 20
	entrance_hint.hide()
	add_child(entrance_hint)
func _build_smg_pickup() -> void:
	var pickup := preload("res://district/mountain_pass/MountainWeaponPickup.gd").new()
	pickup.name = "CargoSMG"
	pickup.weapon_id = "smg"
	pickup.pickup_id = "mountain_cargo_plane_smg_01"
	pickup.ammo = 20
	pickup.load_on_pickup = true
	pickup.render_host = self
	pickup.position = project_floor(Vector2(0.35, -5.2))
	add_child(pickup)
	pickup.install_model(model, Vector3(0.35, 0.08, -5.2))

func _open_cargo_aisle() -> void:
	var materials: Dictionary = model._materials
	for part in model.get_children():
		if not part is MeshInstance3D or not part.mesh is BoxMesh: continue
		if part.material_override in [materials.get("crate_wood"),materials.get("crate_metal")]:
			# The supplied art stacked cargo across the complete fuselage width.
			# Lash it against the port wall and keep the middle/right aisle open.
			part.position.x = -0.95
			part.mesh = part.mesh.duplicate()
			part.mesh.size.x = minf(part.mesh.size.x,0.55)
		if part.position.y > 2.0 and absf(part.position.x)<0.1:
			# Wing centre and raised tail would still cover the walking corridor
			# even with CutawayRoof removed. Treat these as overhead sections.
			_roof_parts.append(part)
func _build_solids() -> void:
	for side in [-1.0,1.0]:
		add_solid(Rect2(side*1.55-0.12,-13.3,0.24,19.9),"FuselageWall")
	add_solid(Rect2(-1.55,-13.6,3.1,0.3),"CockpitNose")
	add_solid(Rect2(-14.1,-4.9,12.6,2.8),"LeftWing")
	add_solid(Rect2(1.65,-4.9,12.3,2.8),"RightWing")
	add_solid(Rect2(-1.27,-4.0,0.65,1.6),"SecuredForwardCargo")
	add_solid(Rect2(-1.27,1.9,0.65,1.5),"SecuredRampCargo")
	add_solid(Rect2(0.18,-7.65,0.75,0.60),"TreasureCrate")
	for side in [-1.0,1.0]:
		add_solid(Rect2(side*0.62-0.26,-11.85,0.52,0.8),"PilotSeat")
	add_solid(Rect2(-1.1,-12.9,2.2,0.6),"CockpitInstruments")
func _build_treasure() -> void:
	treasure_model = Node3D.new()
	treasure_model.name = "SmugglerTreasure"
	treasure_model.position = Vector3(0.55,0.20,-7.35)
	model.add_child(treasure_model)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("344938")
	paint.metallic = 0.6
	_box(treasure_model,Vector3(0,0.21,0),Vector3(0.75,0.42,0.6),paint)
	treasure_lid = Node3D.new()
	treasure_lid.position = Vector3(0,0.45,-0.30)
	treasure_model.add_child(treasure_lid)
	_box(treasure_lid,Vector3(0,0,0.30),Vector3(0.78,0.06,0.62),paint)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("c6aa58")
	brass.metallic = 0.75
	_box(treasure_lid,Vector3(0,0.01,0.62),Vector3(0.11,0.12,0.03),brass)
	gold = Node3D.new()
	treasure_model.add_child(gold)
	for x in [-0.2,0.0,0.2]: _box(gold,Vector3(x,0.47,0),Vector3(0.13,0.06,0.25),brass)
func _box(parent: Node3D,pos: Vector3,size: Vector3,material: Material) -> void:
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.material_override = material
	part.position = pos
	parent.add_child(part)
func contains_actor(actor: Node2D) -> bool:
	if not is_instance_valid(actor) or not actor.is_visible_in_tree(): return false
	if actor.get("is_dead") == true: return false
	return Rect2(-1.37,-13.0,2.74,22.4).has_point(unproject_floor(actor.global_position))
func _process(delta: float) -> void:
	_clock += delta
	if _clock < 0.10: return
	_clock = 0.0
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var occupied := contains_actor(player)
	if occupied != inside or (inside and player != _actor): _set_inside(player,occupied)
	if not is_instance_valid(player): return
	var saved: bool = player.get("world_pickups_collected") is Array and player.world_pickups_collected.has(PICKUP_ID)
	if saved != collected: _set_collected(saved)
	var floor_position := unproject_floor(player.global_position)
	prompt.visible = inside and not collected and floor_position.distance_to(Vector2(0.55,-7.35)) < 1.75
	entrance_hint.visible = not inside and player.visible and floor_position.distance_to(Vector2(0,9.2))<8.0
func _set_inside(player: Node2D, value: bool) -> void:
	if inside and is_instance_valid(_actor): _actor.remove_meta("mountain_shelter")
	if is_instance_valid(_camera):
		if _had_zoom_meta: _camera.set_meta("mountain_zoom",_old_zoom_meta)
		else: _camera.remove_meta("mountain_zoom")
	_actor = player if value else null
	_camera = null
	inside = value
	model.set_cutaway(value)
	for part in _roof_parts: part.visible = not value
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	if value:
		player.set_meta("mountain_shelter",true)
		_camera = player.get_node_or_null("Camera") as Camera2D
		if _camera:
			_had_zoom_meta = _camera.has_meta("mountain_zoom")
			_old_zoom_meta = _camera.get_meta("mountain_zoom") if _had_zoom_meta else null
			_camera.set_meta("mountain_zoom",2.5)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_E and prompt.visible:
		claim_treasure(_actor)
		get_viewport().set_input_as_handled()
func claim_treasure(player: Node2D) -> bool:
	if not contains_actor(player) or unproject_floor(player.global_position).distance_to(Vector2(0.55,-7.35))>=1.75: return false
	if player.world_pickups_collected.has(PICKUP_ID):
		_set_collected(true)
		return false
	player.world_pickups_collected.append(PICKUP_ID)
	player.money += REWARD
	_set_collected(true)
	var sound := AudioStreamPlayer2D.new()
	sound.stream = ProceduralAudio.get_cash_register_stream()
	sound.bus = &"SFX"
	sound.volume_db = -13
	sound.position = project_floor(Vector2(0.55,-7.35))
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()
	if player.has_method("_show_weapon_notice"): player._show_weapon_notice("TESOURO DOS LOBOS ENCONTRADO · +$%d" % REWARD)
	treasure_claimed.emit(REWARD)
	return true
func _set_collected(value: bool) -> void:
	collected = value
	treasure_lid.rotation.x = -1.15 if value else 0.0
	gold.visible = not value
	if value: prompt.hide()
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
func _exit_tree() -> void:
	if is_instance_valid(_actor): _actor.remove_meta("mountain_shelter")
	if is_instance_valid(_camera):
		if _had_zoom_meta: _camera.set_meta("mountain_zoom",_old_zoom_meta)
		else: _camera.remove_meta("mountain_zoom")
