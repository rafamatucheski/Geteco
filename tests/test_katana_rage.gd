extends SceneTree
## Focused contracts: real imported Actor rig, physical player compensation,
## protected NPCs, bounded wounds and interruption of the global time owner.
const RAGE := preload("res://gameplay/KatanaRage.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const MODEL := preload("res://gameplay/KatanaModel.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
class State extends RefCounted:
	var owned := true
	var safe := false
	func owns_weapon(id: String) -> bool: return owned and id == "katana"
	func weapons_allowed() -> bool: return not safe
class FakeGame extends Node:
	signal changed
	var state := State.new()
	var player: Node3D
	var available := true
	var weapon := "katana"
	func attack_allowed() -> bool: return available and not state.safe and not get_tree().paused
	func _free_play_ok() -> bool: return available
	func equipped() -> String: return weapon
class Stage extends Node3D:
	var gameplay = null
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(30, 0.2, 30)
	collider.shape = box; collider.position.y = -0.1
	floor.add_child(collider); stage.add_child(floor)
	var actor := ACTOR.new(); actor.is_player = true; actor.controlled_automatically = true
	stage.add_child(actor)
	var fake := FakeGame.new(); fake.player = actor; stage.add_child(fake)
	var rage := RAGE.new(); rage.gameplay = fake; fake.add_child(rage)
	await frames(3)
	check(actor.animation.has_animation("ual/Sword_Attack") and actor.animation.has_animation("ual/Sword_Idle"), "downloaded UAL sword clips loaded on real Dante")
	check(not rage.activate(), "empty RAGE cannot activate")
	fake.state.owned = false; rage.add_damage(100)
	check(rage.charge == 0, "RAGE locked until acquiring family katana")
	fake.state.owned = true
	for invalid in [NAN, INF, -1.0, 0.0]: rage.add_damage(invalid)
	check(rage.charge == 0, "invalid damage cannot fill RAGE")
	# Actual damage path, including ballistic armor, god mode and environment.
	var actual := GAMEPLAY.new(); actual.player = actor; actual.state = fake.state; actual.rage = rage
	actual.god_mode = true; actual.damage_player(30)
	check(rage.charge == 0, "god mode yields no RAGE")
	actual.god_mode = false; actual.armor = 40; actual.damage_player(20)
	check(is_equal_approx(rage.charge, 50.0), "combat damage to health and armor both charge RAGE")
	actual.damage_environment(10)
	check(is_equal_approx(rage.charge, 50.0), "cold and other environment damage do not farm combat RAGE")
	fake.state.safe = true; actual.damage_player(100)
	check(is_equal_approx(rage.charge, 50.0), "garage ignores damage and charge")
	fake.state.safe = false
	actual.rage = null; actual.free()
	rage.add_damage(200)
	check(rage.charge == 100, "charge clamps at 100")
	fake.weapon = "pistol"; check(not rage.activate(), "RAGE requires equipped katana")
	fake.weapon = "katana"
	check(rage.activate() and is_equal_approx(Engine.time_scale, 0.1), "full meter slows the world by ninety percent")
	check(actor.get_meta("katana_rage_speed", 0.0) == 10.0 and rage.charge == 0, "player compensation and meter consumption are atomic")
	rage.add_damage(100); check(rage.charge == 0, "cannot recharge during active effect")
	var slow_actor := ACTOR.new(); slow_actor.controlled_automatically=true; slow_actor.automatic_direction=Vector3.RIGHT
	stage.add_child(slow_actor); slow_actor.position=Vector3(0,0,3)
	actor.automatic_direction = Vector3.RIGHT
	var before := actor.position
	var slow_before := slow_actor.position
	await frames(12)
	check(actor.position.x - before.x > 0.2, "real CharacterBody remains mobile during RAGE")
	var relative_speed := (slow_actor.position.x-slow_before.x)/(actor.position.x-before.x)
	check(absf(relative_speed-.1)<.025,"real NPC motion advances at one tenth of Dante's motion")
	slow_actor.queue_free()
	actor.automatic_direction = Vector3.ZERO
	rage.advance_real_seconds(15.0)
	check(not rage.active and is_equal_approx(Engine.time_scale, 1.0) and not actor.has_meta("katana_rage_speed"), "15 real seconds restores normal time and player units")
	for interruption in ["pause", "garage", "vehicle_or_death", "weapon"]:
		rage.restore(100); check(rage.activate(), "activation before " + interruption)
		match interruption:
			"pause": paused = true
			"garage": fake.state.safe = true
			"vehicle_or_death": actor.input_locked = true
			"weapon": fake.weapon = "pistol"
		await process_frame; await process_frame
		check(not rage.active and is_equal_approx(Engine.time_scale, 1.0), "global time restored on " + interruption)
		paused = false; fake.state.safe = false; actor.input_locked = false; fake.weapon = "katana"
	rage.restore(100); rage.activate(); rage.restore(34)
	check(not rage.active and rage.charge == 34 and is_equal_approx(Engine.time_scale, 1.0), "load restores charge but never active slow motion")
	rage.restore(100); rage.activate(); rage.free()
	check(is_equal_approx(Engine.time_scale, 1.0), "scene destruction restores global time")
	var blade := MODEL.create(); actor.add_child(blade)
	actor.combat_weapon_pose = {"native_sword":true}; actor.combat_weapon_id = "katana"
	actor.combat_weapon_mount = blade; actor.combat_weapon_grip = MODEL.GRIP
	actor.combat_clip = "ual/Sword_Attack"; actor.combat_clip_time = 0.45
	await frames(10)
	check(blade.global_position.distance_to(actor._clip_palm("Right")) < 0.1, "native sword stays attached to the animated palm")
	check(blade.find_child("ForgedSteel", true, false) != null and blade.get_child_count() < 25, "curved steel model has a bounded authored mesh set")
	var saber := MODEL.create(true, Color("e918b5")); stage.add_child(saber)
	check(saber.find_child("EnergyBlade", true, false) != null and saber.find_children("*", "Light3D", true, false).is_empty(), "any-color saber uses stable emissive geometry without new dynamic lights")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		var camera := Camera3D.new(); stage.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=3.5
		camera.position=actor.position+Vector3(3,2.1,3); camera.look_at(actor.position+Vector3.UP*.85); camera.current=true
		var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-45,-35,0); sun.light_energy=1.4; stage.add_child(sun)
		saber.hide()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://evidence/takeshi/katana_pose"))
		for time in [0.05,0.35,0.55,0.85,1.20]:
			actor.combat_clip_time=time; await frames(8); await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://evidence/takeshi/katana_pose/sword_%.2f.png" % time)
		if "--orientations" in OS.get_cmdline_user_args():
			var axes := {"plus_x":Basis(Vector3.UP,-PI*.5),"minus_x":Basis(Vector3.UP,PI*.5),"plus_y":Basis(Vector3.RIGHT,PI*.5),"minus_y":Basis(Vector3.RIGHT,-PI*.5),"minus_z":Basis.IDENTITY,"plus_z":Basis(Vector3.UP,PI)}
			for axis in axes:
				actor.combat_weapon_pose.native_sword_basis=axes[axis]
				for time in [.05,.35,.55,.85]:
					actor.combat_clip_time=time; await frames(3); await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://evidence/takeshi/katana_pose/%s_%.2f.png" % [axis,time])
	var wounds := preload("res://gameplay/KatanaWounds.gd").new(); stage.add_child(wounds)
	var victim := ACTOR.new(); stage.add_child(victim); victim.position = Vector3(4,0,0)
	await frames(2)
	check(not wounds.sever_defeated(victim, Vector3.RIGHT, 0), "living actors retain complete collision and locomotion")
	victim.set_meta("invulnerable", true); victim.receive_damage(200, actor)
	check(not victim.dead and not wounds.sever_defeated(victim, Vector3.RIGHT, 0), "protected residents cannot die or lose a limb")
	victim.remove_meta("invulnerable"); victim.receive_damage(200, actor)
	check(victim.dead and wounds.sever_defeated(victim, Vector3.RIGHT, 0), "lethal katana presentation detaches a real articulated arm")
	check(not wounds.sever_defeated(victim, Vector3.RIGHT, 0) and wounds.part_count() == 1, "same victim cannot duplicate body parts")
	check(not (victim.find_child("right_upper_arm", true, false) as MeshInstance3D).visible, "severed arm is removed from corpse presentation")
	wounds.clear(); check(wounds.part_count() == 0, "region cleanup releases detached parts and bleeding work")
	stage.queue_free(); await process_frame
	print("KATANA_RAGE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
