extends SceneTree
## Palco mínimo: Dante com a mala de mão em ociosidade, andando, correndo, mirando, atirando e
## recarregando a pistola. Guarda imagens em evidence/claude-mala-20260929/<rótulo>/.
## Uso: --script ... -- --no-save --label=antes|depois
const RIG := preload("res://gameplay/WeaponRigPose.gd")
const POSE := preload("res://gameplay/WeaponPoseData.gd")
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")
var actor
var field
var bag
var gun: Node3D
var rig
var camera: Camera3D
var out := ""
var log_lines: Array[String] = []

func _initialize() -> void: run.call_deferred()

func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/" + label + ".png")

func palm(side: String) -> Vector3:
	return actor.combat_palm_position(side)

## Resolve `frames` quadros da pose de combate para um caso e devolve a pose final.
func run_case(name: String, base: String, phase: float, id: String, aiming: bool, reloading: bool, progress: float, moving: bool, sprinting: bool, fire: bool, frames := 50) -> void:
	rig.reset()
	actor._combat_weight = 0.0
	if fire and false: pass
	var pose := {}
	for i in frames:
		if base == "idle": actor._apply_pose(actor._idle_pose)
		else: actor._pose_cycle(base, fposmod(phase + float(i) * 0.0, 1.0), 0)
		if fire and i == frames - 4: rig.attack(id, 3.0)
		var info: Dictionary = actor.combat_rig_info()
		info["bag_carry"] = true
		pose = rig.update(id, 1.0 / 60.0, aiming, reloading, progress, moving, sprinting, phase, info)
		actor.set_combat_weapon_pose(id, pose)
		actor._pose_delta = 1.0 / 60.0
		actor._apply_combat_weapon_pose()
		if is_instance_valid(gun): gun.global_transform = actor.combat_weapon_transform(POSE.GRIPS.get(id, Vector3.ZERO))
		bag._process(1.0 / 60.0)
		await process_frame
	var hand: Vector3 = palm("Left")
	var right: Vector3 = palm("Right")
	log_lines.append("%s left_palm=%s right_palm=%s bag=%s bag_tilt=%s" % [name, hand, right, bag.global_position, bag.rotation])
	for view in ["iso", "side", "front"]:
		match view:
			"iso": camera.position = actor.global_position + Vector3(4.2, 5.6, 4.2); camera.size = 2.3
			"side": camera.position = actor.global_position + Vector3(-4.0, 1.4, 0.2); camera.size = 2.0
			"front": camera.position = actor.global_position + Vector3(0.2, 1.4, -4.0); camera.size = 2.0
		camera.look_at(actor.global_position + Vector3(0, 0.85, 0))
		await shot(name + "-" + view)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var label := "antes"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.split("=")[1]
	out = ProjectSettings.globalize_path("res://evidence/claude-mala-20260929/" + label)
	DirAccess.make_dir_recursive_absolute(out)
	root.get_node("V2Settings").show_fps = false
	root.get_node("V2Settings")._update_fps_overlay()
	root.size = Vector2i(900, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("6f7b80")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dfe6ea")
	environment.ambient_light_energy = .8
	env.environment = environment
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	light.light_energy = 1.5
	stage.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("8c979b")
	floor_mesh.material_override = floor_material
	stage.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current = true
	actor = load("res://scripts/Actor.gd").new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor._apply_pose(actor._idle_pose)
	var economy = load("res://runtime/GameState.gd").new().economy
	economy.enable_grid_inventory()
	economy.grid_equip_bag("handbag")
	field = load("res://systems/inventory/FieldInventoryRuntime.gd").new()
	field.session = {"state": {"economy": economy}, "world": {"player": actor, "driving": {"occupied": false}}}
	stage.add_child(field)
	field.set_process(false)
	field._update_carried()
	for i in 3: await process_frame
	bag = field.carried
	gun = Node3D.new()
	stage.add_child(gun)
	ARSENAL.build(gun, "pistol")
	actor.set_combat_weapon_mount(gun, POSE.GRIPS.get("pistol", Vector3.ZERO))
	rig = RIG.new()
	if "--basis-sweep" in OS.get_cmdline_user_args():
		var candidates := {"id": Basis.IDENTITY, "up+90": Basis(Vector3.UP, PI * .5), "up-90": Basis(Vector3.UP, -PI * .5), "x+90": Basis(Vector3.RIGHT, PI * .5), "x-90": Basis(Vector3.RIGHT, -PI * .5), "z+90": Basis(Vector3.BACK, PI * .5), "z-90": Basis(Vector3.BACK, -PI * .5), "up180": Basis(Vector3.UP, PI)}
		for key in candidates:
			RIG.bag_palm_basis = candidates[key]
			await run_case("sweep-" + key, "idle", 0.0, "pistol", false, false, 0.0, false, false, false)
		quit()
		return
	await run_case("01-idle", "idle", 0.0, "pistol", false, false, 0.0, false, false, false)
	await run_case("02-walk-a", "Walking", 0.10, "pistol", false, false, 0.0, true, false, false)
	await run_case("03-walk-b", "Walking", 0.60, "pistol", false, false, 0.0, true, false, false)
	await run_case("04-run", "Running", 0.30, "pistol", false, false, 0.0, true, true, false)
	await run_case("05-aim", "idle", 0.0, "pistol", true, false, 0.0, false, false, false)
	await run_case("06-aim-recoil", "idle", 0.0, "pistol", true, false, 0.0, false, false, true)
	await run_case("07-aim-walk", "Walking", 0.25, "pistol", true, false, 0.0, true, false, false)
	await run_case("08-reload", "idle", 0.0, "pistol", false, true, 0.45, false, false, false)
	await run_case("09-fists-guard", "idle", 0.0, "fists", true, false, 0.0, false, false, false)
	var file := FileAccess.open(out + "/pose-log.txt", FileAccess.WRITE)
	file.store_string("\n".join(log_lines))
	file.close()
	print("CAPTURE_BAG done ", out)
	stage.free()
	await process_frame
	quit()
