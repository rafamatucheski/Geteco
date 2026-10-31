extends "res://world/places/sewers/SewerHomelessModel.gd"
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")
const POSE := preload("res://gameplay/WeaponPoseData.gd")
var weapon_id := "fists"
var armed := false
var weapon: Node3D
var muzzle: Marker3D
var flash: MeshInstance3D
var _attack_left := 0.0
var _flash_left := 0.0
var _right_hand := Vector3(.22, 1.24, .3)
var _left_hand := Vector3(-.22, 1.24, .3)

func _ready() -> void:
	super._ready()
	weapon = Node3D.new()
	weapon.name = "SewerWeapon_" + weapon_id
	add_child(weapon)
	var tip := Vector3.ZERO
	if weapon_id in ["knife", "pistol"]:
		tip = ARSENAL.build_cached(weapon, weapon_id)
	elif weapon_id == "bottle":
		_build_bottle()
	elif weapon_id == "claw":
		_part(Vector3(0, 0, 0), Vector3(.10, .04, .07), Color("665447"))
		for x in [-.035, 0.0, .035]:
			_part(Vector3(x, 0, -.13), Vector3(.012, .015, .22), Color("89918a"))
	muzzle = Marker3D.new()
	muzzle.position = tip
	weapon.add_child(muzzle)
	if weapon_id == "pistol":
		flash = _part(tip, Vector3(.055, .055, .10), Color("ffd380"))
		flash.material_override.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash.hide()
	weapon.hide()
	hand_provider = _combat_hands

func _part(at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .65
	part.material_override = material
	part.position = at
	weapon.add_child(part)
	return part

func _build_bottle() -> void:
	# Vidro escuro opaco com uma borda quebrada realmente serrilhada, segurado pelo gargalo.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a := TAU*i/10.0
		var b := TAU*(i+1)/10.0
		var near_a := Vector3(cos(a)*.025, sin(a)*.025, .04)
		var near_b := Vector3(cos(b)*.025, sin(b)*.025, .04)
		var far_a := Vector3(cos(a)*.055, sin(a)*.055, -.20-(.055 if i%2 == 0 else 0))
		var far_b := Vector3(cos(b)*.055, sin(b)*.055, -.20-(.055 if (i+1)%2 == 0 else 0))
		for vertex in [near_a, far_b, near_b, near_a, far_a, far_b]: surface.add_vertex(vertex)
	surface.generate_normals()
	var glass := MeshInstance3D.new()
	glass.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("365942")
	material.roughness = .25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = material
	weapon.add_child(glass)

func set_armed(value: bool) -> void:
	armed = value
	weapon.visible = value and weapon_id != "fists"
	lod_enabled = not value
	if not value:
		hand_targets = [null, null]
		_attack_left = 0
		_flash_left = 0
		if flash != null: flash.hide()

func attack() -> void:
	_attack_left = .55

func fire() -> void:
	_flash_left = .06

func muzzle_position() -> Vector3:
	return muzzle.global_position

func _process(delta: float) -> void:
	_attack_left = maxf(0, _attack_left-delta)
	_flash_left = maxf(0, _flash_left-delta)
	if flash != null: flash.visible = _flash_left > 0
	if armed:
		var swing := sin(clampf((.55-_attack_left)/.55, 0, 1)*PI) if _attack_left > 0 else 0.0
		_right_hand = Vector3(.22-swing*.1, 1.24, .3+swing*.43)
		if weapon_id == "pistol": _right_hand = Vector3(.16, 1.22, .28-_flash_left*.7)
		_left_hand = Vector3(-.22, 1.24, .3)
		var basis := Basis(Vector3.UP, PI)
		if weapon_id != "pistol": basis *= Basis(Vector3.RIGHT, -.5+swing*.9)
		var grip: Vector3 = POSE.GRIPS.get(weapon_id, Vector3.ZERO)
		weapon.transform = Transform3D(basis, _right_hand-basis*grip)
	super._process(delta)

func _combat_hands() -> Array:
	if not armed: return [null, null]
	if weapon_id == "pistol":
		return [weapon.to_global(POSE.SUPPORT_GRIPS.pistol), weapon.to_global(POSE.GRIPS.pistol)]
	return [to_global(_left_hand), to_global(_right_hand)]
