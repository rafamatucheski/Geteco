extends SceneTree
## Pure presentation contracts: every productive weapon has a model, a finite
## pose, grip-consistent placement and imported audio where the catalog asks.
const IDS := ["fists", "knuckles", "knife", "bat", "axe", "pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "rpg", "flamethrower", "grenade", "hunting_rifle"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("CASE PASS " if ok else "CASE FAIL ") + label)
	if not ok: failures.append(label)

func finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

func _run() -> void:
	var pose := preload("res://gameplay/WeaponRigPose.gd").new()
	var data = preload("res://gameplay/WeaponPoseData.gd")
	var catalog = preload("res://gameplay/WeaponCatalog.gd")
	var audio = preload("res://gameplay/CombatAudio.gd")
	var actor = preload("res://scripts/Actor.gd").new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	await process_frame
	for id in IDS:
		var model := Node3D.new()
		root.add_child(model)
		var muzzle := preload("res://gameplay/ArsenalWeapon3D.gd").build(model, id)
		check(id == "fists" or model.find_children("*", "MeshInstance3D", true, false).size() > 0, "%s possui modelo produtivo" % id)
		check(finite_vector(muzzle), "%s possui bico/origem finito" % id)
		pose.reset()
		var frame: Dictionary
		# A pose e o esqueleto avançam juntos, como no Actor produtivo. Avançar
		# apenas os alvos e saltar 20 quadros ignorava as transições dos braços.
		for tick in 20:
			frame = pose.update(id, 1.0 / 60.0, true, false, 0.0, false, false, 0.0)
			actor._pose_locomotion(Vector3.ZERO, 0.0, Vector3.ZERO, 0.0)
			actor.set_combat_weapon_pose(id, frame)
			actor._apply_combat_weapon_pose()
		check(finite_vector(frame.right) and finite_vector(frame.left) and finite_vector(frame.gun_origin), "%s produz postura finita" % id)
		var grip: Vector3 = data.GRIPS.get(id, Vector3.ZERO)
		check((frame.gun_origin + (frame.basis as Basis) * grip * float(frame.get("weapon_scale", 1.0))).distance_to(frame.right) < 0.0005, "%s alinha cabo e palma direita" % id)
		if bool(frame.left_grip) and data.SUPPORT_GRIPS.has(id):
			check((frame.gun_origin + (frame.basis as Basis) * (frame.get("support_point", data.SUPPORT_GRIPS[id]) as Vector3) * float(frame.get("weapon_scale", 1.0))).distance_to(frame.left) < 0.001, "%s alinha apoio e palma esquerda" % id)
		model.global_transform = actor.combat_weapon_transform(grip)
		check(actor.combat_palm_position("Right").distance_to(model.to_global(grip)) < 0.002, "%s mantém o modelo na palma real" % id)
		if bool(frame.left_grip) and data.SUPPORT_GRIPS.has(id):
			var support_distance := actor.combat_palm_position("Left").distance_to(model.to_global(frame.get("support_point", data.SUPPORT_GRIPS[id])))
			check(support_distance < 0.080, "%s mantém o apoio no volume da mão real (%.3f m)" % [id, support_distance])
		pose.attack(id)
		var attacked: Dictionary
		for attack_tick in 10:
			attacked = pose.update(id, 1.0 / 60.0, true, false, 0.0, false, false, 0.0)
			actor._pose_locomotion(Vector3.ZERO, 0.0, Vector3.ZERO, 0.0)
			actor.set_combat_weapon_pose(id, attacked)
			actor._apply_combat_weapon_pose()
		check(finite_vector(attacked.right) and finite_vector(attacked.gun_origin), "%s anima ataque sem alterar lógica" % id)
		model.global_transform = actor.combat_weapon_transform(grip)
		if bool(attacked.left_grip) and data.SUPPORT_GRIPS.has(id):
			var attack_support_distance := actor.combat_palm_position("Left").distance_to(model.to_global(attacked.get("support_point", data.SUPPORT_GRIPS[id])))
			check(attack_support_distance < 0.080, "%s mantém o apoio durante a ação (%.3f m)" % [id, attack_support_distance])
		model.queue_free()
	actor.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for id in ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg"]:
		var stream := audio.take(String(catalog.WEAPONS[id].sound_type), rng)
		check(stream != null and String(stream.resource_path).begins_with("res://") and stream.get_length() > 0.03, "%s usa AudioStream importado com conteúdo (editor/PCK)" % id)
	for id in audio.RELOAD_WEAPONS:
		check(audio.reload_take(id, rng) != null and audio.reload_seconds(id) >= audio.MIN_RELOAD, "%s possui banco/duração de recarga" % id)
	print("WEAPON_PRESENTATION_CONTRACT checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
