extends SceneTree
## Focused rendered regression: real native Actor, room, Gameplay signals and
## WorkplaceThreatReaction. No session/save mock replaces the reaction or IK.
const ROOM := preload("res://world/places/curitiba_cellar/CuritibaCellarPlace.gd")
const MODEL := preload("res://world/places/curitiba_cellar/LuisaModel.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const GAMEPLAY := preload("res://gameplay/Gameplay.gd")
const REACTION := preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd")
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
var checks := 0
var failures: Array[String] = []
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var room: Node3D
var actor: CharacterBody3D
var model: Node3D
var gameplay: Node3D
var reaction: Node
var folder := ""
var hand_samples: Array = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("CELLAR_LUISA ","PASS " if value else "FAIL ",label)
	if not value: failures.append(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func run() -> void:
	create_timer(75).timeout.connect(func(): push_error("CELLAR_LUISA timeout"); quit(3))
	folder = FIXTURE.output_dir("curitiba-cellar-luisa")
	viewport = SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	room = ROOM.new()
	room.definition = ROOM.definition_data()
	stage.add_child(room)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("262c2c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c4c2b5")
	settings.ambient_light_energy = .60
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50,-30,0)
	sun.light_energy = .7
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = room.camera_size
	stage.add_child(camera)
	camera.position = room.camera_target + Vector3(0,18,15)
	camera.look_at(room.camera_target)
	camera.current = true
	await frames(3)
	actor = ACTOR.new()
	actor.controlled_automatically = true
	actor.position = Vector3(4.65,.04,-3.92)
	actor.set_meta("interior_npc_id","cellar_luisa")
	stage.add_child(actor)
	var original: Node = actor.visual.get_child(0)
	actor.visual.remove_child(original)
	original.free()
	model = MODEL.new()
	actor.visual.add_child(model)
	# The real Gameplay signal/catalog owner is sufficient for this scoped
	# runtime integration. It is not added to a full city or allowed to save.
	gameplay = GAMEPLAY.new()
	reaction = REACTION.install(actor,model,gameplay)
	await frames(15)
	check(reaction != null,"real workplace reaction installed")
	check(is_equal_approx(model.sit_amount,1.0),"Luisa seated in normal operation")
	check(model.pelvis.global_position.y < .65,"pelvis rests at chair height rather than standing height")
	check(is_equal_approx(model.scale.x,.96),"authored human scale preserved")
	var chair: Node3D = model.work_chair
	var chair_home := chair.global_transform
	var home := actor.global_position
	for i in 20:
		await frames(1)
		for side in 2:
			# CivilianMeshKit.forearm_mesh authors the curved finger pad at
			# y=-.35,z=.012; inspect the actual rendered fingers, not the IK target.
			var endpoint: Vector3 = model.forearms[side].to_global(Vector3(.012 if side == 0 else -.012,-.35,.012))
			hand_samples.append({"side":side,"x":endpoint.x,"y":endpoint.y,"z":endpoint.z})
	var contact := true
	for sample in hand_samples:
		contact = contact and sample.x >= 4.35 and sample.x <= 4.83 and sample.z >= -3.48 and sample.z <= -3.29 and absf(sample.y-.883) < .035
	check(contact,"both native fingertip paths contact the actual keyboard surface")
	var motion := 0.0
	for i in range(2,hand_samples.size()): motion = maxf(motion,absf(float(hand_samples[i].y)-float(hand_samples[i-2].y)))
	check(motion > .0001,"typing has continuous articulated hand motion")
	await photo("01-seated-final-camera")
	var camera_home := camera.global_transform
	var camera_size := camera.size
	camera.size = 3.0
	camera.position = Vector3(2.0,2.5,-1.1)
	camera.look_at(Vector3(4.65,.8,-3.5))
	await photo("02-seated-hand-contact")
	camera.global_transform = camera_home
	camera.size = camera_size
	if "--photo-only" in OS.get_cmdline_user_args():
		print("CELLAR_LUISA_PHOTO ",folder," checks=",checks," failures=",failures)
		gameplay.free()
		stage.free()
		viewport.free()
		await process_frame
		quit(0 if failures.is_empty() else 1)
		return
	# A shot from her right admits a real 1.6 m retreat into the rear staff
	# aisle. A frontal shot is intentionally blocked by the rear bookcase.
	gameplay.weapon_fired.emit("pistol",home+Vector3(3,0,0))
	await frames(40)
	check(actor.get_meta("workplace_threatened",false),"gunfire signal interrupts financial work")
	check(actor.global_position.distance_to(home) > .75,"real reaction moves through the clear staff aisle")
	check(is_zero_approx(model.sit_amount) and model.pelvis.global_position.y > .75,"retreat is standing rather than a sliding seated pose")
	check(chair.global_transform.is_equal_approx(chair_home),"chair remains at the desk during physical retreat")
	check(is_instance_valid(model.chair_body),"unoccupied chair receives a physical solid")
	var visitor := ACTOR.new()
	visitor.controlled_automatically = true
	stage.add_child(visitor)
	visitor.set_physics_process(false)
	visitor.collision_mask = 1
	await frames(2)
	var from := visitor.global_transform
	from.origin = home+Vector3(-1,0,0)
	var collision := KinematicCollision3D.new()
	check(visitor.test_move(from,Vector3(1.4,0,0),collision) and collision.get_collider() == model.chair_body,"visitor sweep stops at the empty chair")
	visitor.free()
	await photo("03-standing-retreat-chair-fixed")
	await frames(290)
	check(not reaction.active and not actor.get_meta("workplace_threatened",false),"quiet releases real reaction after return")
	check(actor.global_position.distance_to(home) < .08 and is_equal_approx(model.sit_amount,1.0),"Luisa sits only after returning to her original chair")
	check(chair.global_transform.is_equal_approx(chair_home),"chair remains anchored through recovery")
	check(model.hand_provider == Callable(model,"_typing_hands"),"recovery restores the financial typing provider")
	await photo("04-returned-to-work")
	model.hide()
	check(not chair.is_visible_in_tree(),"top-level chair still follows resident visibility")
	model.show()
	gameplay.npc_gunfire.emit(home+Vector3(3,0,0),Vector3.LEFT,null)
	await frames(12)
	actor.dead = true
	await frames(18)
	check(not reaction.active,"death cancels the active workplace reaction")
	var physical_chair: Node = model.chair_body
	actor.free()
	check(not is_instance_valid(chair) and not is_instance_valid(physical_chair),"actor unload frees anchored chair and its collider")
	gameplay.free()
	var report := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	check(report != null,"evidence folder writable")
	if report != null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"hand_samples":hand_samples,"renderer":RenderingServer.get_current_rendering_method(),"notes":"Scoped real actor/room/reaction and native IK. Gameplay signal owner uses production code without starting the full city. Screenshots do not replace Main temporal/performance evidence."},"\t"))
	print("CELLAR_LUISA_RESULT ",folder," checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func photo(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	check(pixels.save_png(folder.path_join(label+".png")) == OK,"rendered evidence "+label)
