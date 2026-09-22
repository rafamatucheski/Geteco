extends SceneTree
## Captura renderizada (Vulkan, não headless) dos faróis por modelo à noite.
## Rodar com --no-save. Saída em res://evidence/traffic-headlights-0922/.
const OUTPUT := "res://evidence/traffic-headlights-0922/"
const LINEUP := ["sedan_classic", "union_sedan", "aurora_executive", "vertice_midengine", "arctic_jeep", "boxrunner", "bike_sport"]
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
	print("CAPTURE ", label)
func set_hour(hour: float) -> void:
	for node in world.find_children("*", "", true, false):
		if node.get("time_of_day") != null and node.get("weather_state") != null: node.time_of_day = hour
	world.session.state.world_state.time = hour
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var session = world.session
	# Pátio largo e plano ao lado da delegacia: tira as viaturas para a fileira caber.
	var pool = session.police_motor_pool
	pool.restock[0] = 9999.0
	pool.restock[1] = 9999.0
	var origin := Vector3(37, 0, 127)
	world.player.teleport(origin + Vector3(14, .1, 3))
	session.controller.region.set_focus(origin)
	await frames(240)
	for car in pool.cars:
		if is_instance_valid(car): car.queue_free()
	var equipment_script := preload("res://gameplay/VehicleEquipment.gd")
	equipment_script.npc_beam_budget = LINEUP.size()
	for index in LINEUP.size():
		var car = session.controller.spawn_vehicle(LINEUP[index], origin + Vector3(index * 4.3, .12, 0), 0.0)
		if car == null:
			print("SPAWN_FAILED ", LINEUP[index])
			continue
		car.traffic = true # sem rota: fica parado, mas conta como motorista NPC
		car.ensure_equipment(world)
	set_hour(.5)
	await frames(90)
	await shot("01_fileira_dia")
	set_hour(.95)
	await frames(90)
	await shot("02_fileira_noite")
	# Mesma cena sem nenhum facho de NPC, para medir o que o facho acrescenta.
	equipment_script.npc_beam_budget = 0
	await frames(4)
	await shot("02b_fileira_noite_sem_facho")
	equipment_script.npc_beam_budget = 5
	# Trânsito real, sem arranjo: rua em frente à delegacia.
	world.player.teleport(Vector3(67.5, .1, 139))
	session.controller.region.set_focus(world.player.global_position)
	await frames(600)
	await shot("03_transito_noite")
	print("CAPTURE_DONE")
	world.queue_free()
	await process_frame
	quit(0)
