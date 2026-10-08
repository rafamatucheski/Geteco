extends Node
## One active hydraulic controller. Cargo retains its collider while lifted;
## swept shape queries reject walls and restore the carrier's last safe pose.
const MAX_LIFT := 3.4
const LIFT_RATE := 1.35
var vehicle: CharacterBody3D
var cargo: PhysicsBody3D
var lift := 0.0
var dump := 0.0
var _saved: Dictionary = {}
var _arm: Node3D
var _bucket: Node3D
var _anchor: Node3D
var _bed: Node3D
var _last_vehicle := Transform3D.IDENTITY
var _last_lift := 0.0
var _label: Label
var _was_active := false
var _hud_layer: CanvasLayer
var _hud_panel: PanelContainer
var _bucket_shape: CollisionShape3D
var _bucket_body: AnimatableBody3D
var rear: Node
var _released_load: WeakRef

func _ready() -> void:
	process_physics_priority = 12
	_arm = vehicle.visual.get_node_or_null("LoaderArm")
	if _arm != null:
		_bucket = _arm.get_node("Bucket")
		_anchor = _bucket.get_node("LoadAnchor")
		_bucket_shape = CollisionShape3D.new()
		_bucket_shape.name = "LoaderBucketCollision"
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.76,.30,1.5)
		_bucket_shape.shape = shape
		_bucket_body = AnimatableBody3D.new()
		_bucket_body.name = "LoaderBucketBody"
		_bucket_body.top_level = true
		_bucket_body.sync_to_physics = false
		_bucket_body.collision_layer = 4
		_bucket_body.collision_mask = 7
		vehicle.add_child(_bucket_body)
		_bucket_body.global_transform = vehicle.global_transform
		_bucket_body.add_child(_bucket_shape)
		_bucket_body.add_collision_exception_with(vehicle)
		vehicle.add_collision_exception_with(_bucket_body)
	_bed = vehicle.visual.get_node_or_null("DumpBed")
	if vehicle.archetype == "mining_backhoe":
		rear = preload("res://gameplay/mining/BackhoeHydraulics.gd").new()
		rear.name = "RearHydraulics"
		add_child(rear)
		rear.configure(vehicle)
	_last_vehicle = vehicle.global_transform
	add_to_group("mining_machine")
	vehicle.destroyed.connect(_carrier_destroyed)
	_update_model()
	# Idle industrial vehicles sleep alongside the base vehicle. Only this tiny
	# gate runs; no broad-phase scans, HUD nodes or load queries until occupied.

func active() -> bool:
	if not is_instance_valid(vehicle) or not vehicle.controlled or vehicle.external_input or vehicle.input_locked or vehicle.engine_disabled or vehicle.health <= 0: return false
	if get_tree().paused: return false
	var controls := get_node_or_null("/root/GameInput")
	if controls != null and controls.remapping: return false
	var world := vehicle.get_parent()
	var driving: Variant = world.get("driving")
	if driving != null:
		if not driving.occupied or driving.car != vehicle or driving.is_body_transition_active(): return false
		if driving.has_method("_external_transition_blocked") and driving._external_transition_blocked(): return false
	return true

func _unhandled_input(event: InputEvent) -> void:
	if not active() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_B and _anchor != null:
		if is_instance_valid(cargo): release_cargo()
		else: acquire_nearest()
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	_sync_bucket_collision()
	var enabled := active()
	if not enabled and is_instance_valid(cargo): release_cargo()
	_was_active = enabled
	if not enabled:
		if _arm != null and not vehicle.global_transform.is_equal_approx(_last_vehicle):
			if vehicle.health > 0 and vehicle.collision_layer != 0: operate(0.0,delta)
			else: _update_model()
		if is_instance_valid(_hud_panel): _hud_panel.hide()
		_last_vehicle = vehicle.global_transform
		return
	if not is_instance_valid(_label): _make_hud()
	_hud_panel.show()
	if is_instance_valid(cargo) and (cargo.is_queued_for_deletion() or (cargo.get("health") != null and float(cargo.get("health")) <= 0)): release_cargo()
	var direction := float(Input.is_physical_key_pressed(KEY_PAGEUP))-float(Input.is_physical_key_pressed(KEY_PAGEDOWN))
	operate(direction,delta)
	if rear != null:
		operate_rear(Vector4(
			float(Input.is_physical_key_pressed(KEY_O))-float(Input.is_physical_key_pressed(KEY_U)),
			float(Input.is_physical_key_pressed(KEY_END))-float(Input.is_physical_key_pressed(KEY_HOME)),
			float(Input.is_physical_key_pressed(KEY_INSERT))-float(Input.is_physical_key_pressed(KEY_DELETE)),
			float(Input.is_physical_key_pressed(KEY_PERIOD))-float(Input.is_physical_key_pressed(KEY_COMMA))),delta)
	if _bed != null:
		dump = move_toward(dump, 1.0 if Input.is_physical_key_pressed(KEY_N) else 0.0, delta*.42)
		_bed.rotation.x = -dump*.72
	_label.text = "PgUp / PgDn  Erguer / baixar pá     B  Prender / soltar carga" if _anchor != null else "N (segurar)  Inclinar caçamba"
	if is_instance_valid(cargo): _label.text += "     Carga presa"
	if rear != null:
		_label.text += "\nU / O  Girar traseira    Home / End  Braço    Ins / Del  Antebraço    , / .  Caçamba"
		if absf(vehicle.speed) > .65: _label.text += "\nPare para operar a traseira"

