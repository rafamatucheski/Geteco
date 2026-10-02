extends CharacterBody3D
## Park residents use the same shared mesh kit, proportions and IK as street NPCs.
## Configure before adding to the tree; position is the floor under the seat/body.
## Bounds are in `deck` coordinates (or the parent when deck is omitted).
const MODEL := preload("res://assets/CivilianModel.gd")
const FALL := preload("res://gameplay/CharacterFallPresentation3D.gd")
const PROTECTION := preload("res://gameplay/DamageProtection.gd")
signal threatened(actor: CharacterBody3D)
signal died(actor: CharacterBody3D)

var health := 100.0
var dead := false
var frightened := false
var visual: Node3D
var model: Node3D
var gameplay: Node
var seated := false
var seat_height := .45
var drinking := false
var identity := 0
var jersey := Color("d86729")
var deck: Node3D
var bounds := Rect2()
var flee_radius := 9.0
## Still actors settle their seated pose, then stop the model's per-frame IK
## until a threat or hit needs animation again (bleacher fans).
var still := false
var _settle := .6
var state := "watching"
var _shape: CollisionShape3D
var _upright: CapsuleShape3D
var _home := Vector3.ZERO
var _home_yaw := 0.0
var _threat := Vector3.ZERO
var _target := Vector3.ZERO
var _quiet := 0.0
var _think := 0.0
var _rise_distance := 0.0
var _rise_allowed := false
var _bottle: Node3D
static var _bottle_body: CylinderMesh
static var _bottle_neck: CylinderMesh
static var _bottle_material: StandardMaterial3D

func configure(options: Dictionary) -> void:
	identity = int(options.get("identity", 0))
	jersey = options.get("jersey", jersey)
	seated = bool(options.get("seated", false))
	seat_height = float(options.get("seat_height", .45))
	drinking = bool(options.get("drinking", false))
	deck = options.get("deck")
	bounds = options.get("bounds", Rect2())
	flee_radius = clampf(float(options.get("flee_radius", 9.0)), .5, 15.0)
	still = bool(options.get("still", false))

func _ready() -> void:
	add_to_group("motocross_spectator")
	add_to_group("v2_damageable")
	# Own bounded movement; the street crowd director must not seize this actor.
	set_meta("gameplay_role", "motocross_spectator")
	set_meta("reaction_exempt", true)
	set_meta("impact_material", "flesh")
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .25
	_home = global_position
	_home_yaw = rotation.y
	_target = _home
	_upright = CapsuleShape3D.new()
	_upright.radius = .27
	_upright.height = 1.72
	_shape = CollisionShape3D.new()
	_shape.shape = _upright
	_shape.position.y = .88
	add_child(_shape)
	if seated:
		var sitting := CapsuleShape3D.new()
		sitting.radius = .27
		sitting.height = .86
		_shape.shape = sitting
		_shape.position.y = seat_height + .47
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	model = MODEL.new()
	model.name = "CivilianModel"
	model.appearance_locked = true
	model.appearance_variant = 120 + posmod(identity, 6)
	model.coat_color = jersey
	model.pants_color = Color("293444")
	# Long sleeves, trousers and boots are existing wardrobe cuts, not new humans.
	model.wardrobe_overrides = {"female": false, "build": 1, "height": 1.0,
		"top": 2, "bottom": 0, "shoe": 1, "hat": 0, "backpack": false,
		"bag": 0, "glasses": false, "inner": Color("e9e7dc"),
		"accent": jersey.lightened(.3), "shoe_color": Color("252a2d")}
	model.rotation.y = PI
	model.sit_amount = 1.0 if seated else 0.0
	model.seat_height = seat_height
	model.hand_provider = _hands
	visual.add_child(model)
	if drinking: _build_bottle()
	# Idle actors need no physics loop. CivilianModel keeps its existing pose LOD.
	set_physics_process(false)
	set_process(still)

func _process(delta: float) -> void:
	_settle -= delta
	if _settle > 0.0: return
	set_process(false)
	if not frightened and not dead and model._hit == Vector2.ZERO: model.set_process(false)

func bind_combat(owner_gameplay: Node) -> void:
	if gameplay == owner_gameplay: return
	_disconnect_combat()
	gameplay = owner_gameplay
	if not is_instance_valid(gameplay): return
	for entry in [["weapon_fired", _weapon_fired], ["npc_gunfire", _npc_gunfire], ["explosion_occurred", _explosion]]:
		if gameplay.has_signal(entry[0]): gameplay.connect(entry[0], entry[1])

