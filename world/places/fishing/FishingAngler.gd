extends "res://scripts/Actor.gd"
## Native civilian, physical capsule, ordinary damage and a two-hand rod pose.
const CIVILIAN_KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
var water_target := Vector3.ZERO
var person: Node3D
var _head: Node3D
var _rod: Node3D
var _line: MeshInstance3D
var _float: MeshInstance3D
var _home := Vector3.ZERO
var _facing := 0.0
var _time := 0.0
var _fear := 0.0
var _active := true
var _gameplay: Node
var _supported := false
var _catch_timer := 0.0
var _catch_fish: Node3D
var _fish_material: StandardMaterial3D
var _idle_reel := 0.0
var _idle_glance := 0.0
var _idle_lift := 0.0

func _ready() -> void:
	super._ready()
	controlled_automatically = true
	set_meta("authored_population_owner","lago_sereno")
	set_meta("civilian_reaction_lod",true)
	add_to_group("fishing_angler")
	add_to_group("v2_damageable")
	_home = global_position
	person = visual.get_child(0)
	_head = person.get("head_node") as Node3D
	var direction := water_target-global_position
	_facing = atan2(-direction.x,-direction.z)
	visual.rotation.y = _facing
	_build_fisher_details()
	_rod = Node3D.new()
	_rod.name = "FishingRod"
	person.add_child(_rod)
	_segment(_rod,Vector3(0,1.06,.14),Vector3(0,1.26,.43),.035,Color("9a7148"))
	_segment(_rod,Vector3(0,1.24,.40),Vector3(.02,2.05,2.58),.013,Color("3c4240"))
	_segment(_rod,Vector3(-.032,1.195,.35),Vector3(.032,1.22,.39),.027,Color("55432f"))
	_add_reel()
	person.hand_provider = _hands
	_line = _segment(self,Vector3.ZERO,Vector3.UP,.008,Color("d8d2af"))
	_line.name = "FishingLine"
	_float = MeshInstance3D.new()
	var bobber := SphereMesh.new()
	bobber.radius = .085
	bobber.height = .19
	bobber.radial_segments = 8
	bobber.rings = 4
	_float.mesh = bobber
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("d78051")
	_float.material_override = material
	_float.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_float)
	_build_catch_fish()
	_time = float(identity)*.71
	_update_gear()

