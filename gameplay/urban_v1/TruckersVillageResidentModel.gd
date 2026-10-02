extends "res://assets/CivilianModel.gd"
## Country clothes on the native human rig; locomotion remains distance-driven
## foot planting and two-bone IK, rather than spinning rigid arms and legs.
const POSE := preload("res://gameplay/WeaponPoseData.gd")
var resident_variant := 0
var weapon_id := "pistol"
var armed := false
var weapon: Node3D
var muzzle: Marker3D
var flash: MeshInstance3D
var recoil := 0.0
var flash_left := 0.0
var _country_materials := {}

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 770+resident_variant*13
	coat_color = [Color("874c3b"),Color("637655"),Color("546976"),Color("a18a63")][resident_variant%4]
	pants_color = Color("344853")
	wardrobe_overrides = {"female":resident_variant==1,"top":1,"bottom":0,"shoe":1,"shoe_color":Color("513b29"),"hat":0,"backpack":false,"bag":0,"glasses":false,"height":1.0}
	super._ready()
	_country_clothes()
	_build_weapon()
	hand_provider = _gun_hands

func _country_clothes() -> void:
	var head := anchor(head_node)
	head.name = "CowboyHat"
	var hat_color := Color("ae9468") if resident_variant%2==0 else Color("64503b")
	var brim := SurfaceTool.new()
	brim.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var a := float(i)*TAU/24
		var b := float(i+1)*TAU/24
		var centre := Vector3(0,1.738,0)
		var first := Vector3(cos(a)*.315,1.735+pow(absf(cos(a)),3)*.065,sin(a)*.265)
		var second := Vector3(cos(b)*.315,1.735+pow(absf(cos(b)),3)*.065,sin(b)*.265)
		for p in [centre,second,first]: brim.add_vertex(p)
	brim.generate_normals()
	var hat := MeshInstance3D.new()
	hat.mesh = brim.commit()
	var felt := _cloth(hat_color).duplicate()
	felt.cull_mode = BaseMaterial3D.CULL_DISABLED
	hat.material_override = felt
	head.add_child(hat)
	var crown := CylinderMesh.new()
	crown.top_radius = .128
	crown.bottom_radius = .158
	crown.height = .17
	crown.radial_segments = 16
	var top := MeshInstance3D.new()
	top.mesh = crown
	top.position.y = 1.82
	top.scale.z = .88
	top.material_override = _cloth(hat_color)
	head.add_child(top)
	_box(head,Vector3(0,1.768,.137),Vector3(.27,.045,.018),Color("493728"))
	_box(head,Vector3(0,1.905,0),Vector3(.045,.009,.18),hat_color.darkened(.25))
	var torso := anchor(spine)
	torso.name = "CountryShirtAndBelt"
	for side in [-1.0,1.0]:
		for y in [1.07,1.16,1.25,1.34]: _box(torso,Vector3(0,y,side*.133),Vector3(.35,.012,.015),coat_color.lightened(.25))
		for x in [-.12,0,.12]: _box(torso,Vector3(x,1.205,side*.143),Vector3(.014,.38,.013),coat_color.darkened(.28))
	if resident_variant in [0,3]:
		for x in [-.13,.13]: _box(torso,Vector3(x,1.23,.153),Vector3(.13,.37,.025),Color("5b4935"))
	_box(torso,Vector3(0,.975,0),Vector3(.36,.065,.265),Color("4b3828"))
	_box(torso,Vector3(0,.975,.145),Vector3(.082,.067,.025),Color("b79855"))
	_box(torso,Vector3(.215,.93,0),Vector3(.07,.18,.10),Color("513b29"))

func _cloth(color: Color) -> StandardMaterial3D:
	if not _country_materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .91
		_country_materials[color] = material
	return _country_materials[color]

func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> void:
	var local_part := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	local_part.mesh = shape
	local_part.position = at
	local_part.material_override = _cloth(color)
	parent.add_child(local_part)

func _build_weapon() -> void:
	weapon = Node3D.new()
	weapon.name = "ResidentShotgun" if weapon_id == "shotgun" else "ResidentPistol"
	add_child(weapon)
	var tip := preload("res://gameplay/ArsenalWeapon3D.gd").build(weapon,weapon_id)
	muzzle = Marker3D.new()
	muzzle.position = tip
	weapon.add_child(muzzle)
	flash = MeshInstance3D.new()
	var shape := SphereMesh.new()
	shape.radius = .045
	shape.height = .09
	shape.radial_segments = 8
	shape.rings = 3
	flash.mesh = shape
	flash.position = tip
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffc065")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash.material_override = material
	weapon.add_child(flash)
	flash.hide()
	weapon.hide()

func set_armed(value: bool) -> void:
	armed = value
	weapon.visible = value
	lod_enabled = not value
	if not value:
		hand_targets = [null,null]
		flash.hide()
		flash_left = 0

func _process(delta: float) -> void:
	if armed:
		recoil = move_toward(recoil,0,delta*.7)
		flash_left = maxf(0,flash_left-delta)
		flash.visible = flash_left>0
		var local_basis := Basis(Vector3.UP,PI)*Basis(Vector3.RIGHT,recoil)
		weapon.transform = Transform3D(local_basis,Vector3(.15,1.23,.30)-local_basis*POSE.GRIPS[weapon_id])
	super._process(delta)

func _gun_hands() -> Array:
	if not armed: return [null,null]
	return [weapon.to_global(POSE.SUPPORT_GRIPS[weapon_id]),weapon.to_global(POSE.GRIPS[weapon_id])]

func muzzle_position() -> Vector3:
	return muzzle.global_position

func attack() -> void:
	recoil = .17 if weapon_id == "shotgun" else .11
	flash_left = .055
