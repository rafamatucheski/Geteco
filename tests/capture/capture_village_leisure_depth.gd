extends "res://tests/test_urban_operations.gd"
## Main-scene visual evidence only; physical fitting is logged separately.
## Run rendered with --no-save. No personal save may be loaded or overwritten.
const ART := preload("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd")
const LEISURE := preload("res://gameplay/urban_v1/TruckersVillageLeisure.gd")
const FOLDER := "res://evidence/village-leisure-20260929/depth"
const NPC_STAGING := Vector3(-325,.05,105)
const PLAYER_STAGING := Vector3(-322,.05,105)
const PROPS := [
	{"id":"windmill","center":Vector3(-332,0,91.4),"camera_offset":Vector3(0,7.5,11),"size":10.0,
		"front":Vector3(-332,.05,92.80),"behind":Vector3(-332,.05,90.0),"side":Vector3(-330.7,.05,91.4)},
	{"id":"garden","center":Vector3(-334.15,0,91.4),"camera_offset":Vector3(0,5.5,9),"size":7.5,
		"front":Vector3(-334.15,.05,93.2),"behind":Vector3(-334.15,.05,89.6),"side":Vector3(-336.15,.05,91.4)},
	{"id":"bicycle","center":Vector3(-337.4,0,84.1),"camera_offset":Vector3(9,6,1.4),"size":7.5,
		"front":Vector3(-336.45,.05,84.1),"behind":Vector3(-338.35,.05,84.1),"side":Vector3(-337.4,.05,85.95)}]
var checks := 0
var review: Camera3D
var npc: CharacterBody3D
var _saved: Dictionary = {}
var _rows: Array[Dictionary] = []

func check(value: bool,label: String) -> void:
	checks += 1
	super.check(value,label)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("VILLAGE_LEISURE_DEPTH requires rendered Main and --no-save")
		quit(2)
		return
	root.size = Vector2i(1280,720)
	seed(29092026)
	check(await _initialize_world(),"Main exposes the village for rendered depth captures")
	if not failures.is_empty():
		quit(1)
		return
	current_scene = world
	check(world.production.no_save,"Capture uses synthetic state without personal save access")
	if not world.production.no_save:
		world.free()
		quit(2)
		return
	check(is_instance_valid(urban.village) and is_instance_valid(urban.village_leisure),"Village art and leisure interaction are present")
	if not failures.is_empty():
		world.free()
		quit(1)
		return
	npc = urban.village.tonico
	_saved = {"npc_transform":npc.global_transform,"npc_velocity":npc.velocity,"npc_physics":npc.is_physics_processing(),
		"player_transform":world.player.global_transform,"player_auto":world.player.controlled_automatically,"player_direction":world.player.automatic_direction,
		"camera_heading":world.camera.heading,"camera_size":world.camera.target_size,"camera_input":world.camera.is_processing_unhandled_input(),
		"weather_time":session.weather.time_of_day,"weather_state":session.weather.weather_state,"weather_processing":session.weather.is_processing(),
		"window_size":root.size,"content_scale_size":root.content_scale_size}
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.camera.set_process_unhandled_input(false)
	session.weather.set_process(false)
	session.weather.time_of_day = .4
	session.weather.weather_state = 0
	session.weather._update()
	world.player.teleport(ART.PLAY_POINT+Vector3.UP*.05)
	world.production.region.set_focus(ART.PLAY_POINT)
	world.production.region.prepare_collision_at(ART.PLAY_POINT)
	urban.refresh_context()
	await settle(100)
	npc.set_physics_process(false)
	review = Camera3D.new()
	review.name = "VillageLeisureDepthReview"
	review.projection = Camera3D.PROJECTION_ORTHOGONAL
	review.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	review.near = .10
	review.far = 200.0
	# Keep the productive exterior layers and the same environment/profile.
	review.cull_mask = world.camera.cull_mask
	review.environment = world.camera.environment
	review.attributes = world.camera.attributes
	world.add_child(review)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	await _overview()
	for prop in PROPS:
		_position_camera(prop.center,prop.camera_offset,float(prop.size))
		for subject in ["player","npc"]:
			for side in ["front","behind","side"]:
				var point: Vector3 = prop[side]
				var player_at := point if subject=="player" else PLAYER_STAGING
				var npc_at := point if subject=="npc" else NPC_STAGING
				var free: bool = await _place_pair(player_at,npc_at)
				check(free,"Whole production capsules fit "+prop.id+" "+subject+" "+side)
				if not free: continue
				var row := {"prop":prop.id,"subject":subject,"side":side,"physical_fit":free,
					"player":str(world.player.global_position),"npc":str(npc.global_position),"camera":str(review.global_transform),
					"visible_player":world.player.is_visible_in_tree(),"visible_npc":npc.is_visible_in_tree(),"occlusion":"requires image inspection"}
				print("VILLAGE_LEISURE_DEPTH_POSE ",JSON.stringify(row))
				await _shot(prop.id+"-"+subject+"-"+side,row)
	await _normal_camera()
	await _compact_ui()
	await _restore_capture_state()
	FileAccess.open(FOLDER+"/poses.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"poses":_rows},"\t"))
	print("VILLAGE_LEISURE_DEPTH checks=",checks," failures=",failures," screenshots=",_rows.size())
	world.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _overview() -> void:
	await _place_pair(Vector3(-320,.05,92),Vector3(-330,.05,96))
	_position_camera(Vector3(-319,0,87),Vector3(4,36,39),48.0)
	await _shot("overview-yard",{"view":"shared yard, market baskets, garden, bicycle and court","occlusion":"overview only"})
	_position_camera(Vector3(-333,0,89),Vector3(6,17,20),22.0)
	await _shot("shared-yard-details",{"view":"market baskets, bicycle, windmill and garden","occlusion":"overview only"})

func _position_camera(center: Vector3,offset: Vector3,size: float) -> void:
	review.size = size
	review.global_position = center+offset
	review.look_at(center+Vector3.UP*.75)
	review.make_current()

func _place_pair(player_at: Vector3,npc_at: Vector3) -> bool:
	# First vacate the NPC's former pose, let the physics server publish it,
	# then move the player. Swapping occupied poses directly can create support
	# contacts and make the character appear to stand on the other actor.
	for point in [NPC_STAGING,PLAYER_STAGING,player_at,npc_at]:
		world.production.region.prepare_collision_at(point)
	npc.set_physics_process(false)
	npc.global_position = NPC_STAGING
	npc.velocity = Vector3.ZERO
	npc.model.teleported()
	await settle(2)
	world.player.teleport(player_at)
	world.production.region.set_focus(player_at)
	await settle(2)
	npc.global_position = npc_at
	npc.velocity = Vector3.ZERO
	npc.model.teleported()
	await settle(2)
	return _capsule_fits(world.player,world.player.global_position) and _capsule_fits(npc,npc.global_position)

func _capsule_fits(actor: CharacterBody3D,point: Vector3) -> bool:
	var collider: CollisionShape3D
	for child in actor.get_children():
		if child is CollisionShape3D:
			collider = child
			break
	if collider==null: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	# Raise the clearance query a few millimetres above the real resting contact
	# so the support terrain is not mistaken for penetration into an obstacle.
	query.transform = Transform3D(actor.global_basis,point+Vector3.UP*.015)*collider.transform
	query.collision_mask = 1
	query.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query).is_empty()

