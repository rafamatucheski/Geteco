extends SceneTree
## Offline movie writer or representative native 3D frames; never opens a user save.
var world
var director
var elapsed := 0.0
var recording := false
var output := "D:/geteco/artifacts/opening-ferry-20261003"
var frames := 0
var start_frame := 0
var movie_frames := 0
var previous_bones: Array[Quaternion] = []
var previous_phone := Vector3.ZERO
var max_bone_step := 0.0
var max_phone_step := 0.0
var max_background_drift := 0.0
var activity_motion: Dictionary = {}
var review_frames := [90,120,1710,1770,2100,2130]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	if DisplayServer.get_name()=="headless":
		push_error("Ferry authoring requires real MultiMesh instance data and the rendered set")
		quit(2)
		return
	# O filme inteiro (carga de ~90 s e 2.190 quadros gravados) passa de 10 min.
	create_timer(2400).timeout.connect(func(): push_error("Ferry capture timed out"); quit(2))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	root.get_node("V2Launch").selected_path = "user://opening-authoring-isolated.json"
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	# Prazo em tempo, não em quadros: o pré-aquecimento das regiões sob a cortina
	# passou de 20 s (16/10) e 1200 quadros acabavam antes do jogo ficar pronto.
	var ready_deadline := Time.get_ticks_msec() + 240000
	while Time.get_ticks_msec() < ready_deadline:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	assert(world.session != null and world.session.ready_for_play)
	# A abertura começa ~120 m ao norte do berço. Com o foco só no berço, as células do
	# canal ficavam meio montadas e, vistas do alto, só o contorno das placas aparecia
	# riscando o mar. Passa o jogador por pontos de terra ao longo da rota e espera cada
	# trecho terminar; todos ficam a até 2 células do berço (retention_radius).
	for point in [Vector3(282,.6,72),Vector3(282,.6,128),Vector3(201,.6,191),Vector3(233,.56,188.2)]:
		world.player.teleport(point)
		var settle := Time.get_ticks_msec() + 60000
		for i in 20: await physics_frame
		while not world.production.region.is_streaming_idle() and Time.get_ticks_msec() < settle: await physics_frame
	world.production.region.set_focus(Vector3(233,0,183.5))
	for i in 120: await physics_frame
	director = preload("res://cutscenes/opening/ferry/FerryDirector.gd").new()
	world.add_child(director)
	director.configure(world)
	DirAccess.make_dir_recursive_absolute(output)
	print("FERRY_ACTIVITY workers=",director.night_set.activity.workers.size()," fishers=",director.night_set.activity.fishers.size()," cranes=",director.night_set.activity.cargo.cranes.size())
	if "--check-work-routes" in OS.get_cmdline_user_args() or "--verify-work-routes" in OS.get_cmdline_user_args():
		var routes_clear := await _check_work_routes()
		if not routes_clear or "--check-work-routes" in OS.get_cmdline_user_args():
			world.queue_free()
			await process_frame
			quit(0 if routes_clear else 1)
			return
	if "--phone-poses" in OS.get_cmdline_user_args():
		var variants := [[-1.5,-.8],[0,.8],[1.5,.8],[3,.8]]
		for i in variants.size():
			director.sample(43.0,1.0/30.0)
			director.dante._apply_pose(director.dante._idle_pose)
			director.dante._apply_idle_breath()
			preload("res://cutscenes/opening/ferry/FerryPhonePose.gd").apply(director.dante,director.phone,1.0,variants[i][0],variants[i][1])
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+"/phone-%02d.png"%i)
		print("FERRY_PHONE_POSES_OK")
		await finish()
		return
	if "--layout" in OS.get_cmdline_user_args():
		director.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		director.camera.size = 225.0
		director.camera.global_position = Vector3(260,240,170)
		director.camera.look_at(Vector3(260,0,170),Vector3.FORWARD)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/layout.png")
		quit()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="):
			# Mapa livre/ocupado para uma cápsula de pessoa: "." livre, "#" sólido, " " sem chão.
			var r := Array(arg.trim_prefix("--probe=").split(",")).map(func(v): return float(v))
			await _probe(r[0],r[1],r[2],r[3])
			world.queue_free()
			await process_frame
			quit(0)
			return
	if "--hide-skirts" in OS.get_cmdline_user_args():
		for mesh in world.find_children("*","MeshInstance3D",true,false):
			if mesh.mesh == null or not "CellMergeBatches" in str(mesh.get_path()): continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if absf(box.position.y+.3) < .01 and absf(box.end.y) < .01:
				print("FERRY_HIDE_SKIRT ",mesh.get_path()," ",box)
				mesh.hide()
	if "--water-meshes" in OS.get_cmdline_user_args():
		# Diagnóstico: superfícies grandes perto da linha d'água (riscos vistos do alto).
		for mesh in world.get_tree().root.find_children("*","MeshInstance3D",true,false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			if box.position.y > .3 or box.end.y < -1.6: continue
			if maxf(box.size.x,box.size.z) < 30.0: continue
			var material = mesh.material_override if mesh.material_override != null else mesh.mesh.surface_get_material(0)
			print("FERRY_WATER_MESH ",mesh.get_path()," y=%.3f..%.3f"%[box.position.y,box.end.y]," xz=",Vector2(box.position.x,box.position.z),"..",Vector2(box.end.x,box.end.z)," mat=",material.resource_path if material else "-"," ",material.get_class() if material else "")
		world.queue_free()
		await process_frame
		quit(0)
		return
	if "--validate-motion" in OS.get_cmdline_user_args():
		# Mesma checagem de braço/celular do gravador, sem gravar: os ossos são CPU.
		var jumps := 0
		var last: Array[Quaternion] = []
		for frame in roundi(director.length*30.0):
			var t := float(frame)/30.0
			director.sample(t,1.0/30.0)
			var now: Array[Quaternion] = []
			for name in ["RightArm","RightForeArm","RightHand"]:
				now.append(director.dante.skeleton.get_bone_pose_rotation(director.dante.skeleton.find_bone(name)))
			if not last.is_empty():
				for i in now.size():
					var step := last[i].angle_to(now[i])
					if step >= .1:
						jumps += 1
						if jumps <= 20: print("FERRY_MOTION_JUMP quadro=%d t=%.2f osso=%d %.1f°"%[frame,t,i,rad_to_deg(step)])
			var phone_at: Vector3 = director.ferry.to_local(director.phone.global_position)
			if director.phone.visible and frame > 0 and phone_at.distance_to(previous_phone) >= .04:
				jumps += 1
				if jumps <= 20: print("FERRY_MOTION_PHONE quadro=%d t=%.2f %.3f m"%[frame,t,phone_at.distance_to(previous_phone)])
			previous_phone = phone_at
			last = now
		print("FERRY_MOTION jumps=",jumps)
		world.queue_free()
		await process_frame
		quit(0 if jumps == 0 else 1)
		return
	if "--check-route" in OS.get_cmdline_user_args():
		var clear := await _check_route()
		world.queue_free()
		await process_frame
		quit(0 if clear else 1)
		return
	if "--stills" in OS.get_cmdline_user_args():
		var times := [3.0,9.5,14.0,18.5,23.0,27.0,30.0,33.5,39.0,44.0,46.5,51.5,57.5,64.0,69.5,72.0]
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--times="):
				times.clear()
				for value in arg.trim_prefix("--times=").split(","): times.append(float(value))
		for t in times:
			# Um segundo de pré-rolagem: passada, mistura de poses e olhar têm estado.
			for i in 30: director.sample(maxf(t-1.0+i/30.0,0.0),1.0/30.0)
			director.sample(t,1.0/30.0)
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var result := root.get_texture().get_image().save_png(output+"/shot-%04.1f.png"%t)
			assert(result == OK)
		print("FERRY_STILLS_OK")
		world.queue_free()
		await process_frame
		quit()
	else:
		var matte := CanvasLayer.new()
		root.add_child(matte)
		for bottom in [false,true]:
			var bar := ColorRect.new()
			bar.color = Color.BLACK
			bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
			if bottom: bar.offset_top = -root.size.y*.125
			else: bar.offset_bottom = root.size.y*.125
			matte.add_child(bar)
		director.sample(0.0,1.0/30.0)
		start_frame = frames
		print("FERRY_MOVIE_START_FRAME ",start_frame)
		recording = true

func _process(delta: float) -> bool:
	frames += 1
	if not recording: return false
	elapsed = float(movie_frames)/30.0
	director.sample(elapsed,delta)
	_validate_motion()
	_measure_activity()
	if movie_frames in review_frames: _capture_activity.call_deferred(movie_frames)
	movie_frames += 1
	if movie_frames >= roundi(director.length*30.0):
		recording = false
		var file := FileAccess.open(output+"/render.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"start_frame":start_frame,"end_frame":frames,"duration":director.length,"fps":30,"size":str(root.size),"max_bone_step_degrees":rad_to_deg(max_bone_step),"max_phone_step_m":max_phone_step,"max_background_drift_m":max_background_drift,"stationary_background_bodies":director.night_set.frozen_bodies.size(),"activity_motion":activity_motion},"\t"))
		file.close()
		var activity = director.night_set.activity
		assert(not activity.workers.is_empty(),"Capture must contain working dock operators")
		assert(activity.fishers.size()==2,"Both fishing posts must be directed")
		for record in activity.workers:
			assert(activity_motion[str(record.actor.get_path())].distance_m>5.0,"Dock worker remained frozen")
		for i in activity.cargo.cranes.size():
			assert(activity_motion["crane_%d"%i].distance_m>10.0,"Cargo handling remained frozen")
		print("FERRY_MOVIE_FINISHED ",frames-start_frame," frames")
		finish.call_deferred()
	return false

func _capture_activity(frame: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+"/activity-%04d.png"%frame)

func _track_motion(key: String, point: Vector3) -> void:
	if not activity_motion.has(key): activity_motion[key] = {"previous":point,"distance_m":0.0,"max_step_m":0.0}
	var record: Dictionary = activity_motion[key]
	var step: float = point.distance_to(record.previous)
	record.distance_m += step
	record.max_step_m = maxf(record.max_step_m,step)
	record.previous = point

func _measure_activity() -> void:
	var activity = director.night_set.activity
	for record in activity.workers: _track_motion(str(record.actor.get_path()),record.actor.global_position)
	for i in activity.cargo.cranes.size(): _track_motion("crane_%d"%i,activity.cargo.cranes[i].visual.global_position)
	for i in activity.fishers.size(): _track_motion("fishing_rod_%d"%i,activity.fishers[i].rod.to_global(Vector3(0,1.1,2)))

func _check_work_routes() -> bool:
	# Keep the real authored solids available to queries while their scripts and
	# gameplay managers are suspended. Test support separately from obstruction.
	var modes: Dictionary = {}
	for body in world.find_children("*","StaticBody3D",true,false):
		modes[body] = body.disable_mode
		body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = .25
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var failures: Dictionary = {}
	var checks := 0
	for frame in range(0,2190,3):
		director.sample(float(frame)/30.0,.1)
		for record in director.night_set.activity.workers:
			var point: Vector3 = record.actor.global_position
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.87)
			var hits := space.intersect_shape(query,1)
			var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP*.25,1))
			checks += 2
			if (not hits.is_empty() or ground.is_empty()) and not failures.has(record.actor.name):
				failures[record.actor.name] = {"time":float(frame)/30.0,"position":point,"unsupported":ground.is_empty(),"solid":str(hits[0].collider.get_path()) if not hits.is_empty() else ""}
	FileAccess.open(output+"/work-routes.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("FERRY_WORK_ROUTES checks=",checks," failures=",JSON.stringify(failures))
	for body in modes: body.disable_mode = modes[body]
	await physics_frame
	return failures.is_empty()

func _probe(x0: float, z0: float, x1: float, z1: float) -> void:
	var modes: Dictionary = {}
	for body in world.find_children("*","StaticBody3D",true,false):
		modes[body] = body.disable_mode
		body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = .25
	shape.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	print("FERRY_PROBE x=%.1f..%.1f z=%.1f..%.1f passo 0,5 m (linhas = z)"%[x0,x1,z0,z1])
	var z := z0
	while z <= z1:
		var row := "FERRY_PROBE %6.1f "%z
		var x := x0
		while x <= x1:
			var point := Vector3(x,.14,z)
			query.transform = Transform3D(Basis.IDENTITY,point+Vector3.UP*.87)
			var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP*.25,1))
			row += " " if ground.is_empty() else ("#" if not space.intersect_shape(query,1).is_empty() else ".")
			x += .5
		print(row)
		z += .5
	for body in modes: body.disable_mode = modes[body]

