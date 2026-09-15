extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok: failures += 1

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	root.get_node("WantedManager").set_process(false)
	var life := preload("res://world/harbor/HarborLife.gd").new()
	world.add_child(life)
	var citizen := life.HarborWalker.new()
	citizen.name = "OriginalCitizen"
	citizen.appearance_variant = 12
	citizen.configure_authored_route(PackedVector2Array([Vector2(5000,5000),Vector2(5300,5000)]),"test")
	life.add_child(citizen)
	life.walkers.append(citizen)
	await process_frame
	citizen._die()
	var care := root.get_node("CoronerCare")
	var key: String = care.identity(citizen)
	life._replace_buried_walker()
	check(life.walkers[0] == citizen,"Pending body is not replaced before collection or housekeeping")
	care.mark_unrecovered(citizen)
	life._replace_buried_walker()
	await process_frame
	var successor: Node = life.walkers[0]
	check(successor != citizen and not successor.is_dead,"An unseen vacant ambient slot gets a new living citizen")
	check(care.records()[key].phase == "unrecovered","Population renewal does not change the old death into a burial")
	check(successor.appearance_variant != 12 and care.identity(successor) != key,"Successor has a distinct appearance and medical identity")
	var count := life.walkers.size()
	life._replace_buried_walker()
	check(life.walkers.size()==count,"Population replacement does not grow the population")
	world.queue_free()
	for i in 3: await process_frame
	print("CORONER_POPULATION failures=",failures)
	quit(0 if failures==0 else 1)
