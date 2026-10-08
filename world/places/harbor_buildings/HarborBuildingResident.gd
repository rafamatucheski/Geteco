extends "res://scripts/Actor.gd"
## Civilian actors keep the shared collision/damage contracts. Their task is
## performed with native hand IK and real props, without NPC-sized billboards.
const MODEL := preload("res://assets/CivilianModel.gd")
const MATERIALS := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")
const SOCIAL_ROUTINE := preload("res://gameplay/civilian_social/BuildingSocialRoutine.gd")
var specification: Dictionary = {}
var resident_model: Node3D
var prop: Node3D
var social_phone: Node3D
var social_routine: Node
var work_activity := "read"
var work_clock := 0.0

func _ready() -> void:
	name = str(specification.get("id", "BuildingResident"))
	identity = int(specification.get("identity", 7000))
	controlled_automatically = true
	automatic_direction = Vector3.ZERO
	collision_layer = 2
	collision_mask = 7
	floor_snap_length = .3
	set_meta("gameplay_role", "civilian")
	set_meta("reaction_exempt", true)
	add_to_group("police_witness")
	add_to_group("v2_damageable")
	add_to_group("building_resident")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .30
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = .86
	add_child(shape)
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	resident_model = MODEL.new()
	resident_model.appearance_locked = true
	resident_model.appearance_variant = identity
	resident_model.lod_enabled = false
	var appearance: Dictionary = specification.get("appearance", {})
	resident_model.coat_color = Color(str(appearance.get("coat", "778775")))
	resident_model.pants_color = Color("414c4e")
	resident_model.wardrobe_overrides = {"female":bool(appearance.get("female", false)), "height":1.0, "top":int(appearance.get("top", 1)),
		"bottom":0, "shoe":0, "hat":0, "bag":0, "backpack":false}
	visual.add_child(resident_model)
	work_activity = str(specification.get("activity", "read"))
	resident_model.hand_provider = _hands
	_build_prop()
	_build_social_phone()
	last_position = global_position
	resident_model.teleported()
	process_priority = 1

func _hands() -> Array:
	if dead or get_meta("workplace_threatened", false): return [null, null]
	var sway := sin(work_clock * 1.7)
	if is_instance_valid(social_routine):
		match social_routine.social.state:
			"calling_police": return [null, resident_model.to_global(Vector3(.19, 1.6, .12))]
			"happy": return [null, resident_model.to_global(Vector3(.36 + sway * .035, 1.43, .2))]
			"talking": return [null, null] # Native conversational arm motion.
			"annoyed": return [resident_model.to_global(Vector3(-.23, 1.02, .12)), resident_model.to_global(Vector3(.23, 1.02, .12))]
			"scared": return [resident_model.to_global(Vector3(-.22, 1.43, .21)), resident_model.to_global(Vector3(.22, 1.43, .21))]
			"recovering": return [null, resident_model.to_global(Vector3(.08, 1.22, .26))]
		if social_routine.social.routine_phase == "pause": return [null, null]
	match work_activity:
		"phone": return [null, resident_model.to_global(Vector3(.18, 1.51, .14))]
		"repair": return [resident_model.to_global(Vector3(-.15, 1.10, .52)), resident_model.to_global(Vector3(.15, 1.12 + sin(work_clock * 3.0) * .035, .57))]
		"cook": return [resident_model.to_global(Vector3(-.18, 1.17, .50)), resident_model.to_global(Vector3(-.16 + cos(work_clock * 1.6) * .04, 1.26, .57 + sway * .035))]
		"write": return [resident_model.to_global(Vector3(-.16, 1.10, .34)), resident_model.to_global(Vector3(.12 + sway * .03, 1.12, .38))]
		_: return [resident_model.to_global(Vector3(-.16, 1.17, .35)), resident_model.to_global(Vector3(.16, 1.17, .35))]

