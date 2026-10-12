extends SceneTree
const TERMINAL = preload("res://runtime/terminal/TerminalOperations.gd")
const ACTOR = preload("res://scripts/Actor.gd")
const ZOO = preload("res://world/mountain_detail/zoo/MountainZoo.gd")
const FIXTURE = preload("res://tests/test_mountain_zoo_tickets.gd")
class Coach extends CharacterBody3D:
	var health := 100.0
	var passengers: Array = []
	var state := "parked"
	var timer := 100.0
	var doors := 1.0
	var platform := 0
	var boarded := 0
	var alighted := 0
	func set_doors(value: float) -> void: doors = value
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	var ops = TERMINAL.new(); root.add_child(ops); ops.set_physics_process(false)
	var coach := Coach.new(); root.add_child(coach)
	for phase in ["waiting", "alight", "walk_away", "board", "done"]:
		var actor = ACTOR.new()
		var passenger := {"actor":actor,"inside":false,"phase":phase,"seat":0}
		coach.passengers = [passenger]
		actor.free()
		ops.tick_coach(coach, .1)
		ops.set_inside(passenger, true)
		ops.suspend(passenger)
		check(ops.exchange(coach), "Removed %s passenger cannot block exchange" % phase)
		check(passenger.actor == null and not passenger.inside, "Removed passenger reference and occupancy cleared")
	var queued = ACTOR.new(); queued.queue_free()
	var pending := {"actor":queued,"inside":false,"phase":"board","seat":0}
	coach.passengers = [pending]
	check(ops.exchange(coach), "Queued removal cannot board")
	check(coach.boarded == 0 and coach.alighted == 0, "Missing passengers never count as exchanges")
	var survivor_actor = ACTOR.new(); root.add_child(survivor_actor)
	survivor_actor.teleport(coach.global_position + Vector3(1.4,.12,-2.18))
	var live := {"actor":survivor_actor,"inside":false,"phase":"board","seat":1}
	coach.passengers.append(live)
	ops.exchange(coach)
	check(coach.boarded == 1 and live.inside and not survivor_actor.visible, "Surviving passenger boards after missing passenger")
	check(ops.exchange(coach), "Exchange finishes after surviving passenger boards")
	ops.suspend(live); ops.set_inside(live, false)
	check(survivor_actor.visible and survivor_actor.collision_layer == 2, "Surviving passenger resumes outside after suspension")
	survivor_actor.free()
	coach.free(); ops.free()
	var session = FIXTURE.TestSession.new(); root.add_child(session); root.add_child(session.world)
	session.world.add_child(session.world.gameplay); session.world.add_child(session.world.driving)
	session.world.player.is_player = true; session.world.add_child(session.world.player)
	session.world.player.set_physics_process(false)
	var zoo = ZOO.new(); zoo.position = ZOO.CENTER; root.add_child(zoo); zoo.session = session; zoo.set_process(false)
	session.world.player.teleport(ZOO.CENTER + Vector3(-5,.08,24))
	var admission = zoo.admission; admission.set_physics_process(false)
	admission._physics_process(.1)
	for i in 4: admission._spawn_visitor(i)
	var victim: Dictionary = admission.visitors[0]
	victim.phase = "pay"; victim.wait = 0; victim.note.show()
	victim.actor.free()
	admission._physics_process(.1)
	check(victim.actor == null and victim.phase == "done", "Freed visitor removed from admission work")
	check(admission.npc_sales == 0, "Removed paying visitor cannot create revenue")
	var survivor: Dictionary = admission.visitors[1]
	survivor.actor.teleport(zoo.to_global(Vector3(-3.2,.06,24)))
	admission._physics_process(.1)
	check(survivor.phase == "pay", "Surviving queue advances after removed visitor")
	admission._physics_process(2.0)
	check(admission.npc_sales == 1 and survivor.paid, "Surviving visitor still pays normally")
	admission.visitors[2].actor.queue_free()
	admission._physics_process(.1)
	check(admission.visitors[2].actor == null, "Pending deletion excluded before frame flush")
	check(admission.visitors.size() == 4, "Removal does not respawn an attacked visitor")
	session.world.player.teleport(ZOO.CENTER + Vector3(100,0,100)); admission._physics_process(.1)
	check(admission.visitors.is_empty(), "Distance cleanup tolerates invalid and live actors")
	session.world.player.teleport(ZOO.CENTER + Vector3(-5,.08,24)); admission._physics_process(3.1)
	check(admission._initialized and admission.visitors.size() == 1, "Returning initializes admission again")
	zoo.free(); session.world.free(); session.free()
	await process_frame
	print("TERMINAL_ZOO_REMOVED_ACTORS ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)
