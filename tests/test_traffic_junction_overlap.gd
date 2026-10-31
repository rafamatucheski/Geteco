extends SceneTree
## Uma segunda reserva não pode liberar uma primeira travessia ainda ocupada pela
## traseira de um Vehicle longo real. Isto é evidência funcional, nunca prova de FPS.
const VEHICLE = preload("res://scripts/Vehicle.gd")
const JUNCTIONS = preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const FIRST := Vector3.ZERO
const SECOND := Vector3(0, 0, -20)
var checks := 0
var failures: Array[String] = []
var world: Node3D
var challenger: CharacterBody3D
var snapshots: Array[Dictionary] = []
var output := "user://traffic-junction-overlap.json"

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func frames(count := 4) -> void:
	for i in count: await physics_frame
	await process_frame

func route() -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0,0,50))
	curve.add_point(FIRST)
	curve.add_point(SECOND)
	curve.add_point(Vector3(0,0,-50))
	curve.set_meta("traffic_open",true)
	return curve

func held(center: Vector3, id: int) -> bool:
	return JUNCTIONS.owners.get(JUNCTIONS.key_of(center),{}).has(id)

func physical(center: Vector3, id: int) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(8,6,8)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = center + Vector3.UP*3
	query.collision_mask = 4
	for hit in world.get_world_3d().direct_space_state.intersect_shape(query):
		if hit.collider.get_instance_id() == id: return true
	return false

func conflicting_admission(center: Vector3) -> bool:
	var key := JUNCTIONS.key_of(center)
	JUNCTIONS.release(key,challenger.get_instance_id())
	var admitted := JUNCTIONS.request(key,challenger.get_instance_id(),Vector3.RIGHT,1.0,.2)
	JUNCTIONS.release(key,challenger.get_instance_id())
	return admitted

func capture(label: String, owner: CharacterBody3D) -> void:
	snapshots.append({"phase":label,"position":str(owner.global_position),"speed":owner.get("speed"),
		"local_token":str(owner.get("_held_junction")),"first_reserved":held(FIRST,owner.get_instance_id()),
		"second_reserved":held(SECOND,owner.get_instance_id()),"first_physical":physical(FIRST,owner.get_instance_id()),
		"second_physical":physical(SECOND,owner.get_instance_id())})

func wait_for_next(owner: CharacterBody3D) -> void:
	# O controlador atual de token único pode alternar primeiro/segundo a cada quadro.
	# Observa a aquisição real, em vez de depender de uma contagem par de quadros.
	for frame in 8:
		await frames(1)
		capture("approach_next_frame_%d" % frame,owner)
		if held(SECOND,owner.get_instance_id()): return

