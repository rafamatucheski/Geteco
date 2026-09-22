extends SceneTree
## Esgoto pela sessão integrada: entrar pelo catálogo, andar até o esconderijo,
## pegar a escopeta serrada pelo laço normal do FullSession.
## Uso obrigatório: -- --no-save (sem isso carrega e regrava o progress.json do jogador).
var world
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition: failures.append(label)
func settle(frames := 3) -> void:
	for i in frames: await physics_frame
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args():
		print("FAIL rode com -- --no-save: este teste coleta recompensa e não pode tocar no save real")
		quit(1)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 240:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"mundo integrado inicia")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var state = session.state
	check(world.production.no_save,"fixture não toca no save do jogador")
	check(not state.owns_weapon("sawed_off"),"começa sem a escopeta serrada")
	check(await session.enter_place("harbor_sewer",false),"entra no esgoto")
	var room: Node3D = session.room
	check(room != null and room.definition.id == "harbor_sewer","sala ativa é o esgoto")
	var atmosphere: Node3D = room.model.get_node_or_null("SewerAtmosphere")
	check(atmosphere != null and atmosphere.is_processing(),"atmosfera ativa dentro da sessão")
	check(room.reward_points.size() == 1 and room.reward_points[0].visual.visible,"escopeta visível no esconderijo")
	world.player.teleport(room.reward_points[0].position+Vector3.UP*.05)
	for i in 30: await physics_frame
	check(state.owns_weapon("sawed_off"),"coleta a escopeta serrada ao pisar no esconderijo")
	check(int(state.get_ammo("sawed_off").get("reserve",0)) + int(state.get_ammo("sawed_off").get("magazine",0)) >= 24,"24 cartuchos da serrada concedidos")
	check(state.world_state.rewards.has("harbor_police_sewer_sawed_off"),"recompensa marcada no estado do mundo")
	check(not room.reward_points[0].visual.visible,"escopeta some depois de coletada")
	# Os ratos do lado leste enxergam o Dante pelo sensor de física.
	check(atmosphere._player == world.player,"sensor dos ratos detecta o Dante")
	print("SEWER_SESSION ammo=",state.get_ammo("sawed_off"))
	print("SEWER_SESSION failures=%d" % failures.size())
	quit(1 if not failures.is_empty() else 0)
