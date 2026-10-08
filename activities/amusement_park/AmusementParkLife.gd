extends Node
## Four bounded native pedestrians. Refresh shares the park's 150 ms residency tick.
const CLOWN := preload("res://activities/amusement_park/ParkClown.gd")
const LAYOUT := preload("res://world/places/amusement_park/AmusementParkLayout.gd")
const ROUTES := [
	[Vector3(34,.08,15),Vector3(25,.08,15),Vector3(23,.08,9),Vector3(31,.08,9),Vector3(34,.08,10)],
	[Vector3(13,.08,20),Vector3(8,.08,20),Vector3(2,.08,18),Vector3(-2,.08,14),Vector3(4,.08,10),Vector3(14,.08,10)],
	[Vector3(25,.08,27),Vector3(24,.08,28),Vector3(26,.08,31),Vector3(28,.08,30),Vector3(27,.08,27)],
	[Vector3(-34,.08,25),Vector3(-25,.08,25),Vector3(-24,.08,28),Vector3(-24,.08,34),Vector3(-34,.08,34)],
]
var session
var actors: Array[Node3D] = []
var _site: Node3D

func configure(owner_session) -> void: session = owner_session

func refresh(site: Node3D) -> void:
	if not is_instance_valid(site) or site != _site:
		clear()
		_site = site
	if not is_instance_valid(site): return
	var outdoors: bool = session.state.region_id == "harbor" and session.state.place_id.is_empty()
	for actor in actors:
		if not is_instance_valid(actor): continue
		actor.visible = outdoors
		actor.process_mode = Node.PROCESS_MODE_PAUSABLE if outdoors else Node.PROCESS_MODE_DISABLED
	if not outdoors or actors.size() >= ROUTES.size(): return
	# Admit one rig per scan, after the park's solids have reached the physics server.
	var index := actors.size()
	var point: Vector3 = site.to_global(ROUTES[index][0])
	if not session.position_clear(point): return
	var actor := CLOWN.new()
	actor.configure({"id":"lume_clown_%d"%index,"position":point,"kind":"park_clown","worker_index":index})
	for local: Vector3 in ROUTES[index]: actor.patrol.append(site.to_global(local))
	session.world.add_child(actor)
	actors.append(actor)

func clear() -> void:
	for actor in actors:
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	_site = null

func _exit_tree() -> void: clear()