func real_pairs() -> Dictionary:
	# Dados atuais exatos do Harbor e o filtro de ruas do ambiente de produção; sem edição de mapa.
	# A topologia do grafo só identifica locais candidatos. Não afirma que a
	# manobra sintética em rota reta foi dirigida em cada rua listada.
	var before := FileAccess.get_sha256("res://world/editing/world_edits.json")
	var region = preload("res://world/editing/EditableRegion.gd").build_region("harbor")
	region.prepare_data()
	var graph = preload("res://gameplay/NativeTrafficRoutes.gd").new()
	graph.configure(preload("res://gameplay/urban_v1/HarborPortPolicy.gd").ambient_roads(region.roads))
	var neighbours: Dictionary = {}
	for index in graph.vertices.size(): neighbours[index] = {}
	for index in graph.edges:
		for edge in graph.edges[index]:
			neighbours[index][edge.to] = true
			neighbours[edge.to][index] = true
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var junction_count := 0
	for index in neighbours:
		if neighbours[index].size() < 3: continue
		junction_count += 1
		for initial in graph.edges[index]:
			var previous: int = index
			var current: int = initial.to
			var distance: float = graph.vertices[previous].distance_to(graph.vertices[current])
			var visited: Dictionary = {previous:true}
			var roads: Array[String] = [str(initial.id)]
			while distance <= 26.0 and not visited.has(current):
				visited[current] = true
				if neighbours[current].size() >= 3:
					var pair := Vector2i(mini(index,current),maxi(index,current))
					if not seen.has(pair) and distance > .1:
						seen[pair] = true
						rows.append({"from":str(graph.vertices[index]),"to":str(graph.vertices[current]),
							"directed_path_metres":distance,"road_ids":roads.duplicate(),
							"height_difference":absf(graph.vertices[index].y-graph.vertices[current].y),
							"within_synthetic_stop_geometry":distance <= 20.9})
					break
				var next: Dictionary = {}
				for edge in graph.edges[current]:
					if edge.to != previous: next = edge; break
				if next.is_empty(): break
				previous = current
				current = next.to
				distance += graph.vertices[previous].distance_to(graph.vertices[current])
				if str(next.id) not in roads: roads.append(str(next.id))
	rows.sort_custom(func(a,b): return a.directed_path_metres < b.directed_path_metres)
	region.free()
	var after := FileAccess.get_sha256("res://world/editing/world_edits.json")
	check(before == after,"current map document remains byte-identical")
	return {"region":"harbor","map_sha256":before,"junctions":junction_count,"pairs":rows,
		"scope":"Consecutive junction topology on production-filtered roads; actual lane routes, signal phases and driven outcomes at these pairs remain unverified."}

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--junction-overlap-output="): output = argument.trim_prefix("--junction-overlap-output=")
	if "--no-save" not in OS.get_cmdline_user_args() or not ClassDB.class_exists(&"CSharpScript"):
		push_error("Requires compiled Godot .NET and --no-save"); quit(2); return
	create_timer(90).timeout.connect(func(): push_error("Junction overlap timeout"); quit(3))
	JUNCTIONS.configure({"vertices":[FIRST,Vector3(30,0,0),Vector3(-30,0,0),Vector3(0,0,50),SECOND,
		Vector3(30,0,-20),Vector3(-30,0,-20),Vector3(0,0,-50)],
		"edges":{0:[{"to":1},{"to":2},{"to":3},{"to":4}],4:[{"to":0},{"to":5},{"to":6},{"to":7}]}})
	check(JUNCTIONS.junctions.size() == 2,"fixture has two distinct four-arm crossings twenty metres apart")
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100,1,160)
	floor_shape.shape = floor_box
	floor_shape.position.y = -.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	challenger = VEHICLE.new()
	challenger.archetype = "union_sedan"
	challenger.position = Vector3(-13,.1,0)
	world.add_child(challenger)
	var owner = VEHICLE.new()
	owner.archetype = "route_city"
	owner.position = Vector3(0,.1,0)
	world.add_child(owner)
	owner.route = route()
	owner.traffic = true
	await frames(8)
	check(owner.shape.shape is BoxShape3D and owner.half_length > 4.8,"actual 9.78m Vehicle uses its catalogue collision hull")
	check(held(FIRST,owner.get_instance_id()),"normal physics acquired the first reservation")
	owner.place(Vector3(0,.1,-7.4),0)
	await wait_for_next(owner)
	capture("next_acquired_with_rear_in_first",owner)
	check(physical(FIRST,owner.get_instance_id()),"independent query sees rear still in the first physical crossing")
	check(held(SECOND,owner.get_instance_id()),"normal physics also acquired the next crossing")
	check(held(FIRST,owner.get_instance_id()),"acquiring next crossing preserves the still-occupied first reservation")
	check(not conflicting_admission(FIRST),"cross traffic cannot enter the first crossing under the vehicle rear")
	owner.place(Vector3(0,.1,-20),0)
	await frames()
	capture("first_clear_second_occupied",owner)
	check(not physical(FIRST,owner.get_instance_id()) and physical(SECOND,owner.get_instance_id()),"only second physical crossing remains occupied")
	check(not held(FIRST,owner.get_instance_id()),"first reservation releases within normal frames, without a nine-second ghost")
	check(held(SECOND,owner.get_instance_id()) and not conflicting_admission(SECOND),"second crossing remains protected while occupied")
	owner.place(Vector3(0,.1,-35),0)
	await frames()
	check(not physical(SECOND,owner.get_instance_id()),"rear has physically cleared both crossings")
	check(not held(FIRST,owner.get_instance_id()) and not held(SECOND,owner.get_instance_id()),"all reservations release promptly after full departure")
	owner.place(Vector3(0,.1,0),0)
	await frames(8)
	owner.place(Vector3(0,.1,-7.4),0)
	await wait_for_next(owner)
	check(held(FIRST,owner.get_instance_id()) and held(SECOND,owner.get_instance_id()),"recovery starts with two real simultaneous reservations")
	await frames(8)
	check(held(FIRST,owner.get_instance_id()) and held(SECOND,owner.get_instance_id()),"continued normal frames do not alternate or drop the two reservations")
	owner.place(Vector3(0,.1,-7.4),0)
	JUNCTIONS.release(JUNCTIONS.key_of(FIRST),owner.get_instance_id())
	await frames(4)
	capture("previous_registry_token_recovered",owner)
	check(physical(FIRST,owner.get_instance_id()),"previous-token recovery still has a physically occupied first crossing")
	check(held(FIRST,owner.get_instance_id()) and held(SECOND,owner.get_instance_id()),"lost previous token is reacquired while preserving the next reservation")
	owner.place(Vector3(0,.1,-7.4),0)
	JUNCTIONS.release(JUNCTIONS.key_of(SECOND),owner.get_instance_id())
	await frames(4)
	capture("current_registry_token_recovered",owner)
	check(held(FIRST,owner.get_instance_id()) and held(SECOND,owner.get_instance_id()),"lost current token is reacquired without erasing the trailing reservation")
	owner.place(Vector3(0,.1,-7.4),0)
	owner.route = route()
	await frames(4)
	check(held(FIRST,owner.get_instance_id()) and held(SECOND,owner.get_instance_id()),"replacement equivalent route preserves its occupied previous crossing")
	# A retained tail must also clear when the normal driver no longer runs.
	owner.traffic = false
	owner.place(Vector3(0,.1,-20),0)
	await frames(4)
	check(not physical(FIRST,owner.get_instance_id()) and physical(SECOND,owner.get_instance_id()),"manual-control cleanup has physically left the first crossing")
	check(not held(FIRST,owner.get_instance_id()),"old tail token clears while traffic driver is disabled")
	owner._release_junction()
	check(not held(FIRST,owner.get_instance_id()) and not held(SECOND,owner.get_instance_id()),"existing explicit reset API releases every reservation immediately")
	owner.traffic = true
	owner.place(Vector3(0,.1,0),0)
	await frames(8)
	owner.place(Vector3(0,.1,-7.4),0)
	await wait_for_next(owner)
	check(held(FIRST,owner.get_instance_id()) and held(SECOND,owner.get_instance_id()),"lifecycle starts with two real simultaneous reservations")
	var id := owner.get_instance_id()
	owner.queue_free()
	await frames()
	check(not is_instance_id_valid(id),"owner was destroyed by scene-tree lifecycle")
	check(not held(FIRST,id) and not held(SECOND,id),"scene exit releases both reservations without pruning or TTL")
	world.queue_free()
	await frames()
	JUNCTIONS.configure(null)
	var inventory := real_pairs()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Could not write overlap evidence"); quit(4); return
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"snapshots":snapshots,"real_pair_inventory":inventory},"\t"))
	print("TRAFFIC_JUNCTION_OVERLAP checks=",checks," failures=",failures.size()," real_pairs=",inventory.pairs.size())
	quit(0 if failures.is_empty() else 1)