func _build_catch_fish() -> void:
	_catch_fish = Node3D.new()
	_catch_fish.name = "CaughtFish"
	add_child(_catch_fish)
	_fish_material = StandardMaterial3D.new()
	_fish_material.albedo_color = Color("94a99a")
	_fish_material.roughness = .56
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .13
	mesh.height = .34
	mesh.radial_segments = 10
	mesh.rings = 5
	body.mesh = mesh
	body.scale = Vector3(.86,.65,1.38)
	body.material_override = _fish_material
	_catch_fish.add_child(body)
	var tail := MeshInstance3D.new()
	var fin := CylinderMesh.new()
	fin.top_radius = .02
	fin.bottom_radius = .11
	fin.height = .11
	fin.radial_segments = 4
	tail.mesh = fin
	tail.rotation.x = PI*.5
	tail.position.z = -.25
	tail.material_override = _fish_material
	_catch_fish.add_child(tail)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color("18201e")
	for side in [-1.0,1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = .015
		eye_mesh.height = .03
		eye_mesh.radial_segments = 6
		eye_mesh.rings = 3
		eye.mesh = eye_mesh
		eye.position = Vector3(side*.08,.02,.14)
		eye.material_override = eye_material
		_catch_fish.add_child(eye)
	_catch_fish.hide()

func _build_fisher_details() -> void:
	# Use the civilian kit's own cap mesh and palette so the anglers keep the
	# same natural proportions and shared mesh cache as the rest of the crowd.
	var wardrobe: Dictionary = person.wardrobe
	person.head_node.mesh = CIVILIAN_KIT.head_mesh(
		bool(wardrobe.get("female",false)),int(wardrobe.get("hair",0)),
		int(wardrobe.get("beard",0)),1,bool(wardrobe.get("glasses",false)))
	wardrobe.hat = 1
	person.wardrobe = wardrobe
	# A muted shoulder strap and one tackle pocket give each fisher a distinct,
	# readable fishing outfit without adding another animated rig or collider.
	var strap_colors := [Color("b28b50"),Color("71836a"),Color("a66d4d"),Color("858c7c"),Color("b49a70")]
	var strap := _segment(person.spine,Vector3(-.10,.30,.078),Vector3(.085,-.13,.09),.012,strap_colors[posmod(identity,strap_colors.size())])
	strap.name = "TackleStrap"
	strap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pocket := MeshInstance3D.new()
	pocket.name = "TacklePocket"
	var pocket_mesh := BoxMesh.new()
	pocket_mesh.size = Vector3(.052,.065,.018)
	pocket.mesh = pocket_mesh
	pocket.position = Vector3(-.06,.055,.102)
	var pocket_material := StandardMaterial3D.new()
	pocket_material.albedo_color = Color("354a3a")
	pocket_material.roughness = .9
	pocket.material_override = pocket_material
	pocket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	person.spine.add_child(pocket)
	var button := MeshInstance3D.new()
	button.name = "TacklePocketSnap"
	var button_mesh := SphereMesh.new()
	button_mesh.radius = .009
	button_mesh.height = .012
	button_mesh.radial_segments = 6
	button_mesh.rings = 3
	button.mesh = button_mesh
	button.position = Vector3(-.06,.055,.114)
	var button_material := StandardMaterial3D.new()
	button_material.albedo_color = Color("c9aa64")
	button_material.metallic = .25
	button_material.roughness = .55
	button.material_override = button_material
	button.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	person.spine.add_child(button)

func _add_reel() -> void:
	var reel := MeshInstance3D.new()
	reel.name = "FishingReel"
	var spool := CylinderMesh.new()
	spool.top_radius = .038
	spool.bottom_radius = .038
	spool.height = .045
	spool.radial_segments = 10
	reel.mesh = spool
	reel.position = Vector3(.055,1.14,.255)
	reel.rotation.z = PI*.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("4a514a")
	material.metallic = .35
	material.roughness = .48
	reel.material_override = material
	reel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rod.add_child(reel)

func show_catch(fish: Dictionary) -> void:
	if dead or _fear>0: return
	var definition := preload("res://activities/fishing/FishingRules.gd").definition(str(fish.get("id","")))
	if definition.is_empty(): return
	_fish_material.albedo_color = definition.color
	_catch_fish.scale = Vector3.ONE*clampf(.55+float(fish.get("grams",1000))/16000.0,.6,1.4)
	_catch_timer = 4.0

func bind_gameplay(gameplay: Node) -> void:
	if gameplay == null or _gameplay == gameplay: return
	_gameplay = gameplay
	if gameplay.has_signal("weapon_fired"): gameplay.weapon_fired.connect(_weapon_fired)
	if gameplay.has_signal("explosion_occurred"): gameplay.explosion_occurred.connect(_explosion)

func set_active(active: bool) -> void:
	_active = active
	set_physics_process((active or _fear>0) and not dead)
	if is_instance_valid(person): person.set_process(active and not dead)

func _physics_process(delta: float) -> void:
	if dead: return
	# Exterior admission can precede the surrounding streamed land by a frame.
	if not _supported:
		var support := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.2,global_position-Vector3.UP*.3,1)
		if get_world_3d().direct_space_state.intersect_ray(support).is_empty(): return
		_supported = true
	_time += delta
	_catch_timer = maxf(0,_catch_timer-delta)
	_fear = maxf(0,_fear-delta)
	# A short recoil along the dry strip cannot send an angler into the pond.
	var away := _home-water_target
	away.y = 0
	var target := _home+away.normalized()*1.0 if _fear>0 else _home
	var offset := target-global_position
	offset.y = 0
	automatic_direction = offset.normalized() if offset.length()>.10 else Vector3.ZERO
	speed = 1.5
	super._physics_process(delta)
	if _fear <= 0 and automatic_direction.is_zero_approx(): visual.rotation.y = _facing
	person.hand_provider = _hands if _fear<=0 else Callable()
	_rod.visible = _fear<=0
	_line.visible = _fear<=0
	_float.visible = _fear<=0
	_catch_fish.visible = _fear<=0 and _catch_timer>0
	if _fear<=0: _update_gear()
	if not _active and _fear<=0: set_active(false)