func _check_route() -> bool:
	# Só a parte do casco acima da linha d'água importa na imagem; abaixo dela
	# a caixa tocava o fundo modelado do canal em trechos de água livre.
	var ferry: Node3D = director.ferry
	var box := AABB()
	var first := true
	for mesh in ferry.find_children("*","MeshInstance3D",true,false):
		if director.dante.is_ancestor_of(mesh) or director.passenger.is_ancestor_of(mesh): continue
		var local: AABB = ferry.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	box.position.y = .3
	box.size.y = 1.2
	var shape := BoxShape3D.new()
	shape.size = box.size
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	var excluded: Array[RID] = []
	for body in ferry.find_children("*","CollisionObject3D",true,false): excluded.append(body.get_rid())
	query.exclude = excluded
	var modes: Dictionary = {}
	for body in world.find_children("*","StaticBody3D",true,false):
		modes[body] = body.disable_mode
		body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var hits_by_time := {}
	for frame in range(0,roundi(director.length*30.0),15):
		var t := float(frame)/30.0
		director.sample(t,.5)
		query.transform = ferry.global_transform*Transform3D(Basis.IDENTITY,box.get_center())
		var hits := space.intersect_shape(query,6)
		if not hits.is_empty():
			var names := []
			for hit in hits: names.append(str(hit.collider.get_path()).get_file())
			hits_by_time["%.1f"%t] = {"position":ferry.global_position,"solids":names}
	FileAccess.open(output+"/route.json",FileAccess.WRITE).store_string(JSON.stringify({"hull":str(box),"hits":hits_by_time},"\t"))
	print("FERRY_ROUTE hull=",box," hits=",hits_by_time.size())
	for t in hits_by_time: print("FERRY_ROUTE_HIT ",t," ",hits_by_time[t])
	for body in modes: body.disable_mode = modes[body]
	return hits_by_time.is_empty()