func _normal_camera() -> void:
	await _place_pair(ART.CACHE_POINT+Vector3.UP*.05,NPC_STAGING)
	world.camera.heading = 0.0
	world.camera.target_size = 23.0
	world.camera.initialized = false
	world.camera.make_current()
	await settle(40)
	await _shot("normal-camera-garden",{"view":"productive exterior camera","player":str(world.player.global_position),"camera":str(world.camera.global_transform)})
	await _place_pair(ART.PLAY_POINT+Vector3.UP*.05,NPC_STAGING)
	world.camera.initialized = false
	await settle(30)
	await _shot("normal-camera-court",{"view":"productive exterior camera","player":str(world.player.global_position),"camera":str(world.camera.global_transform)})

func _compact_ui() -> void:
	var leisure = urban.village_leisure
	root.content_scale_size = Vector2i(800,600)
	root.size = Vector2i(800,600)
	await settle(12)
	check(urban.nearest_action().get("target","")==LEISURE.PREFIX+"play","Real dispatch still reaches the court at 800x600")
	check(session.interact(),"Normal interaction opens the compact horseshoe panel")
	await settle(12)
	var panel: Control = leisure.ui.get_node("ThrowPanel")
	var viewport: Rect2 = leisure.ui.get_viewport_rect()
	var contained := viewport.encloses(panel.get_global_rect())
	check(contained,"800x600 viewport contains the complete mini-game panel")
	var buttons := panel.find_children("*","Button",true,false)
	check(buttons.size()==2,"Compact panel exposes both throw and exit controls")
	for button in buttons:
		check(button.is_visible_in_tree() and viewport.encloses(button.get_global_rect()) and panel.get_global_rect().encloses(button.get_global_rect()),"Visible compact control stays inside the panel: "+str(button.name))
	await _shot("minigame-800x600",{"view":"real interaction at 800x600","viewport":str(viewport),"panel":str(panel.get_global_rect()),"panel_contained":contained})
	if leisure.ui.active: leisure.ui.cancel_game()
	await settle(3)
	check(not session.modal and not world.player.input_locked,"Exiting the small-window panel releases the player")
	root.content_scale_size = _saved.content_scale_size
	root.size = _saved.window_size
	await settle(3)

func _shot(id: String,row: Dictionary) -> void:
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var result := image.save_png(ProjectSettings.globalize_path(FOLDER+"/"+id+".png"))
	check(result==OK,"Rendered screenshot saved: "+id)
	row["file"] = id+".png"
	row["pixels"] = str(image.get_size())
	row["time_us"] = Time.get_ticks_usec()
	_rows.append(row)

func _restore_capture_state() -> void:
	if session.modal: session.close_menu()
	await _place_pair(_saved.player_transform.origin,NPC_STAGING)
	npc.global_transform = _saved.npc_transform
	npc.velocity = _saved.npc_velocity
	npc.model.teleported()
	npc.set_physics_process(_saved.npc_physics)
	world.player.global_transform = _saved.player_transform
	world.player.controlled_automatically = _saved.player_auto
	world.player.automatic_direction = _saved.player_direction
	world.camera.heading = _saved.camera_heading
	world.camera.target_size = _saved.camera_size
	world.camera.initialized = false
	world.camera.set_process_unhandled_input(_saved.camera_input)
	world.camera.make_current()
	session.weather.time_of_day = _saved.weather_time
	session.weather.weather_state = _saved.weather_state
	session.weather._update()
	session.weather.set_process(_saved.weather_processing)
	world.production.region.set_focus(world.player.global_position)
	review.queue_free()
	await process_frame