func _disconnect_combat() -> void:
	if not is_instance_valid(gameplay): return
	for entry in [["weapon_fired", _weapon_fired], ["npc_gunfire", _npc_gunfire], ["explosion_occurred", _explosion]]:
		if gameplay.has_signal(entry[0]) and gameplay.is_connected(entry[0], entry[1]): gameplay.disconnect(entry[0], entry[1])

func _exit_tree() -> void: _disconnect_combat()

func _weapon_fired(weapon_id: String, origin: Vector3) -> void:
	if weapon_id in ["fists", "grenade"]: return
	var data: Dictionary = gameplay.weapon_data(weapon_id) if gameplay.has_method("weapon_data") else {}
	notice_threat(origin, 13.0 if data.get("suppressed", false) else 30.0)

func _npc_gunfire(origin: Vector3, _direction: Vector3, _shooter: Node3D) -> void:
	notice_threat(origin, 30.0)

func _explosion(origin: Vector3, radius: float, _source: Node) -> void:
	notice_threat(origin, maxf(30.0, radius * 2.0))

func notice_threat(origin: Vector3, radius := 30.0) -> void:
	if dead or not is_inside_tree() or global_position.distance_squared_to(origin) > radius * radius: return
	_threat = origin
	_quiet = 7.0
	if not dead: model.set_process(true)
	_think = 0.0
	if not frightened:
		frightened = true
		state = "rising" if seated else "fleeing"
		if seated:
			var exit_step := -global_basis.z * .8
			_rise_allowed = _safe_motion(exit_step) and _can_stand(global_position + exit_step)
		threatened.emit(self)
	if is_instance_valid(_bottle): _bottle.hide()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if dead: return
	_quiet = maxf(0.0, _quiet - delta)
	if seated:
		# Slide clear of the bench with the seated torso capsule before expanding.
		# If blocked by a table/wall, stay seated and protect the head instead.
		var step := -global_basis.z * minf(.9 * delta, maxf(0.0, .8 - _rise_distance))
		if _rise_allowed and _rise_distance < .8 and _safe_motion(step):
			velocity = step / maxf(delta, .001)
			var previous := global_position
			move_and_slide()
			_rise_distance += previous.distance_to(global_position)
		else: velocity = Vector3.ZERO
		if _can_stand():
			seated = false
			_shape.shape = _upright
			_shape.position.y = .88
			state = "fleeing"
		elif _quiet <= 0.0:
			# Never slide back through the bench or teleport into the old pose.
			frightened = false
			state = "watching"
			if is_instance_valid(_bottle): _bottle.show()
			set_physics_process(false)
		return
	model.sit_amount = move_toward(float(model.sit_amount), 0.0, delta * 3.0)
	_think -= delta
	if _think <= 0.0:
		_think = .35
		_target = _choose_escape() if _quiet > 0.0 else global_position
	var toward := _target - global_position
	toward.y = 0.0
	var direction := toward.normalized() if toward.length() > .15 else Vector3.ZERO
	var movement := direction * minf(2.8 * delta, toward.length())
	if not _safe_motion(movement):
		movement = Vector3.ZERO
		_think = minf(_think, .08)
	velocity.x = movement.x / maxf(delta, .001)
	velocity.z = movement.z / maxf(delta, .001)
	velocity.y = -1.0 if is_on_floor() else velocity.y - 20.0 * delta
	move_and_slide()
	if movement.length_squared() > .00001:
		state = "fleeing"
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-9.0 * delta))
	else: state = "sheltering"
	if _quiet <= 0.0 and is_on_floor():
		frightened = false
		state = "watching"
		velocity = Vector3.ZERO
		set_physics_process(false)

func _can_stand(at := Vector3.INF) -> bool:
	if at == Vector3.INF: at = global_position
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _upright
	query.transform = Transform3D(global_basis, at + Vector3.UP * .88)
	query.collision_mask = 7
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _inside_limits(point: Vector3) -> bool:
	if bounds.has_area():
		var anchor: Node3D = deck if is_instance_valid(deck) else get_parent() as Node3D
		var local: Vector3 = anchor.to_local(point) if anchor != null else point
		# Bounds describe walkable deck, with a capsule-radius margin inside it.
		if not bounds.grow(-.28).has_point(Vector2(local.x, local.z)): return false
	var flat := point - _home
	flat.y = 0.0
	return flat.length_squared() <= flee_radius * flee_radius

