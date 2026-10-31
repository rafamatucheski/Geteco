extends SceneTree
## Native actor/shaft: approach, take hold, descend, rotated access and cancellation.
const HATCH := preload("res://world/urban_detail/HarborManholeExterior3D.gd")
const DESCENT := preload("res://gameplay/SewerHatchDescent.gd")
var failures: Array[String] = []
var scene: Node3D
var actor: CharacterBody3D
var hatch: Node3D
var descent: Node
var active := true
var observing := false
var initial_y := 0.0
var started_down := false
var down_at_ladder := true
var cover_clear := true
var ground_grip_time := 0.0
var max_hand_gap := 0.0
var last_frame := 0
var captured: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func floor_piece(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.position = at
	body.add_child(collider)
	var art := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	art.mesh = mesh
	body.add_child(art)
	scene.add_child(body)
func snapshot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless" or captured.has(label): return
	captured[label] = true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://output/manhole-access/"+label+".png")
func observe() -> void:
	if not observing: return
	var now := Time.get_ticks_usec()
	var seconds := float(now-last_frame)/1000000.0
	last_frame = now
	var local := hatch.to_local(actor.global_position)
	var offset: Vector3 = local-hatch.descent.ladder_stand
	var at_ladder := Vector2(offset.x, offset.z).length() < .04
	if not started_down and at_ladder and actor.global_position.y >= initial_y-.02:
		ground_grip_time += seconds
		snapshot.call_deferred("grip")
	if actor.global_position.y < initial_y-.04:
		if not started_down:
			down_at_ladder = at_ladder
			cover_clear = hatch.open_amount > .99
		started_down = true
		for side in ["Left", "Right"]:
			var palm: Vector3 = actor._clip_palm(side)
			var rail: Vector3 = hatch.ladder_handhold(palm)
			max_hand_gap = maxf(max_hand_gap, Vector2(palm.x-rail.x, palm.z-rail.z).length())
		if local.y < -.55 and local.y > -.9: snapshot.call_deferred("descent")

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute("res://output/manhole-access")
	scene = Node3D.new()
	root.add_child(scene)
	# As lajes da rua recortam o poço real, em vez de apoiar um ator voando.
	floor_piece(Vector3(-2.28125,-.1,0), Vector3(3.4375,.2,8))
	floor_piece(Vector3(2.28125,-.1,0), Vector3(3.4375,.2,8))
	floor_piece(Vector3(0,-.1,-2.28125), Vector3(1.125,.2,3.4375))
	floor_piece(Vector3(0,-.1,2.28125), Vector3(1.125,.2,3.4375))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5
	camera.position = Vector3(2.5,5,4)
	scene.add_child(camera)
	camera.look_at(Vector3(0,.3,0))
	camera.make_current()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-25,0)
	scene.add_child(sun)
	hatch = HATCH.new()
	hatch.setup({"id":"harbor_sewer", "kind":"sewer", "size":Vector2(2,2)})
	scene.add_child(hatch)
	actor = preload("res://scripts/Actor.gd").new()
	actor.is_player = true
	actor.controlled_automatically = true
	actor.position = Vector3(0,.04,1.3)
	scene.add_child(actor)
	for i in 15: await physics_frame
	check(hatch.find_child("ShaftVoid",true,false) == null, "abertura deixa escada visível")
	var cover: CollisionShape3D = hatch.find_child("ClosedCoverCollision",true,false).get_child(0)
	check(is_zero_approx(cover.position.y+cover.shape.height*.5), "tampa física termina no piso")
	for yaw in [0.0, PI*.5]:
		hatch.rotation.y = yaw
		hatch.set_open_amount(0)
		actor.teleport(hatch.to_global(Vector3(0,.04,1.3)))
		for i in 10: await physics_frame
		initial_y = actor.global_position.y
		started_down = false
		down_at_ladder = true
		cover_clear = true
		ground_grip_time = 0
		max_hand_gap = 0
		descent = DESCENT.new()
		descent.setup(actor,hatch,func() -> bool: return active)
		scene.add_child(descent)
		check(descent.can_run(), "clipes de escada disponíveis")
		last_frame = Time.get_ticks_usec()
		observing = true
		process_frame.connect(observe)
		await snapshot("closed")
		var ok: bool = await descent.descend()
		observing = false
		process_frame.disconnect(observe)
		check(ok and started_down, "descida completa yaw="+str(yaw))
		check(down_at_ladder and cover_clear and ground_grip_time >= .3, "chega e segura a escada antes de baixar")
		check(absf(hatch.to_local(actor.global_position).z+.19) < .04, "desce alinhado à escada na parede")
		print("HAND_RAIL_GAP ",max_hand_gap)
		check(max_hand_gap < .05, "mãos ficam nos trilhos reais durante a descida")
		descent.prepare_exit()
		check(await descent.ascend(hatch.to_global(Vector3(0,0,.95))), "subida retorna à borda")
		check(actor.is_physics_processing(), "controle físico restaurado")
		descent.free()
	actor.teleport(Vector3(0,.04,1.3))
	hatch.rotation.y = 0
	hatch.set_open_amount(0)
	descent = DESCENT.new()
	descent.setup(actor,hatch,func() -> bool: return active)
	scene.add_child(descent)
	create_timer(.2).timeout.connect(func(): active = false)
	check(not await descent.descend() and actor.is_physics_processing(), "cancelamento interrompe e restaura física")
	descent.free()
	print("MANHOLE_LADDER_ACCESS failures=",failures)
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
