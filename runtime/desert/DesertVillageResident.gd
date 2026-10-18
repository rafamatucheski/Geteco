extends "res://scripts/Actor.gd"
## Stationary domestic routines retain the real Actor body and native rig.
const HOME_MODEL := preload("res://runtime/desert/DesertVillageResidentModel.gd")
const HUMAN_KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
signal home_resident_died
var specification: Dictionary={}
var home_activity := "read"
var home_model: Node3D
var held_prop: Node3D
var _death_notified := false

func _ready() -> void:
	name=str(specification.get("name","SantaLuaResident"))
	identity=int(specification.get("appearance",{}).get("variant",9730))
	home_activity=str(specification.get("activity","read"))
	controlled_automatically=true
	# Update the held spoon after the rig has solved its hands this frame.
	process_priority=1
	automatic_direction=Vector3.ZERO
	set_meta("gameplay_role","civilian")
	set_meta("desert_village_resident",true)
	set_meta("reaction_exempt",true)
	add_to_group("police_witness")
	add_to_group("v2_damageable")
	add_to_group("desert_village_resident")
	collision_layer=2
	collision_mask=7
	floor_snap_length=.3
	visual=Node3D.new()
	visual.name="Visual"
	add_child(visual)
	home_model=HOME_MODEL.new()
	home_model.appearance_locked=true
	home_model.appearance_variant=identity
	home_model.lod_enabled=false
	home_model.home_activity=home_activity
	var look: Dictionary=specification.get("appearance",{})
	home_model.coat_color=Color(str(look.get("coat",look.get("shirt","80715c"))))
	home_model.pants_color=Color(str(look.get("pants","3f4644")))
	home_model.wardrobe_overrides={"female":bool(look.get("female",false)),"height":1.0,"build":0,"top":1,"bottom":0,"shoe":0,"hat":0,"backpack":false,"bag":0,"glasses":false}
	if look.has("skin"): home_model.wardrobe_overrides.skin=Color(str(look.skin))
	# Corpo Meshy de pedestre do mesmo sexo; o guarda-roupa acima só vale sem corpo compatível.
	preload("res://assets/civilians/CivilianBodyCatalog.gd").apply_keeping_sex(home_model,identity)
	visual.add_child(home_model)
	if home_activity=="sleep":
		visual.rotation.x=-PI*.5
		_add_sleep_collision()
		set_physics_process(false)
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius=.30
		capsule.height=1.72
		var collision := CollisionShape3D.new()
		collision.shape=capsule
		collision.position=Vector3(0,.87,0)
		add_child(collision)
		home_model.hand_provider=_hand_targets
		_create_prop()
	last_position=global_position
	home_model.teleported()

func _add_sleep_collision() -> void:
	# Feet are +.87 m from the bed centre; the two blocks separately respect
	# mattress and higher pillow, instead of suspending a walking capsule.
	for row in [[Vector3(0,.02,-.74),Vector3(.58,.28,1.35)],
		[Vector3(0,.15,-1.54),Vector3(.30,.26,.35)]]:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=row[1]
		collider.shape=shape
		collider.position=row[0]
		add_child(collider)
	set_meta("explicit_sleep_pose",true)

func _hand_targets() -> Array:
	if dead: return [null,null]
	var t: float=home_model.clock
	if home_activity=="cook":
		return [to_global(Vector3(-.18,1.12,.42)),_cooking_hand(t)]
	return [to_global(Vector3(-.17,1.14,.35)),to_global(Vector3(.17,1.14,.35))]

func _cooking_hand(t: float) -> Vector3:
	var target: Vector3=specification.get("cook_target",specification.get("cooking_point",Vector3.ZERO)+Basis(Vector3.UP,rotation.y)*Vector3(0,1.22,.6))
	# The authored target is inside the pot. Keep the hand above its rim while
	# the spoon reaches into it; the ordinary arm IK still limits human reach.
	target.y+=.14
	return get_parent().to_global(target)+global_basis*Vector3(cos(t*1.8)*.065,sin(t*1.8)*.016,sin(t*1.8)*.055)

func _create_prop() -> void:
	held_prop=Node3D.new()
	held_prop.name="WoodenSpoon" if home_activity=="cook" else "OpenBook"
	add_child(held_prop)
	if home_activity=="cook":
		_box(held_prop,Vector3(0,-.08,0),Vector3(.026,.25,.035),Color("ad8b5b"))
		_box(held_prop,Vector3(0,-.21,0),Vector3(.070,.042,.07),Color("ad8b5b"))
	else:
		held_prop.position=Vector3(0,1.14,.38)
		held_prop.rotation.x=-.3
		_box(held_prop,Vector3.ZERO,Vector3(.38,.022,.28),Color("634c38"))
		for side in [-1.0,1.0]:
			var page := _box(held_prop,Vector3(side*.093,.018,0),Vector3(.18,.018,.25),Color("d8d0b8"))
			page.rotation.z=-side*.10
			for line in 4: _box(page,Vector3(0,.012,-.07+float(line)*.046),Vector3(.12,.003,.005),Color("817e70"))

func _process(_delta: float) -> void:
	if dead:
		if is_instance_valid(held_prop): held_prop.hide()
		set_process(false)
		return
	if home_activity=="cook" and is_instance_valid(held_prop):
		held_prop.global_position=home_model.forearms[1].to_global(Vector3(0,-HUMAN_KIT.FOREARM,0))
		held_prop.rotation=Vector3(.22,0,.20)

func _fall_over(impact := Vector3.ZERO) -> void:
	if dead and not _death_notified:
		_death_notified=true
		home_resident_died.emit()
	if home_activity=="sleep" and not has_meta("street_pose_owned") and not has_meta("street_down"):
		# Already lying on a validated mattress/pillow. A standing fall would
		# translate this pose beyond the bed and lift it above its support.
		if _reaction_tween!=null: _reaction_tween.kill()
		home_model.hand_provider=Callable()
		home_model.hand_targets=[null,null]
		home_model.set_process(false)
		set_process(false)
		preload("res://gameplay/DestroyedFade3D.gd").schedule(self)
		return
	super._fall_over(impact)

func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.position=at
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=.9
	node.material_override=material
	parent.add_child(node)
	return node
