extends SceneTree
## Diagnostic only: production Actor/GLB, isolated lit stage, no saves.
const ACTOR = preload("res://scripts/Actor.gd")
const FALL = preload("res://gameplay/CharacterFallPresentation3D.gd")
const POSE = preload("res://gameplay/WeaponRigPose.gd")
const DATA = preload("res://gameplay/WeaponPoseData.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const OUT = "res://evidence/dante-animation-review-0924/"
var actor
var view: SubViewport
var report := {}
func _initialize() -> void: run.call_deferred()
func root_lock() -> void:
	var p: Vector3 = actor.skeleton.get_bone_pose_position(actor.hips)
	p.x = actor.hip_rest.x
	p.z = actor.hip_rest.z
	actor.skeleton.set_bone_pose_position(actor.hips, p)
func snapshot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image().save_png(OUT.path_join(name + ".png"))
	if result != OK:
		push_error("Capture write failed")
		quit(2)
func difference(a: Array, b: Array) -> Dictionary:
	var angle := 0.0
	var bone := ""
	for i in a.size():
		var d := rad_to_deg((a[i][1] as Quaternion).angle_to(b[i][1]))
		if d > angle:
			angle = d
			bone = actor.skeleton.get_bone_name(i)
	return {"max_degrees":angle, "bone":bone}
func run() -> void:
	view = SubViewport.new()
	view.size = Vector2i(320, 360)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("273039")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("cad4df")
	env.environment.ambient_light_energy = 0.75
	view.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42,-28,0)
	light.light_energy = 1.35
	view.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	camera.position = Vector3(2.5,1.9,-3.5)
	view.add_child(camera)
	camera.look_at(Vector3(0,0.95,0))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20,20)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("49545e")
	floor_mesh.material_override = material
	view.add_child(floor_mesh)
	actor = ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	view.add_child(actor)
	actor.set_physics_process(false)
	report["actor_hash"] = actor.get_script().source_code.sha256_text()
	report["clips"] = []
	for clip in actor.animation.get_animation_list():
		var anim: Animation = actor.animation.get_animation(clip)
		report.clips.append({"name":clip,"duration":anim.length})
		for i in 6:
			actor._pose_clip(clip, anim.length * (float(i) / 6.0 + 0.04))
			root_lock()
			await snapshot("clip_%s_%02d" % [clip,i])
	report["seams"] = {}
	for clip in ["Walking","Running"]:
		var start := 0.067 if clip == "Walking" else 0.0
		actor._pose_cycle(clip,0.99999,start)
		var before: Array = actor._capture_pose()
		actor._pose_cycle(clip,0.00001,start)
		report.seams[clip] = difference(before,actor._capture_pose())
	for scenario in ["idle","walk","run","slow_sprint","back_fast","side_fast","side_slow","turn"]:
		actor.phase = 0.0
		actor._locomotion_weight = 0.0
		actor._run_weight = 0.0
		actor.visual.rotation = Vector3.ZERO
		var speed := 0.0 if scenario in ["idle","turn"] else (6.5 if scenario == "run" else (1.0 if scenario in ["side_slow","slow_sprint"] else 3.5))
		var target := 6.5 if scenario in ["run","slow_sprint"] else 3.5
		var direction := Vector3.FORWARD
		if scenario.begins_with("side"): direction = Vector3.RIGHT
		if scenario == "back_fast": direction = Vector3.BACK
		actor.combat_facing = 0.0 if scenario.begins_with("side") or scenario == "back_fast" or scenario == "turn" else NAN
		actor.combat_stance = "gun" if not is_nan(actor.combat_facing) else ""
		for tick in 30: actor._pose_locomotion(direction,target,direction*speed/60.0,speed,1.0/60.0)
		var initial: Array = actor._capture_pose()
		var cycle := (3.4 if target > 4.0 else 1.8) / maxf(speed,0.1)
		var dt := cycle / 48.0 if speed > 0 else 1.0/30.0
		for tick in 48:
			if scenario == "turn": actor.visual.rotation.y = float(tick)/48.0 * TAU
			actor._pose_locomotion(direction,target,direction*speed*dt,speed,dt)
			root_lock()
			if tick % 6 == 0: await snapshot("runtime_%s_%02d" % [scenario,tick/6])
		report[scenario] = {"clip":actor.animation.current_animation,"speed":speed,"run_weight":actor._run_weight,"local_pose_change":difference(initial,actor._capture_pose())}
	report["combat"] = {}
	for id in DATA.PROFILES:
		var variants := 4 if id == "knuckles" else (2 if id == "fists" else (3 if id == "knife" else 1))
		for variant in variants:
			await combat_sequence(id,variant,false,camera)
		if id in POSE.FIREARMS: await combat_sequence(id,0,true,camera)
	for id in ["fists","knuckles"]:
		camera.position = Vector3(0,1.45,-4)
		camera.look_at(Vector3(0,1.05,0))
		await combat_sequence(id,0,false,camera,"front")
		camera.position = Vector3(4,1.45,0)
		camera.look_at(Vector3(0,1.05,0))
		await combat_sequence(id,0,false,camera,"side")
	camera.position = Vector3(2.5,1.9,-3.5)
	camera.look_at(Vector3(0,0.95,0))
	actor.clear_combat_weapon_pose()
	var joints: Array[Dictionary] = []
	FALL._gather_joints(actor,actor.visual,0,joints)
	report["death_articulated_joints"] = joints.size()
	actor.visual.rotation = Vector3.ZERO
	actor._apply_pose(actor._idle_pose)
	var initial_death: Array = actor._capture_pose()
	actor.on_player_death()
	for tick in 7:
		await create_timer(0.18).timeout
		await snapshot("runtime_death_%02d" % tick)
	report["death_pose_change"] = difference(initial_death,actor._capture_pose())
	FileAccess.open(OUT.path_join("review.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DANTE_REVIEW ",JSON.stringify(report))
	quit()

func combat_sequence(id: String, variant: int, reload_action: bool, _camera: Camera3D, suffix := "") -> void:
	actor.visual.rotation = Vector3.ZERO
	actor._locomotion_weight = 0.0
	actor._run_weight = 0.0
	actor.combat_facing = 0.0
	var gun := Node3D.new()
	view.add_child(gun)
	if id != "fists": ARSENAL.build(gun,id)
	var pose = POSE.new()
	for t in 45:
		actor._apply_pose(actor._idle_pose)
		actor.set_combat_weapon_pose(id,pose.update(id,1.0/60.0,true,false,0.0,false,false,0.0))
		actor._apply_combat_weapon_pose()
	var label := "%s_%d_%s%s" % [id,variant,"reload" if reload_action else "attack",suffix]
	var previous: Array = actor._capture_pose()
	var max_jump := {"max_degrees":0.0,"bone":"","tick":0}
	for n in variant + 1: pose.attack(id)
	var start_pose: Array = actor._capture_pose()
	var samples := []
	for tick in 60:
		actor._apply_pose(actor._idle_pose)
		var packet: Dictionary = pose.update(id,1.0/60.0,true,reload_action,float(tick)/59.0,false,false,0.0)
		actor.set_combat_weapon_pose(id,packet)
		actor._apply_combat_weapon_pose()
		gun.visible = bool(packet.visible) and id != "fists"
		if id != "fists": gun.global_transform = actor.combat_weapon_transform(DATA.GRIPS.get(id,Vector3.ZERO))
		var now: Array = actor._capture_pose()
		var diff := difference(previous,now)
		if diff.max_degrees > max_jump.max_degrees:
			max_jump = diff
			max_jump["tick"] = tick
		previous = now
		if tick in [0,3,6,9,12,18,24,35,47,59]:
			await snapshot("combat_%s_%02d" % [label,tick])
			var entry := {"tick":tick,"left":str(actor.combat_palm_position("Left")),"right":str(actor.combat_palm_position("Right"))}
			samples.append(entry)
	report.combat[label] = {"max_frame_jump":max_jump,"samples":samples,"return_delta":difference(start_pose,actor._capture_pose())}
	gun.queue_free()
	await process_frame
