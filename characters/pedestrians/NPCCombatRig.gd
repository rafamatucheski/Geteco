extends Node2D
## The same weapon meshes, grip solver and action profiles used by Dante.
## This child runs after AI/gait so an idle/walk branch cannot overwrite aiming.
const POSE = preload("res://characters/PlayerCombatPose.gd")
const ARSENAL = preload("res://scripts/player/ArsenalWeapon3D.gd")
var combat_pose := POSE.new()
var actor: Node2D
var model_root: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var weapon_mount_node: Node3D
var current_gun_mesh: Node3D
var active_weapon_id := "pistol"
var aim_override := false
var clock := 0.0

static func attach(body: Node2D, id: String) -> Node2D:
	var existing := body.get_node_or_null("NPCCombatRig")
	if existing: return existing
	var rig = load("res://characters/pedestrians/NPCCombatRig.gd").new()
	rig.name = "NPCCombatRig"
	rig.actor = body
	rig.active_weapon_id = id
	body.add_child(rig)
	return rig

func _ready() -> void:
	process_physics_priority = 10
	model_root = actor.model_root
	left_upper_arm = actor.left_upper_arm
	left_lower_arm = actor.left_lower_arm
	right_upper_arm = actor.right_upper_arm
	right_lower_arm = actor.right_lower_arm
	# Body diversity changes sleeve thickness, not the kinematic bone basis.
	# Nonuniform bone scale skews the shared solver's wrist/support transforms.
	for upper in [left_upper_arm, right_upper_arm]:
		var thickness: Vector3 = upper.scale
		upper.scale = Vector3.ONE
		for child in upper.get_children():
			if child is MeshInstance3D:
				child.scale *= thickness
				child.position *= thickness
		var lower: Node3D = left_lower_arm if upper == left_upper_arm else right_lower_arm
		for child in lower.get_children():
			if child is MeshInstance3D:
				child.scale *= thickness
				child.position *= thickness
	for arm in [left_lower_arm, right_lower_arm]:
		if not arm.has_node("Palm"):
			var palm := MeshInstance3D.new()
			palm.name = "Palm"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(.075, .07, .085)
			palm.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color("bd8a6b")
			if actor.get("tier") != null and int(actor.get("tier")) >= 2:
				material.albedo_color = Color("30353c")
			palm.material_override = material
			palm.position.y = -.20
			arm.add_child(palm)
		if actor.get("tier") != null and int(actor.get("tier")) >= 2:
			var palm: MeshInstance3D = arm.get_node("Palm")
			palm.material_override = palm.material_override.duplicate()
			palm.material_override.albedo_color = Color("30353c")
	weapon_mount_node = Node3D.new()
	weapon_mount_node.name = "WeaponMount"
	right_lower_arm.add_child(weapon_mount_node)
	equip(active_weapon_id)

func equip(id: String) -> void:
	active_weapon_id = id if POSE.PROFILES.has(id) else "pistol"
	if is_instance_valid(current_gun_mesh):
		current_gun_mesh.free()
	current_gun_mesh = Node3D.new()
	weapon_mount_node.add_child(current_gun_mesh)
	current_gun_mesh.position = -POSE.GRIPS.get(active_weapon_id, Vector3.ZERO)
	var muzzle := ARSENAL.build(current_gun_mesh, active_weapon_id)
	var flash: Node3D = actor.get("muzzle_flash_3d")
	if is_instance_valid(flash):
		flash.reparent(weapon_mount_node)
		flash.position = current_gun_mesh.position + muzzle
	combat_pose.update(self, 0.0, false, false, 0.0)

func attack() -> void:
	combat_pose.on_attack(active_weapon_id)
	var data := WeaponCatalog.get_weapon(active_weapon_id)
	if data.get("is_melee", false) == true and actor and actor.has_method("_play_audio"):
		var sound_type: String = String(data.get("sound_type", "fists"))
		var vol: float = float(data.get("audio_volume_db", -4.0))
		actor._play_audio(ProceduralAudio.get_melee_swing_stream(sound_type), vol)

func is_reloading() -> bool:
	return actor != null and actor.has_method("is_reloading") and actor.is_reloading()

func get_reload_progress() -> float:
	return float(actor.get_reload_progress()) if (actor != null and actor.has_method("get_reload_progress")) else 0.0

func _physics_process(delta: float) -> void:
	if actor == null or actor.get("is_dead") == true or actor.get("is_flying") == true or actor.get("is_incapacitated") == true: return
	if actor.get("_viewport_render_active") == false: return
	clock += delta
	var moving: bool = actor.velocity.length_squared() > 1.0
	var aiming := aim_override
	if actor.has_method("is_police_aiming"):
		aiming = aiming or actor.is_police_aiming()
	elif actor.get("combat_target") != null:
		aiming = aiming or is_instance_valid(actor.get("combat_target"))
	elif actor.get("target") != null and is_instance_valid(actor.get("target")):
		var wm := get_node_or_null("/root/WantedManager")
		var stars: int = int(actor.get("security_alert")) if actor.get("local_security") == true else (wm.current_stars if wm else 0)
		aiming = aiming or stars >= 3 or float(actor.get("response_aggression")) > 0.0
	combat_pose.update(self, delta, aiming, moving and not aiming, sin(clock * 6.0) * .4 if moving else 0.0)
