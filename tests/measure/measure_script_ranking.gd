extends SceneTree
## Ranking de custo por script no cenário de caos do guardião (arma, crime, tiros e explosões, 6+
## unidades): cada nó com _physics_process (ou _process, com --process) é chamado daqui, cronometrado e
## somado por arquivo. O adotar muda a ordem de chamada e infla um pouco; use as proporções.
##   godot --path . --script res://tests/measure/measure_script_ranking.gd -- --no-save --skip-arrival [--process]
const MIN_UNITS := 6
var world: Node
var mode_process := false
var adopted: Array[Node] = []
var cost_us: Dictionary = {}
var count: Dictionary = {}
var tick_count := 0
var measuring := false
var next_shot := 0
var next_blast := 0

## Hospedeiro dentro do passo real: o espaço de física só aceita consulta (move_and_slide, test_motion)
## de dentro de _physics_process, não do sinal physics_frame.
class Host extends Node:
	var owner_ref
	func _init() -> void:
		process_physics_priority = -1000
		process_priority = -1000
	func _physics_process(delta: float) -> void:
		if not owner_ref.mode_process: owner_ref.run_adopted(delta)
	func _process(delta: float) -> void:
		if owner_ref.mode_process: owner_ref.run_adopted(delta)

func _initialize() -> void: run.call_deferred()

func adopt() -> void:
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node.get_script() == null or node in adopted: continue
		if mode_process:
			if node.is_processing() and node.has_method("_process"):
				adopted.append(node)
				node.set_process(false)
		elif node.is_physics_processing() and node.has_method("_physics_process"):
			adopted.append(node)
			node.set_physics_process(false)

func run_adopted(delta: float) -> void:
	tick_count += 1
	if world == null: return
	if tick_count % 20 == 1: adopt()
	for i in range(adopted.size() - 1, -1, -1):
		var node := adopted[i]
		if not is_instance_valid(node):
			adopted.remove_at(i)
			continue
		if not node.is_inside_tree() or not node.can_process(): continue
		# Corpo sem espaço de física (suspenso/fora do mundo): o motor também não o chamaria.
		if node is PhysicsBody3D and not PhysicsServer3D.body_get_space((node as PhysicsBody3D).get_rid()).is_valid(): continue
		var began := Time.get_ticks_usec()
		if mode_process: node._process(delta)
		else: node._physics_process(delta)
		if measuring:
			var path: String = (node.get_script() as Script).resource_path
			cost_us[path] = int(cost_us.get(path, 0)) + Time.get_ticks_usec() - began
			count[path] = int(count.get(path, 0)) + 1

func settle(seconds: float, load_on: bool) -> void:
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		elapsed += float(now - previous) / 1000000.0
		previous = now
		if load_on: drive_load()

func drive_load() -> void:
	if world.gameplay.health <= 0 or world.session.modal: return
	var now := Time.get_ticks_usec()
	world.gameplay.health = 100.0
	if now >= next_shot:
		next_shot = now + 200000
		world.gameplay.fire_at(world.player.position + Vector3(8, 0, -2))
		if world.session.state.get_ammo("ak47").magazine == 0: world.gameplay.reload_weapon()
	if next_blast == 0: next_blast = now + 8000000
	if now >= next_blast:
		next_blast = now + 8000000
		world.gameplay.explode(world.player.position + Vector3(8, .1, -2), 4.0, 80.0, world.player, false)

func report(name: String, seconds: float, load_on: bool) -> void:
	cost_us.clear()
	count.clear()
	tick_count = 0
	var frames := 0
	measuring = true
	var elapsed := 0.0
	var previous := Time.get_ticks_usec()
	while elapsed < seconds:
		await process_frame
		var now := Time.get_ticks_usec()
		elapsed += float(now - previous) / 1000000.0
		previous = now
		frames += 1
		if load_on: drive_load()
	measuring = false
	var steps := maxf(1.0, float(tick_count))
	print("=== %s (%s): %d quadros, %.1f FPS; unidades=%d carros=%d pessoas=%d" % [name, "_process" if mode_process else "_physics_process", frames, frames / elapsed, world.dispatch.units.size(), world.production.vehicles.size(), world.people.size()])
	var keys: Array = cost_us.keys()
	keys.sort_custom(func(a, b): return cost_us[a] > cost_us[b])
	var total := 0.0
	for k in keys: total += float(cost_us[k])
	print("  total %.2f ms/chamada-do-motor" % (total / steps / 1000.0))
	for k in keys.slice(0, 22):
		print("  %-62s %6.3f ms  %5.1f nós/vez  %6.1f us/nó" % [str(k).trim_prefix("res://"), float(cost_us[k]) / steps / 1000.0, float(count[k]) / steps, float(cost_us[k]) / float(count[k])])

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or "--no-save" not in args or "--skip-arrival" not in args:
		push_error("exige renderização e --no-save --skip-arrival")
		quit(2)
		return
	mode_process = "--process" in args
	var host := Host.new()
	host.owner_ref = self
	root.add_child(host)
	seed(20260930)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for i in 900:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	world.player.controlled_automatically = true
	world.session.state.grant_weapon("ak47")
	world.session.state.add_ammo("ak47", 600)
	world.session.state.equip_weapon("ak47")
	await settle(10.0, false)
	await report("NORMAL", 12.0, false)
	world.gameplay.register_crime(150, world.player.position)
	var waited := 0.0
	while world.dispatch.units.size() < MIN_UNITS and waited < 60.0:
		await settle(1.0, true)
		waited += 1.0
	await settle(3.0, true)
	await report("CAOS", 20.0, true)
	quit(0)