func _hands() -> Array:
	# Keep both hands on the handle but on opposite sides of the chest. The old
	# same-side, far-forward targets forced the IK to lock both elbows straight.
	var catch_look := 0.0
	if _catch_timer > 0.0:
		catch_look = 1.0 - smoothstep(.65, 2.2, 4.0 - _catch_timer)
	if is_instance_valid(_head):
		# CivilianModel rebuilds its base pose before requesting hand targets, so
		# these small offsets don't accumulate or replace the shared rig pose.
		_head.rotate_x(_idle_glance * .10 + _idle_lift * .06 + catch_look * .15)
		_head.rotate_y(_idle_glance * sin(_time * .55 + float(identity)) * .035)
	return [_rod.to_global(Vector3(-.025,1.205,.37)),_rod.to_global(Vector3(.025,1.105,.22))]

func _update_gear() -> void:
	# Stagger short, quiet actions across the five fishers. The same phase drives
	# the rod, float and gaze; it adds no per-frame node scans or particles.
	var phase := fposmod(_time + float(identity % 5) * 3.2, 18.0)
	_idle_reel = _pulse(phase, 2.1, 2.45, 3.55, 4.05)
	_idle_glance = _pulse(phase, 7.0, 7.4, 8.15, 8.75)
	_idle_lift = _pulse(phase, 12.3, 12.7, 13.3, 13.85)
	var lifted := clampf((4.0-_catch_timer)*1.4,0,1) if _catch_timer>0 else 0.0
	var catch_age := 4.0 - _catch_timer if _catch_timer > 0.0 else 4.0
	var catch_snap := (1.0 - smoothstep(0.0, .42, catch_age)) if _catch_timer > 0.0 else 0.0
	_rod.rotation.x = sin(_time*.7)*.022 + sin(_time*.29+float(identity))*.009 \
		-_idle_reel*.085 - _idle_lift*.12 - lifted*.33 - catch_snap*.045
	_rod.rotation.z = sin(_time*.48+float(identity))*.016 + _idle_glance*.012
	var bobber := water_target+Vector3.UP*(.04+sin(_time*1.4)*.014)
	var hand_height: Vector3 = person.to_global(Vector3(0,1.10,.30))
	bobber = bobber.lerp(hand_height, _idle_reel * .055)
	bobber.y += _idle_lift * .025
	if _catch_timer>0:
		var landed: Vector3 = person.to_global(Vector3(.17,1.15,.95))
		bobber = bobber.lerp(landed,lifted)
		_catch_fish.global_position = bobber-Vector3.UP*.25
		_catch_fish.global_rotation = person.global_rotation + Vector3(0,0,sin(_time*12)*.17)
	_float.visible = _catch_timer<=0
	_float.global_position = bobber
	var start := _rod.to_global(Vector3(.02,2.05,2.58))
	var difference := bobber-start
	_line.global_position = (start+bobber)*.5
	_line.global_basis = Basis(Quaternion(Vector3.UP,difference.normalized()))
	_line.scale = Vector3(1,difference.length(),1)

func _pulse(phase: float, start: float, attack_end: float, release_start: float, end: float) -> float:
	return smoothstep(start, attack_end, phase) * (1.0 - smoothstep(release_start, end, phase))

func _weapon_fired(_id: String,origin: Vector3) -> void:
	if global_position.distance_squared_to(origin)<40*40: _alert()

func _explosion(origin: Vector3,radius: float,_source: Node) -> void:
	if global_position.distance_to(origin)<maxf(45,radius*3): _alert()

func _alert() -> void:
	if dead: return
	_fear = 7.0
	set_physics_process(true)
	if is_instance_valid(person): person.set_process(true)

func receive_damage(amount: float,source: Node = null) -> void:
	super.receive_damage(amount,source)
	if dead:
		person.hand_provider = Callable()
		_rod.hide()
		_line.hide()
		_float.hide()
		_catch_fish.hide()
	else: _alert()

func _segment(parent: Node3D,a: Vector3,b: Vector3,radius: float,color: Color) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius*.7
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = cylinder
	mesh.position = (a+b)*.5
	mesh.basis = Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .75
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh
