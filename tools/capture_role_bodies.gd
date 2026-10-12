extends SceneTree
## Seis NPCs de função com corpo do Meshy lado a lado (bombeiro, paramédico, funerário, bancário, caixa, residente).
## Uso: "$GODOT" --path . --script res://tools/capture_role_bodies.gd -- --out=res://evidence/npc-meshy/roles
const MODELS := ["res://gameplay/emergency/FirefighterModel.gd", "res://gameplay/emergency/ParamedicModel.gd", "res://gameplay/emergency/MorticianModel.gd",
	"res://assets/regions/source/world/harbor/events/BankClerkModel.gd", "res://runtime/CashierBaseModel.gd", "res://world/places/ServiceResidentModel.gd",
	"res://world/places/NecoModel.gd", "res://gameplay/routines_v1/DockWorkerModel.gd", "res://runtime/BankGuardModel.gd", "res://world/places/sewers/SewerHomelessModel.gd", "res://gameplay/CobraModel.gd", "res://assets/regions/source/world/mountain_pass/WinterResidentModel.gd", "res://assets/maciota/MaciotaModel.gd", "res://world/places/curitiba_cellar/LuisaModel.gd", "res://world/places/amusement_park/ParkClownModel.gd"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var out := "res://evidence/npc-meshy/roles"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1600, 700)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("8fa3ad")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b9c4cc")
	env.environment.ambient_light_energy = 0.9
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	stage.add_child(sun)
	for k in MODELS.size():
		var model := (load(MODELS[k]) as GDScript).new() as Node3D
		model.position = Vector3((k - 7.5) * 1.1, 0, 0)
		stage.add_child(model)
	var camera := Camera3D.new()
	camera.fov = 52.0
	stage.add_child(camera)
	camera.current = true
	for i in 20: await process_frame
	camera.position = Vector3(0, 1.3, 9.0)
	camera.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	for i in 6: await process_frame
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out + "/frente.png"))
	quit(0)
