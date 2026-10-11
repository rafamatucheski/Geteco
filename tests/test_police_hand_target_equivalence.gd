extends SceneTree
## Compara o caminho anterior e o otimizado com estado idêntico, incluindo arma e esqueleto final.
## Não afrouxa contato nem altera a malha: a otimização deve preservar o resultado da pose.
const MODEL := preload("res://gameplay/PoliceModel.gd")
const CATALOG := preload("res://gameplay/PoliceBodyCatalog.gd")
const RIG := preload("res://assets/civilians/MeshyBodyRig.gd")
const SOURCES := ["patrol_m", "patrol_heavy", "patrol_f", "suit_m", "suit_f", "tactical_gray", "tactical_black"]
const WEAPONS := ["pistol", "smg", "m4a1"]
const EPSILON := 0.000001
var failures: Array[String] = []
var samples := 0
var maximum_error := 0.0

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): push_error("Equivalência excedeu o prazo"); quit(3))
	_run.call_deferred()

func _error(expected: Variant, actual: Variant) -> float:
	if typeof(expected) != typeof(actual): return INF
	if expected == null: return 0.0
	if expected is Vector3: return (expected as Vector3).distance_to(actual)
	if expected is Vector2: return (expected as Vector2).distance_to(actual)
	if expected is Basis:
		var a: Basis = expected
		var b: Basis = actual
		return maxf(a.x.distance_to(b.x), maxf(a.y.distance_to(b.y), a.z.distance_to(b.z)))
	if expected is Transform3D:
		var a: Transform3D = expected
		var b: Transform3D = actual
		return maxf(a.origin.distance_to(b.origin), _error(a.basis, b.basis))
	if expected is Array:
		if expected.size() != actual.size(): return INF
		var largest := 0.0
		for index in expected.size(): largest = maxf(largest, _error(expected[index], actual[index]))
		return largest
	if expected is float: return absf(float(expected) - float(actual))
	return 0.0 if expected == actual else INF

func _scenarios() -> Array[Dictionary]:
	var scenarios: Array[Dictionary] = []
	for weight in [0.0, .25, .7, 1.0]:
		scenarios.append({"name": "aim_%s" % weight, "aim_weight": weight, "aiming": weight > .5, "reload": false, "progress": 0.0, "recoil": 0.0, "run": false})
	for recoil in [.03, .10, .24]:
		scenarios.append({"name": "recoil_%s" % recoil, "aim_weight": 1.0, "aiming": true, "reload": false, "progress": 0.0, "recoil": recoil, "run": false})
	for progress in [0.0, .08, .14, .23, .32, .41, .5, .6, .67, .79, .88, .95, 1.0]:
		scenarios.append({"name": "reload_%s" % progress, "aim_weight": .85, "aiming": true, "reload": true, "progress": progress, "recoil": .02, "run": false})
	scenarios.append({"name": "run", "aim_weight": .10, "aiming": false, "reload": false, "progress": 0.0, "recoil": 0.0, "run": true})
	return scenarios

func _snapshot(police: Node3D, scenario: Dictionary, optimized: bool) -> Dictionary:
	MODEL.optimize_weapon_targets = optimized
	RIG.optimize_pose_chain = optimized
	police._body_aim_weight = float(scenario.aim_weight)
	police.recoil = float(scenario.recoil)
	police.flash_time = .04
	police.update_pose(1.0 / 60.0, bool(scenario.aiming), bool(scenario.reload), float(scenario.progress), .9 if scenario.run else .0)
	var body: Node3D = police.body
	# Resolve a cadeia real até os alvos produzidos; não escreve nos ossos para fazê-los coincidir.
	var spine_model: Transform3D = body.pelvis.transform * body.spine.transform
	for side in 2:
		if not body.hand_targets[side] is Vector3: continue
		var sign_side := -1.0 if side == 0 else 1.0
		var reached: Array = body._reach_arm(side, spine_model, body.to_local(body.hand_targets[side]), Vector3(sign_side * .9, -.8, -.3))
		body.upper_arms[side].transform = Transform3D(reached[0], body._shoulders[side])
		body.forearms[side].transform = Transform3D(reached[1], Vector3(0, -body._arm_measure(side).x, 0))
	body._meshy.sync(1.0 / 60.0)
	var bones: Array[Transform3D] = []
	for bone in body.skeleton.get_bone_count():
		bones.append(body.skeleton.global_transform * body.skeleton.get_bone_global_pose(bone))
	return {"targets": body.hand_targets.duplicate(), "weapon_local": police.weapon.transform,
		"weapon_world": police.weapon.global_transform, "frames": body.hand_frames.duplicate(),
		"grip_weights": body.hand_grip_weights, "contacts": police.weapon_hand_contacts(),
		"muzzle": police.muzzle_position(), "recoil": police.recoil, "flash_visible": police.muzzle_flash_3d.visible,
		"bones": bones}

func _prepare(a: Node3D, b: Node3D, scenario: Dictionary, world_index: int) -> void:
	# As duas instâncias recebem o mesmo estado. Nenhum relógio autônomo avança durante a comparação.
	var tracked_a: Array = a.body._meshy._tracked
	var tracked_b: Array = b.body._meshy._tracked
	for index in tracked_a.size(): tracked_b[index].transform = tracked_a[index].transform
	var rotation := Vector3(.07 * world_index, .61 * world_index, -.035 * world_index)
	var uniform_scale := 1.0 + .12 * world_index
	var world_pose := Transform3D(Basis.from_euler(rotation).scaled(Vector3.ONE * uniform_scale), Vector3(7.0 * world_index, .35 * world_index, -4.0 * world_index))
	var pelvis_y: float = a.body.pelvis_y
	var pelvis_pose := Transform3D(Basis.from_euler(Vector3(.06, -.12, .045)), Vector3(.018, pelvis_y - (.035 if scenario.run else .0), -.01))
	var chest_pose := Transform3D(Basis.from_euler(Vector3(.22 if scenario.run else .035, .11, -.025)), a.body.SPINE_OFFSET)
	for police in [a, b]:
		police.transform = world_pose
		police.body.pelvis.transform = pelvis_pose
		police.body.spine.transform = chest_pose
		police.body.hand_targets = [null, null]
		police.body.hand_frames = [null, null]
		police.body.hand_grip_weights = Vector2.ONE

func _run() -> void:
	var previous_enabled := CATALOG.enabled
	var previous_override: Dictionary = CATALOG.override.duplicate(true)
	var previous_flag := MODEL.optimize_weapon_targets
	var previous_chain := RIG.optimize_pose_chain
	CATALOG.enabled = true
	var scenarios := _scenarios()
	for source in SOURCES:
		CATALOG.override[1] = "res://assets/civilians/meshy/police/%s.glb" % source
		for weapon in WEAPONS:
			var holder := Node3D.new()
			root.add_child(holder)
			var models: Array[Node3D] = []
			for index in 2:
				var police := MODEL.new()
				police.tier = 1
				police.appearance_index = 2
				holder.add_child(police)
				police.equip(weapon)
				models.append(police)
			for frame in 3: await process_frame
			var installed := true
			for police in models:
				if police.body == null or police.body.skeleton == null:
					failures.append("%s/%s: corpo importado ausente" % [source, weapon])
					installed = false
					continue
				police.body.set_process(false)
				police.body._meshy.driver.set_process(false)
			if installed:
				for scenario in scenarios:
					for world_index in 3:
						_prepare(models[0], models[1], scenario, world_index)
						var reference := _snapshot(models[0], scenario, false)
						var optimized := _snapshot(models[1], scenario, true)
						samples += 1
						for field in reference:
							var error := _error(reference[field], optimized[field])
							maximum_error = maxf(maximum_error, error)
							if not is_finite(error) or error > EPSILON:
								failures.append("%s/%s/%s/world%d/%s: diferença %.9f" % [source, weapon, scenario.name, world_index, field, error])
			print("POLICE_TARGET_EQ ", source, "/", weapon, " samples=", samples, " max_error=", maximum_error)
			holder.queue_free()
			await process_frame
	CATALOG.override = previous_override
	CATALOG.enabled = previous_enabled
	MODEL.optimize_weapon_targets = previous_flag
	RIG.optimize_pose_chain = previous_chain
	print("POLICE_TARGET_EQ samples=", samples, " max_error=", maximum_error, " failures=", failures)
	quit(0 if failures.is_empty() and samples == SOURCES.size() * WEAPONS.size() * scenarios.size() * 3 else 1)