func _validate_motion() -> void:
	# Detect the reported flips and circling across all 2,190 authored frames.
	var rotations: Array[Quaternion] = []
	for name in ["RightArm","RightForeArm","RightHand"]:
		var bone: int = director.dante.skeleton.find_bone(name)
		rotations.append(director.dante.skeleton.get_bone_pose_rotation(bone))
	var relative_phone: Vector3 = director.ferry.to_local(director.phone.global_position)
	if not previous_bones.is_empty():
		for i in rotations.size():
			var bone_step := previous_bones[i].angle_to(rotations[i])
			if bone_step >= .1 and max_bone_step < .1:
				push_error("Primeiro salto de braço: quadro %d (%.2f s), osso %d, %.1f°"%[movie_frames,elapsed,i,rad_to_deg(bone_step)])
			max_bone_step = maxf(max_bone_step,bone_step)
		if director.phone.visible: max_phone_step = maxf(max_phone_step,relative_phone.distance_to(previous_phone))
	previous_bones = rotations
	previous_phone = relative_phone
	for body in director.night_set.frozen_bodies:
		if is_instance_valid(body.node):
			var drift: float = body.position.distance_to(body.node.global_position)
			if drift > .005:
				push_error("Cinematic mark moved: %s (%s), %.4f m"%[body.node.get_path(),body.node.get_script(),drift])
				recording = false
				quit(1)
				return
			max_background_drift = maxf(max_background_drift,drift)
	assert(max_bone_step < .1,"Sudden arm/wrist flip in the film")
	assert(max_phone_step < .04,"Phone jumps relative to the actor")
	assert(max_background_drift < .005,"Background extras left their cinematic marks")

func finish() -> void:
	world.queue_free()
	await process_frame
	await process_frame
	quit()