func _make_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 7
	add_child(_hud_layer)
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.add_child(overlay)
	_hud_panel = PanelContainer.new()
	_hud_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hud_panel.offset_left = -390
	_hud_panel.offset_right = 390
	_hud_panel.offset_top = -82 if rear != null else -60
	_hud_panel.offset_bottom = -18
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(.055,.065,.065,.94)
	panel.border_color = Color(.66,.53,.27,.85)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(6)
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 8
	panel.content_margin_bottom = 8
	_hud_panel.add_theme_stylebox_override("panel",panel)
	overlay.add_child(_hud_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size",16)
	_label.add_theme_color_override("font_color",Color("f7d27c"))
	_label.add_theme_color_override("font_shadow_color",Color("171714"))
	_label.add_theme_constant_override("shadow_offset_x",2)
	_label.add_theme_constant_override("shadow_offset_y",2)
	_hud_panel.add_child(_label)

## Also used by the deterministic contract test; production input calls this.
func operate(direction: float, delta: float) -> bool:
	if _arm == null: return false
	var previous := lift
	var previous_bucket := _bucket_shape.global_transform
	lift = clampf(lift+clampf(direction,-1,1)*maxf(delta,0)*LIFT_RATE,0,MAX_LIFT)
	_update_model()
	if is_equal_approx(previous,lift) and vehicle.global_transform.is_equal_approx(_last_vehicle): return false
	if not _bucket_motion_clear(previous_bucket) or not _rear_clear():
		lift = _last_lift
		vehicle.global_transform = _last_vehicle
		vehicle.speed = 0.0
		vehicle.horizontal_velocity = Vector3.ZERO
		vehicle.velocity = Vector3.ZERO
		_update_model()
		return false
	if is_instance_valid(cargo):
		var desired := _cargo_transform()
		if not _motion_clear(cargo,desired):
			lift = _last_lift
			vehicle.global_transform = _last_vehicle
			vehicle.speed = 0.0
			vehicle.horizontal_velocity = Vector3.ZERO
			vehicle.velocity = Vector3.ZERO
			_update_model()
			return false
		cargo.global_transform = desired
	_last_vehicle = vehicle.global_transform
	_last_lift = lift
	if rear != null: rear.accept_motion()
	return not is_equal_approx(lift,previous)

func _rear_clear() -> bool:
	return rear == null or vehicle.global_transform.is_equal_approx(_last_vehicle) or rear.carrier_motion_clear(_carrier_rids())

func operate_rear(direction: Vector4, delta: float) -> bool:
	if rear == null or absf(vehicle.speed) > .65 or vehicle.health <= 0 or vehicle.engine_disabled: return false
	return rear.operate(direction,delta,_carrier_rids())

func _bucket_motion_clear(previous: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _bucket_shape.shape
	query.transform = previous
	query.motion = _bucket_shape.global_position-previous.origin
	query.collision_mask = 7
	var excluded: Array[RID] = _carrier_rids()
	if is_instance_valid(cargo): excluded.append(cargo.get_rid())
	query.exclude = excluded
	var released := _withdrawal_load()
	var withdrawing := released != null and _separating_from(released,previous)
	# A just-released load keeps native physical contact with the scoop. The
	# extra arm query must let that existing
	# contact separate when withdrawing/lowering, instead of undoing every move.
	if withdrawing: query.exclude = excluded+[released.get_rid()]
	var state := vehicle.get_world_3d().direct_space_state
	var sweep := state.cast_motion(query)
	if not sweep.is_empty() and sweep[0] < .995: return false
	query.transform = _bucket_shape.global_transform
	query.motion = Vector3.ZERO
	query.exclude = excluded
	for hit in state.intersect_shape(query,8):
		if not withdrawing or hit.collider != released: return false
	return true

func _separating_from(body: PhysicsBody3D, previous: Transform3D) -> bool:
	if lift > _last_lift+.0001 or not previous.basis.is_equal_approx(_bucket_shape.global_basis): return false
	var before := previous.origin-body.global_position
	var after := _bucket_shape.global_position-body.global_position
	before.y=0; after.y=0
	return after.length_squared()+.00001 >= before.length_squared()

func _withdrawal_load() -> PhysicsBody3D:
	if _released_load == null: return null
	var body := _released_load.get_ref() as PhysicsBody3D
	if not is_instance_valid(body) or body.is_queued_for_deletion(): return null
	var wreck := body.get_node_or_null("WreckBody") as PhysicsBody3D
	var physical := wreck if wreck != null else body
	# Initial release has a tiny vertical clearance before gravity establishes
	# contact. Retain ownership history until the load leaves the support footprint,
	# not merely for a single overlap-free frame while it is falling onto the scoop.
	var radius := .85
	if body.get("half_length") != null: radius=Vector2(float(body.get("half_length")),float(body.get("half_width"))).length()
	var local := _bucket_shape.to_local(physical.global_position)
	var half: Vector3 = _bucket_shape.shape.size*.5
	if absf(local.x)>half.x+radius+.08 or absf(local.z)>half.z+radius+.08:
		_released_load=null
		return null
	return physical

func _sync_bucket_collision() -> void:
	if not is_instance_valid(_bucket_body): return
	var layer: int = vehicle.collision_layer if vehicle.health>0 else 0
	_bucket_body.collision_layer=layer
	_bucket_body.collision_mask=vehicle.collision_mask if layer!=0 else 0

func _carrier_destroyed() -> void:
	release_cargo()
	_sync_bucket_collision()

func _update_model() -> void:
	if _arm == null: return
	# Rotation raises the articulated boom; bucket stays level under its linkage.
	_arm.rotation.x = asin(clampf(lift/3.35,0,.94))
	_bucket.rotation.x = -_arm.rotation.x
	if _bucket_shape != null:
		_bucket_body.global_transform = vehicle.global_transform
		_bucket_shape.transform = vehicle.global_transform.affine_inverse()*_bucket.global_transform
		_bucket_shape.position += Vector3(0,.12,-.16)

func cargo_anchor() -> Vector3:
	return _anchor.global_position if is_instance_valid(_anchor) else vehicle.global_position

func _cargo_transform() -> Transform3D:
	var target := cargo.global_transform
	target.basis = vehicle.global_basis*Basis(Vector3.UP,float(_saved.get("relative_yaw",0.0)))
	var half_length := float(cargo.get("half_length")) if cargo.get("half_length") != null else .0
	target.origin = cargo_anchor()-vehicle.global_basis.z*half_length*.6
	# Match the actual supporting collider. The visual anchor sits below its
	# top; placing the load there made release start inside the scoop, trapping
	# the carrier between its load and the floor during collision recovery.
	var half: Vector3 = _bucket_shape.shape.size*.5
	var basis := _bucket_shape.global_basis
	var top := _bucket_shape.global_position.y+absf(basis.x.y)*half.x+absf(basis.y.y)*half.y+absf(basis.z.y)*half.z
	# Rocks have their origin at the centre; vehicles use the ground plane.
	target.origin.y = top+float(cargo.get_meta("mining_origin_height",.0))+.015
	return target

func eligible(body: PhysicsBody3D) -> bool:
	if body == null or body == vehicle or body.is_queued_for_deletion() or body.has_meta("mining_carried_by"): return false
	if body.collision_layer == 0 or not body.is_visible_in_tree(): return false
	if body is RigidBody3D: return body.is_in_group("mining_cargo") and not body.freeze
	if not body.is_in_group("drivable"): return false
	if body.controlled or body.external_input or body.traffic or body.health <= 0 or absf(body.speed) > .5: return false
	if body.input_locked or body.has_meta("awaiting_ground"): return false
	if body.get_meta("dispatch_unit",false) or body.get_meta("police_locked",false) or body.get_meta("passenger_transport",false): return false
	if preload("res://gameplay/DamageProtection.gd").is_protected(body): return false
	if str(body.archetype).begins_with("mining_"): return false
	var spec := preload("res://runtime/FleetCatalog.gd").spec(body.archetype)
	if float(spec.get("mass",1.0)) > 3.5: return false
	var world := vehicle.get_parent()
	var driving: Variant = world.get("driving")
	if driving != null and driving.occupied and driving.car == body: return false
	# A person standing on a candidate is a real obstacle, not a legal load.
	var volume := BoxShape3D.new()
	volume.size = Vector3(float(body.half_width)*2.0+.15,float(body.body_height)+1.8,float(body.half_length)*2.0+.15)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = volume
	query.transform = body.global_transform.translated(Vector3.UP*(float(body.body_height)*.5+.70))
	query.collision_mask = 2
	query.exclude = [body.get_rid()]+_carrier_rids()
	return vehicle.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func acquire_nearest() -> bool:
	if is_instance_valid(cargo) or _anchor == null or absf(vehicle.speed) > .65: return false
	var best: PhysicsBody3D
	var gap := 3.0
	var candidates := get_tree().get_nodes_in_group("mining_cargo")
	candidates.append_array(get_tree().get_nodes_in_group("drivable"))
	for candidate in candidates:
		if not candidate is PhysicsBody3D or not eligible(candidate): continue
		var offset: Vector3 = candidate.global_position-cargo_anchor()
		var distance := offset.length()
		if distance < gap and vehicle.to_local(candidate.global_position).z < -vehicle.half_length:
			gap = distance
			best = candidate
	return acquire(best)

func acquire(body: PhysicsBody3D) -> bool:
	if is_instance_valid(cargo) or _anchor == null or not eligible(body): return false
	if absf(vehicle.speed) > .65 or cargo_anchor().distance_to(body.global_position) > 3.0: return false
	cargo = body
	_saved = {"physics":body.is_physics_processing(),"relative_yaw":body.rotation.y-vehicle.rotation.y,"drivable":body.is_in_group("drivable")}
	if body is RigidBody3D:
		_saved["freeze"] = body.freeze
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	else:
		body.set_physics_process(false)
		body.velocity = Vector3.ZERO
		body.horizontal_velocity = Vector3.ZERO
		body.speed = 0.0
	var desired := _cargo_transform()
	if not _motion_clear(body,desired):
		release_cargo()
		return false
	body.set_meta("mining_carried_by",vehicle.get_instance_id())
	if body.has_signal("destroyed") and not body.is_connected("destroyed",_cargo_destroyed):
		body.connect("destroyed",_cargo_destroyed)
	if _saved.drivable: body.remove_from_group("drivable")
	body.add_collision_exception_with(_bucket_body)
	_bucket_body.add_collision_exception_with(body)
	body.add_collision_exception_with(vehicle)
	vehicle.add_collision_exception_with(body)
	body.global_transform = desired
	_last_vehicle = vehicle.global_transform
	_last_lift = lift
	return true

func _motion_clear(body: PhysicsBody3D, target: Transform3D) -> bool:
	var state := vehicle.get_world_3d().direct_space_state
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = child.shape
		query.transform = body.global_transform*child.transform
		query.motion = target.origin-body.global_position
		query.collision_mask = 7
		query.exclude = [body.get_rid()]+_carrier_rids()
		query.margin = .01
		var sweep := state.cast_motion(query)
		if not sweep.is_empty() and sweep[0] < .995: return false
		query.transform = target*child.transform
		query.motion = Vector3.ZERO
		if not state.intersect_shape(query,1).is_empty(): return false
	return true

func release_cargo() -> void:
	if not is_instance_valid(cargo): cargo = null; _saved.clear(); return
	var body := cargo
	if body.has_meta("mining_carried_by"): _released_load = weakref(body)
	if body.has_signal("destroyed") and body.is_connected("destroyed",_cargo_destroyed):
		body.disconnect("destroyed",_cargo_destroyed)
	body.remove_meta("mining_carried_by")
	if bool(_saved.get("drivable",false)): body.add_to_group("drivable")
	if is_instance_valid(_bucket_body):
		body.remove_collision_exception_with(_bucket_body)
		_bucket_body.remove_collision_exception_with(body)
	body.remove_collision_exception_with(vehicle)
	if is_instance_valid(vehicle): vehicle.remove_collision_exception_with(body)
	if body is RigidBody3D:
		body.freeze = bool(_saved.get("freeze",false))
		body.sleeping = false
		body.linear_velocity = Vector3.ZERO
	else:
		# Native death transfers motion to WreckBody. Never run its old character
		# controller in parallel with the rigid wreck or overwrite its transform.
		if body.get_node_or_null("WreckBody") == null:
			body.set_physics_process(bool(_saved.get("physics",true)))
		body.velocity = Vector3.DOWN*.1
		body.horizontal_velocity = Vector3.ZERO
		body.speed = 0.0
		body.brake_input = true
		preload("res://gameplay/mining/MiningDroppedLoad.gd").attach(body)
	cargo = null
	_saved.clear()

func _cargo_destroyed() -> void:
	# Vehicle emits destroyed before VehicleDamage creates its rigid wreck.
	# Release now so the native death system captures the restored driver state.
	release_cargo()

func _carrier_rids() -> Array[RID]:
	var result: Array[RID] = [vehicle.get_rid()]
	if is_instance_valid(_bucket_body): result.append(_bucket_body.get_rid())
	return result

func _exit_tree() -> void:
	release_cargo()
	if is_instance_valid(_bucket_body) and not vehicle.is_queued_for_deletion(): _bucket_body.queue_free()