func _safe_motion(movement: Vector3) -> bool:
	if movement.is_zero_approx(): return true
	if not _inside_limits(global_position + movement): return false
	if test_move(global_transform, movement): return false
	# Floor probes at both sides prevent a center-only probe walking off a deck.
	var side := Vector3(-movement.z, 0, movement.x).normalized() * .25
	for offset in [Vector3.ZERO, side, -side]:
		var point: Vector3 = global_position + movement + offset
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .20, point - Vector3.UP * .30, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < .7: return false
	return true

func _choose_escape() -> Vector3:
	var away := global_position - _threat
	away.y = 0.0
	if away.length_squared() < .01: away = -global_basis.z
	away = away.normalized()
	var best := global_position
	var score := global_position.distance_squared_to(_threat)
	for angle in [0.0, -.65, .65, -1.25, 1.25, -1.9, 1.9]:
		var direction := away.rotated(Vector3.UP, angle)
		# Small, checked steps, no global nav queries and no route through solids.
		var step := direction * .65
		if not _safe_motion(step): continue
		var candidate := global_position + step
		var value := candidate.distance_squared_to(_threat)
		if value > score:
			score = value
			best = candidate
	return best

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0.0 or PROTECTION.is_protected(self): return
	health = maxf(0.0, health - amount)
	var impact := global_position - (source as Node3D).global_position if source is Node3D else -global_basis.z
	if health <= 0.0:
		dead = true
		state = "dead"
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		model.set_process(false)
		if is_instance_valid(_bottle): _bottle.hide()
		if has_meta("v2_burning"): preload("res://gameplay/BurningActor.gd").char_body(self)
		# On boats fall toward the deck center, not outward over the gunwale.
		if is_instance_valid(deck): impact = deck.to_global(Vector3(bounds.get_center().x, 0, bounds.get_center().y)) - global_position
		FALL.apply_fall(self, visual, impact)
		died.emit(self)
	else:
		model.set_process(true)
		model.take_hit(impact, clampf(amount / 35.0, .3, 1.0))
		notice_threat((source as Node3D).global_position if source is Node3D else global_position, INF)
	if is_instance_valid(gameplay):
		if is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source() and gameplay.has_method("report_vehicle_assault"):
			gameplay.report_vehicle_assault(self, source)
		var emergency: Node = gameplay.get("emergency")
		if is_instance_valid(emergency): emergency.report_injury(self, dead)

func recover_from_injury() -> void:
	if not dead: health = maxf(health, 60.0)

func _hands() -> Array:
	if frightened:
		var y := seat_height + 1.03 if seated else 1.55
		return [model.to_global(Vector3(-.18, y, .17)), model.to_global(Vector3(.18, y, .17))]
	if not drinking: return [null, null]
	var phase: float = fposmod(float(model.clock) + float(identity) * 1.7, 10.0)
	var sip := smoothstep(2.0, 3.0, phase) * (1.0 - smoothstep(4.0, 5.0, phase))
	var hip := seat_height + .08 if seated else .94
	var hand := Vector3(.21, hip + lerpf(.23, .59, sip), lerpf(.29, .24, sip))
	if is_instance_valid(_bottle):
		_bottle.position = hand + Vector3(0, .04, 0)
		_bottle.rotation.x = -sip * 1.25
	var seated_hand: Variant = null
	if seated: seated_hand = model.to_global(Vector3(-.21, hip + .05, .30))
	return [seated_hand, model.to_global(hand)]

func _build_bottle() -> void:
	if _bottle_body == null:
		_bottle_body = CylinderMesh.new()
		_bottle_body.top_radius = .032
		_bottle_body.bottom_radius = .035
		_bottle_body.height = .15
		_bottle_body.radial_segments = 10
		_bottle_body.rings = 0
		_bottle_neck = CylinderMesh.new()
		_bottle_neck.top_radius = .013
		_bottle_neck.bottom_radius = .024
		_bottle_neck.height = .09
		_bottle_neck.radial_segments = 10
		_bottle_neck.rings = 0
		_bottle_material = StandardMaterial3D.new()
		_bottle_material.albedo_color = Color("67421f")
		_bottle_material.roughness = .24
	_bottle = Node3D.new()
	_bottle.name = "BeerBottle"
	model.add_child(_bottle)
	for part in [[_bottle_body, 0.0], [_bottle_neck, .12]]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = part[0]
		mesh.position.y = part[1]
		mesh.material_override = _bottle_material
		_bottle.add_child(mesh)
