extends "res://tests/test_vertice_depth.gd"
## Native room geometry and real Actor rigs, final aligned camera, positive visibility controls.
## This fixture proves local rendered depth only; Main lifecycle and frame time are separate checks.
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const NATIVE := preload("res://world/places/NativePlace.gd")
var destination: String = ""
var _completed: bool = false
var _started_ms: int = 0

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("DESERT_HOMES_DEPTH requires a real rendered viewport")
		quit(2)
		return
	_started_ms=Time.get_ticks_msec()
	destination="res://evidence/desert-village/depth-%d"%_started_ms
	var args: PackedStringArray=OS.get_cmdline_user_args()
	for index in args.size():
		if args[index].begins_with("--out-dir="): destination=args[index].trim_prefix("--out-dir=")
		elif args[index]=="--out-dir" and index+1<args.size(): destination=args[index+1]
	var error: Error=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination))
	if error!=OK:
		push_error("Cannot create depth evidence folder: "+destination)
		quit(2)
		return
	create_timer(240.0).timeout.connect(_watchdog)
	viewport=SubViewport.new()
	viewport.size=Vector2i(960,540)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage: Node3D=Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var environment: WorldEnvironment=WorldEnvironment.new()
	var settings: Environment=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("262a30")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("c5cbd0")
	settings.ambient_light_energy=.55
	settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=settings
	stage.add_child(environment)
	var key: DirectionalLight3D=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-48,-25,0)
	key.light_color=Color("f0dfca")
	key.light_energy=.65
	key.shadow_enabled=true
	stage.add_child(key)
	var camera: Camera3D=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=90
	stage.add_child(camera)
	camera.current=true
	var diagnostic: StandardMaterial3D=StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for home_index in 4:
		var definition: Dictionary=HOMES.home_data(HOMES.IDS[home_index])
		var layout: Dictionary=HOMES.specification(home_index)
		var room: NATIVE=NATIVE.new()
		room.definition=definition
		stage.add_child(room)
		camera.size=float(definition.camera_size)
		var target: Vector3=definition.camera_target
		camera.position=target+Vector3(0,18,15)
		camera.look_at(target,Vector3.UP)
		await physics_frame
		await physics_frame
		var cases: Array[Dictionary]=_positions(home_index,layout)
		for player in [true,false]:
			var actor: ACTOR=ACTOR.new()
			actor.is_player=player
			actor.controlled_automatically=true
			actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
			stage.add_child(actor)
			actor.set_physics_process(false)
			for frame in 4: await process_frame
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			var who: String="player" if player else "npc"
			actor.position=definition.spawn
			actor.reset_physics_interpolation()
			var natural: Image=await capture()
			check(natural.save_png(destination.path_join(str(definition.id)+"-"+who+"-natural.png"))==OK,str(definition.id)+" "+who+" natural room evidence saved")
			mask_meshes(actor.visual,diagnostic)
			for setup in cases:
				var id: String=str(definition.id)+"-"+who+"-"+str(setup.id)
				var point: Vector3=setup.point
				actor.position=point
				actor.reset_physics_interpolation()
				check(room.is_floor_clear(point,.32),id+" authored probe is on free floor")
				check(not actor.test_move(actor.global_transform,Vector3.UP*.002),id+" whole actor capsule has clearance")
				room.show()
				var actual: Image=await capture()
				var visible_pixels: int=mask_count(actual)
				check(actual.save_png(destination.path_join(id+".png"))==OK,id+" rendered depth evidence saved")
				# Only architecture is hidden: this is the same actor, camera and pose.
				room.hide()
				var control: Image=await capture()
				var control_pixels: int=mask_count(control)
				check(control.save_png(destination.path_join(id+"-control.png"))==OK,id+" positive control saved")
				room.show()
				var ratio: float=float(visible_pixels)/maxf(float(control_pixels),1.0)
				check(control_pixels>150,id+" unobstructed positive control contains the real actor")
				# Same visibility thresholds as test_vertice_depth, fixed before rendering.
				if setup.expected=="clear":
					check(ratio>.9,id+" actor remains readable in front/beside furniture: "+str(ratio))
				else:
					check(ratio>.05 and ratio<.9,id+" solid occludes lower body while upper body remains visible: "+str(ratio))
				records.append({"home":definition.id,"actor":who,"probe":setup.id,"point":str(point),"expected":setup.expected,
					"visible_pixels":visible_pixels,"control_pixels":control_pixels,"visible_ratio":ratio,"note":setup.get("note","")})
			actor.free()
		room.free()
		await physics_frame
	_completed=true
	_save_report(false)
	print("DESERT_HOMES_DEPTH checks=",checks," failures=",failures," output=",destination)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _positions(index: int,layout: Dictionary) -> Array[Dictionary]:
	var table: Vector3=layout.table
	var bed: Vector3=layout.bed
	var half_width: float=1.1 if index==3 else .925
	# In home 1 the eastern ceiling beam is at x=3.48; probe the western table
	# lane so "clear" measures table ordering rather than intentional beam cover.
	var chair_bypass: float=-.60 if index==0 else .60
	# Oval tops taper at the ends: probe closer to their rear edge, still outside
	# the full physical envelope (.51 m + .32 m capsule radius).
	var rear_distance := -.85 if index in [0,2] else -.92
	# Chairs occupy x +/- .26 at z +/- .98. Offset x=.60 leaves capsule clearance
	# and keeps the actor behind the tabletop silhouette without standing on a chair.
	var result: Array[Dictionary]=[
		{"id":"table-front","point":table+Vector3(chair_bypass,.04,.94),"expected":"clear"},
		{"id":"table-behind","point":table+Vector3(chair_bypass,.04,rear_distance),"expected":"partial"},
		{"id":"table-side","point":table+Vector3(half_width+.58,.04,0),"expected":"clear"},
		{"id":"bed-headboard-behind","point":bed+Vector3(0,.04,-1.70),"expected":"partial",
		 "note":"Bedroom view includes mattress, headboard and native overhead beams; the mask covers their combined depth."},
	]
	if index==2:
		result.append({"id":"bedroom-partition-behind","point":Vector3(1.75,.04,-1.85),"expected":"partial",
			"note":"The low bedroom divider intentionally hides legs while retaining the upper body."})
	elif index==3:
		result.append({"id":"bedroom-partition-behind","point":Vector3(-5,.04,-1.15),"expected":"partial",
			"note":"The low partition in front of the bed intentionally hides legs; the point is outside the bed footprint."})
	return result

func _watchdog() -> void:
	if _completed: return
	failures.append("240s watchdog: capture did not complete")
	_save_report(true)
	push_error("DESERT_HOMES_DEPTH watchdog expired")
	quit(2)

func _save_report(timed_out: bool) -> void:
	var report: FileAccess=FileAccess.open(destination.path_join("results.json"),FileAccess.WRITE)
	if report==null:
		push_error("Cannot write depth report")
		return
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"timed_out":timed_out,
		"seconds":float(Time.get_ticks_msec()-_started_ms)/1000.0,"renderer":RenderingServer.get_current_rendering_method(),
		"camera_offset":"(0,18,15)","resolution":[960,540],"records":records,
		"limitations":["Native room fixture, not full Main gameplay or a performance benchmark.",
			"Natural photos use the fixture's stable ambient/key light plus authored room pendants; Main lighting is verified separately.",
			"Bed probes include structural overhead beams in the same depth buffer; use the paired controls and natural photos for inspection."]},"\t"))