func _build_prop() -> void:
	prop = Node3D.new()
	prop.name = "ActivityProp_" + work_activity
	resident_model.add_child(prop)
	if work_activity == "phone":
		prop.position = Vector3(.18, 1.51, .14)
		_box(prop, Vector3.ZERO, Vector3(.073, .15, .018), "344544", "metal")
	elif work_activity in ["repair", "cook"]:
		_box(prop, Vector3(0, -.08, 0), Vector3(.026, .24, .035), "977441", "wood")
		_box(prop, Vector3(0, -.22, 0), Vector3(.075, .06, .07), "aaa998" if work_activity == "repair" else "977441", "metal" if work_activity == "repair" else "wood")
	else:
		prop.position = Vector3(0, 1.17, .37)
		prop.rotation.x = -.20
		_box(prop, Vector3.ZERO, Vector3(.36, .027, .28), "655841", "wood")
		_box(prop, Vector3(0, .021, 0), Vector3(.32, .018, .25), "d6d0b4", "paper")
		for line in 4: _box(prop, Vector3(0, .034, -.07 + line * .047), Vector3(.24, .004, .006), "817f70", "paper")

func _build_social_phone() -> void:
	social_phone = Node3D.new()
	social_phone.name = "EmergencyPhone"
	social_phone.position = Vector3(.19, 1.6, .12)
	resident_model.add_child(social_phone)
	_box(social_phone, Vector3.ZERO, Vector3(.073, .15, .018), "344544", "metal")
	social_phone.hide()

func configure_social(owner_gameplay: Node, reaction: Node, illicit: bool) -> void:
	if is_instance_valid(social_routine): return
	social_routine = SOCIAL_ROUTINE.new()
	social_routine.name = "BuildingSocialRoutine"
	social_routine.configure(self, owner_gameplay, reaction, specification, illicit)
	add_child(social_routine)
	add_to_group("social_npc")

func social_options() -> Array[Dictionary]:
	return social_routine.social.options() if is_instance_valid(social_routine) else []

func social_snapshot() -> Dictionary:
	return social_routine.snapshot() if is_instance_valid(social_routine) else {"can_interact":false}

func begin_social(player: Node3D) -> bool:
	return is_instance_valid(social_routine) and social_routine.begin_social(player)

func end_social() -> void:
	if is_instance_valid(social_routine): social_routine.end_social()

func social_interact(action: String, player: Node3D = null) -> Dictionary:
	return social_routine.interact(action, player) if is_instance_valid(social_routine) else {"ok":false}

func present_social_threat(calling: bool) -> void:
	if is_instance_valid(social_phone): social_phone.visible = calling and not dead and is_visible_in_tree()
	if dead or calling or get_meta("workplace_threatened", false): prop.hide()

func _process(delta: float) -> void:
	if dead:
		prop.hide()
		social_phone.hide()
		resident_model.hand_provider = Callable()
		set_process(false)
		return
	if get_meta("workplace_threatened", false):
		prop.hide()
		return
	work_clock += delta
	var working := true
	if is_instance_valid(social_routine):
		var social: RefCounted = social_routine.social
		working = social.state == "calm" and social.routine_phase == "work"
		resident_model.activity = "talk" if social.state in ["talking", "happy"] else ""
		var target_yaw := 0.0
		if is_instance_valid(social_routine.partner):
			var offset: Vector3 = to_local(social_routine.partner.global_position)
			target_yaw = atan2(offset.x, offset.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, 1.0 - exp(-4.0 * delta))
		social_phone.visible = social.state == "calling_police"
	prop.visible = working
	if not working: return
	if work_activity in ["repair", "cook"] and resident_model.forearms.size() > 1:
		prop.global_position = resident_model.forearms[1].to_global(Vector3(0, -preload("res://assets/civilians/CivilianMeshKit.gd").FOREARM, 0))
		prop.rotation = Vector3(.14, 0, .12)
	# Small head movements show attention without moving the collision capsule.
	resident_model.head_node.rotation.x = .14 + sin(work_clock * .65) * .025

func _box(parent: Node3D, at: Vector3, size: Vector3, color: String, kind: String) -> void:
	var visual_prop := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual_prop.mesh = mesh
	visual_prop.position = at
	visual_prop.material_override = MATERIALS.material(kind, Color(color))
	parent.add_child(visual_prop)
