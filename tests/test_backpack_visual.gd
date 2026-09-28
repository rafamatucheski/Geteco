extends SceneTree
var actor
var field
var economy
var stage: Node3D
var camera: Camera3D
var checks:=0
var failures:=0
const OUT:="res://evidence/backpack-subtle-20260928"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("BACKPACK ","PASS " if ok else "FAIL ",label)
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
	economy=load("res://runtime/GameState.gd").new().economy; economy.enable_grid_inventory(); economy.grid_equip_bag("backpack")
	field=load("res://systems/inventory/FieldInventoryRuntime.gd").new()
	field.session={"state":{"economy":economy},"world":{"player":actor,"driving":{"occupied":false}}}
	stage.add_child(field); field.set_process(false); field._update_carried()
	await settle()
	check(field.carried_mount!=null,"backpack attached to real player skeleton")
	var mount: BoneAttachment3D=field.carried_mount
	var bone: int=mount.bone_idx
	var idle: Transform3D=field.carried.global_transform
	var offset: Transform3D=(actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(bone)).affine_inverse()*idle
	await shot("idle-back")
	for clip in ["Walking","Running","Walk_Backward_with_Gun"]:
		actor._pose_cycle(clip,.27,0)
		await settle()
		var expected: Transform3D=actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(bone)*offset
		check(field.carried.global_transform.is_equal_approx(expected),clip+" follows animated torso without drift")
		check(not field.carried.global_transform.is_equal_approx(idle),clip+" changes backpack pose")
		await shot(clip)
	actor._apply_pose(actor._idle_pose); await settle()
	camera.position=Vector3(3,1.4,.3); camera.look_at(Vector3(0,.95,0)); await shot("side")
	field.carried.set_open(true); await create_timer(.35).timeout
	check(field.carried.get_parent()==actor.visual,"open bag leaves back socket")
	check(field.carried.position.z<0,"opened bag is in front of player")
	await shot("opened")
	field.carried.set_open(false); await create_timer(.35).timeout
	check(field.carried.get_parent()==field.carried.carry_space,"closed bag returns to animated socket")
	check(field.carried.global_transform.is_equal_approx(idle),"closing restores exact original fit")
	field.carried.set_open(true); await create_timer(.3).timeout
	var old_bag: Node3D=field.carried
	economy.grid_drop_bag("harbor","",Vector3.ZERO); field._update_carried(); await settle()
	check(not is_instance_valid(mount) and not is_instance_valid(old_bag),"drop while open frees bag and bone socket")
	economy.grid_equip_bag("handbag"); field._update_carried(); await settle()
	check(field.carried_mount==null and field.carried.kind=="handbag","handbag keeps independent carry pose")
	economy.grid_drop_bag("harbor","",Vector3.ZERO); field._update_carried(); await settle()
	economy.grid_equip_bag("backpack"); field._update_carried(); await settle()
	var count:=0
	for node in actor.skeleton.get_children():
		if node is BoneAttachment3D and node.name=="BackpackAttachment": count+=1
	check(count==1,"equip after drop creates only one bone socket")
	actor.visual.rotation.y=.6; await settle()
	check(field.carried.global_position.distance_to(actor.global_position)<1.5,"turning keeps backpack against player")
	stage.free(); await process_frame
	print("BACKPACK_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
