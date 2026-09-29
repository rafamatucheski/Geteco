extends SceneTree
var actor
var field
var economy
var stage: Node3D
var camera: Camera3D
var checks:=0
var failures:=0
const OUT:="res://evidence/handbag-hand-20260928"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("HANDBAG ","PASS " if ok else "FAIL ",label)
func settle() -> void:
	for i in 3: await process_frame
func shot(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+label+".png")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# Pose captures are not benchmarks; keep the alpha watermark, omit the
	# uninitialized first-second FPS counter without saving user settings.
	root.get_node("V2Settings").show_fps=false
	root.get_node("V2Settings")._update_fps_overlay()
	stage=Node3D.new(); root.add_child(stage); current_scene=stage
	var env:=WorldEnvironment.new(); var environment:=Environment.new()
	environment.background_mode=Environment.BG_COLOR; environment.background_color=Color("282c30")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color("e5e0d5"); environment.ambient_light_energy=.7
	env.environment=environment; stage.add_child(env)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-40,-35,0); light.light_energy=1.6; stage.add_child(light)
	camera=Camera3D.new(); stage.add_child(camera); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=2.1
	camera.position=Vector3(2,1.8,3); camera.look_at(Vector3(0,.87,0)); camera.current=true
	actor=load("res://scripts/Actor.gd").new(); actor.is_player=true; stage.add_child(actor); actor.set_physics_process(false)
	actor._apply_pose(actor._idle_pose)
	economy=load("res://runtime/GameState.gd").new().economy; economy.enable_grid_inventory(); economy.grid_equip_bag("handbag")
	field=load("res://systems/inventory/FieldInventoryRuntime.gd").new()
	field.session={"state":{"economy":economy},"world":{"player":actor,"driving":{"occupied":false}}}
	stage.add_child(field); field.set_process(false); field._update_carried()
	await settle()
	var bag: Node3D=field.carried
	check(bag!=null and bag.kind=="handbag" and bag.hand_bone>=0,"handbag attached to a real hand bone")
	var palm_height:=0.0
	var previous:=Vector3.INF
	var moved:=false
	for clip in ["Idle","Walking","Running"]:
		if clip=="Idle": actor._apply_pose(actor._idle_pose)
		else: actor._pose_cycle(clip,.27,0)
		await settle()
		var hang: Array=bag._hand_hang()
		var handle_world: Vector3=actor.visual.to_global(bag.position+Vector3(0,bag.HANDLE_HEIGHT,0))
		var palm: Vector3=actor.skeleton.to_global(actor.skeleton.get_bone_global_pose(bag.hand_bone)*Vector3(0,.065,0))
		check(handle_world.distance_to(palm)<.12,clip+": handle stays in the hand ("+str(snappedf(handle_world.distance_to(palm),.001))+")")
		check(bag.position.distance_to(hang[0])<.001,clip+": bag tracks the hand every frame")
		check(bag.global_position.y>actor.global_position.y-.05 and bag.global_position.y<actor.global_position.y+.6,clip+": hangs above the ground, not dragged")
		if previous!=Vector3.INF and not bag.position.is_equal_approx(previous): moved=true
		previous=bag.position
		await shot("handbag-"+clip)
	check(moved,"bag moves with the animated hand")
	camera.position=Vector3(3,1.4,.3); camera.look_at(Vector3(0,.95,0))
	actor._apply_pose(actor._idle_pose); await settle(); await shot("handbag-side")
	camera.position=Vector3(-3,1.4,.3); camera.look_at(Vector3(0,.95,0)); await shot("handbag-side-other")
	camera.position=Vector3(0,1.4,-3); camera.look_at(Vector3(0,.95,0)); await shot("handbag-front")
	bag.set_open(true); await create_timer(.35).timeout
	check(bag.position.z<0,"opened bag is in front of player")
	await shot("handbag-opened")
	bag.set_open(false); await create_timer(.4).timeout; await settle()
	check(bag.position.distance_to(bag._hand_hang()[0])<.01,"closing hands the bag back to the hand")
	stage.free(); await process_frame
	print("HANDBAG_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
