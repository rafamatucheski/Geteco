extends SceneTree
## Arena real, cápsulas do Actor e monstros autorais. É uma fixture delimitada
## de geometria/profundidade, não ciclo de vida do Main nem benchmark de desempenho.
const WORLD := preload("res://world/places/upside_world/UpsideWorld.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var checks := 0
var failures: Array[String] = []
var records: Array = []
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var arena: Node3D
var folder := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("UPSIDE_GEOMETRY ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	create_timer(90).timeout.connect(func(): push_error("UPSIDE_GEOMETRY timeout"); quit(3))
	folder = FIXTURE.output_dir("upside-world-geometry")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	arena = WORLD.new()
	stage.add_child(arena)
	var environment := WorldEnvironment.new()
	environment.environment = arena.make_environment()
	stage.add_child(environment)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 72.0
	camera.near = .05
	camera.far = 95.0
	stage.add_child(camera)
	camera.position = arena.spawn_local+Vector3.UP*1.65
	camera.look_at(Vector3(0,1.5,-7))
	camera.current = true
	await frames(24)
	check(arena.solid_bodies.size() >= 35,"independent walls ruins furniture and boundary roots have physical volumes")
	check(arena.is_floor_clear(arena.spawn_local),"authored first-person arrival is clear")
	check(arena.monsters.size() == 4,"four independently authored hallucination bodies")
	check(arena.local_lights.size() == 2,"two stable motivated local light sources")
	check(arena.meteor_batch.instance_count == 22 and arena.rain_batch.instance_count == 112,"bounded batched weather has fixed instance counts")
	for node in arena.get_children():
		if not node is MeshInstance3D or not node.has_meta("interior_solid_id"): continue
		var id := str(node.get_meta("interior_solid_id"))
		var visual: AABB = node.transform*node.get_aabb()
		var physical := AABB()
		var found := false
		for body in arena.solid_bodies:
			if str(body.get_meta("interior_solid_id","")) == id: physical = body.get_meta("bounds"); found = true; break
		check(found and physical.grow(.002).encloses(visual),"physical bounds cover visible solid "+id)
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player = player
		actor.controlled_automatically = true
		stage.add_child(actor)
		actor.set_physics_process(false)
		actor.collision_mask = 1
		await frames(2)
		var who := "Dante" if player else "visitor"
		for point in [arena.spawn_local,Vector3(0,.08,-4),Vector3(-4,.08,7),Vector3(4,.08,7),Vector3(-5,.08,-2),Vector3(5,.08,-4)]:
			check(_clear(actor,point),who+" complete capsule clear at "+str(point))
			check(_support(point),who+" continuous floor supports "+str(point))
		var swept := 0
		for body in arena.solid_bodies:
			var bounds: AABB = body.get_meta("bounds")
			if str(body.get_meta("interior_solid_id")) == "UnbrokenFloor" or bounds.position.y > 1.7: continue
			var center := bounds.get_center()
			for direction: Vector3 in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:
				var extent := bounds.size.x*.5 if absf(direction.x)>.5 else bounds.size.z*.5
				var start := Vector3(center.x,.08,center.z)+direction*(extent+.85)
				if absf(start.x)>13.35 or absf(start.z)>13.35 or not _clear(actor,start): continue
				var from := actor.global_transform
				from.origin = start
				check(actor.test_move(from,-direction*(extent*2+1.7)),who+" long sweep blocks "+str(body.name))
				swept += 1
				break
		check(swept >= 20,who+" tests reachable boundaries across full arena")
		actor.free()
	var homes := []
	for monster in arena.monsters:
		homes.append(monster.position)
		check(monster.collision_layer == 0 and monster.collision_mask == 1 and not monster.has_method("receive_damage"),"monster is physically constrained illusion without damage interface")
		check(not monster.test_move(monster.global_transform,Vector3.UP*.005),"monster full body starts outside solid architecture")
		check(_support(monster.position+Vector3.UP*.08),"monster rests on real continuous floor")
	await photo("01-first-person-arrival")
	await frames(240)
	var movers := 0
	for index in arena.monsters.size():
		var monster: CharacterBody3D = arena.monsters[index]
		if monster.position.distance_to(homes[index]) > .3: movers += 1
		check(not monster.test_move(monster.global_transform,Vector3.UP*.005),"pursuing monster remains outside solid architecture")
		check(absf(monster.position.x)<13.4 and absf(monster.position.z)<13.4,"pursuing monster remains in physical arena")
	check(movers == 4,"all four silhouettes pursue with native movement")
	await photo("02-first-person-pursuit")
	camera.look_at(Vector3(-4,10,-16))
	await photo("03-sky-meteors-ruins")
	# Congela só para as capturas de máscara de diagnóstico. Arquitetura e ator compartilham
	# o mesmo buffer de profundidade; esconder o cenário fornece um controle positivo.
	arena.set_process(false)
	for monster in arena.monsters: monster.set_physics_process(false); monster.hide()
	var subject: CharacterBody3D = arena.monsters[0]
	subject.show()
	var mask := StandardMaterial3D.new()
	mask.albedo_color = Color(0,1,.01)
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for mesh in subject.find_children("*","MeshInstance3D",true,false): mesh.material_override = mask
	camera.position = Vector3(0,1.65,7)
	subject.position = Vector3(0,.05,-4)
	subject.reset_physics_interpolation()
	camera.look_at(Vector3(0,1.65,-4))
	await _depth_case(subject,"visible-first-person",false)
	# Olhando para uma parede genuína de ruína ao fundo: o monstro fica posicionado no
	# piso livre atrás da parede, não embutido no sólido dela.
	camera.position = Vector3(-10.15,1.65,-.8)
	subject.position = Vector3(-10.15,.05,-10.2)
	subject.reset_physics_interpolation()
	camera.look_at(subject.position+Vector3.UP*1.6)
	await _depth_case(subject,"behind-ruin",true)
	var wind: Node = arena.wind
	var before: float = arena.elapsed
	arena.set_active(false)
	await frames(3)
	check(is_equal_approx(arena.elapsed,before) and wind.stream_paused,"inactive arena suspends effects and wind")
	arena.set_active(true)
	var report := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	check(report != null,"diagnostic evidence writable")
	if report != null: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"stats":arena.get_stats(),"depth":records,"renderer":RenderingServer.get_current_rendering_method(),"notes":"Actual Actor/monster physics and rendered first-person depth; scoped fixture does not certify Main lifecycle or frame time."},"\t"))
	stage.free()
	check(not is_instance_valid(wind) and not is_instance_valid(subject),"arena unload frees owned audio and monsters")
	viewport.free()
	await process_frame
	print("UPSIDE_GEOMETRY_RESULT ",folder," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _clear(actor: CharacterBody3D, point: Vector3) -> bool:
	var from := actor.global_transform
	from.origin = point
	return not actor.test_move(from,Vector3.UP*.001)

func _support(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*.15,point-Vector3.UP*.35,1)
	var hit := stage.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.normal.y>.8 and absf(float(hit.position.y))<.03

func _capture() -> Image:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var pixels := await _capture()
	check(pixels.save_png(folder.path_join(label+".png"))==OK,"first-person evidence "+label)

func _count(image: Image) -> int:
	var found := 0
	for y in image.get_height():
		for x in image.get_width():
			var value := image.get_pixel(x,y)
			if value.g>.55 and value.r<.25 and value.b<.30: found += 1
	return found

func _depth_case(subject: Node3D, label: String, occluded: bool) -> void:
	var rendered := await _capture()
	var scenery: Array[Node3D] = []
	for child in arena.get_children():
		if child is Node3D and child != subject and not child is Light3D and child.visible:
			scenery.append(child)
			child.hide()
	var control := await _capture()
	for child in scenery: child.show()
	var reference := _count(control)
	var actual := _count(rendered)
	var ratio := float(actual)/maxf(reference,1)
	check(reference>80,label+" positive control shows the actual monster")
	check(ratio<.12 if occluded else ratio>.80,label+" real depth ratio "+str(ratio))
	rendered.save_png(folder.path_join(label+".png"))
	control.save_png(folder.path_join(label+"-control.png"))
	records.append({"id":label,"actual":actual,"control":reference,"ratio":ratio})
