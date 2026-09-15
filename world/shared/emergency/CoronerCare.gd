extends Node
## Saved custody ledger. Scene nodes are attachments, never the death record.
signal case_changed(identity: String, phase: String)
const TERMINAL := ["buried", "unrecovered"]
const CUSTODY := ["carrying", "transport", "morgue", "cemetery", "burial", "awaiting_plot"]
var active := {}
var _clock := 0.0
var _scene_id := 0

func records() -> Dictionary:
	return get_node("/root/CampaignState").coroner_cases

func _ready() -> void:
	get_node("/root/CampaignState").campaign_started.connect(func(): active.clear())

func identity(body: Node) -> String:
	return String(body.get_meta("coroner_identity", body.get_meta("medical_identity", ""))) if is_instance_valid(body) else ""

func next_staff_identity() -> String:
	var campaign := get_node("/root/CampaignState")
	campaign.coroner_staff_serial += 1
	return "iml_staff:%d" % campaign.coroner_staff_serial

func register_death(body: Node2D) -> String:
	var key := identity(body)
	if key.is_empty(): return ""
	# An exterior service address must not replace its actual indoor corpse.
	if body.has_method("return_point") and is_instance_valid(body.get("body")):
		body = body.get("body")
	body.set_meta("coroner_identity", key)
	body.set_meta("medical_pending", true)
	if not records().has(key):
		var scene := get_tree().current_scene
		records()[key] = {"phase":"discovered", "name":String(body.get_meta("display_name", body.name)),
			"cause":String(body.get_meta("death_cause", "undetermined")), "scene":scene.scene_file_path if scene else "",
			"x":body.global_position.x, "y":body.global_position.y, "age":0.0, "plot":-1, "identified":body.has_meta("display_name")}
	var interior := body.get_parent()
	while interior and not interior.is_in_group("harbor_interior"): interior = interior.get_parent()
	if interior and get_tree().current_scene:
		records()[key].room_path = String(get_tree().current_scene.get_path_to(interior))
	if not active.has(key): active[key] = {"body":weakref(body), "unit":null, "carrier":null}
	else: active[key].body = weakref(body)
	return key

func restore_actor(body: Node2D) -> bool:
	var key := identity(body)
	if not records().has(key): return false
	register_death(body)
	body.set("is_dead", true)
	body.set("health", 0)
	var phase: String = records()[key].phase
	if phase in TERMINAL or phase in (CUSTODY + ["recovery"]):
		_hide_body(body)
		return true
	body.global_position = Vector2(records()[key].x, records()[key].y)
	if body.has_method("_start_fall"): body._start_fall()
	var fragments: Array = records()[key].get("fragments",[])
	if not fragments.is_empty(): _restore_fragments.call_deferred(weakref(body),fragments)
	return false

func _restore_fragments(reference: WeakRef, fragments: Array) -> void:
	var body: Variant = reference.get_ref()
	if not is_instance_valid(body) or body.has_meta("explosion_remains"): return
	preload("res://guns/combat/ExplosionRemains.gd").spawn(body,body.global_position,null,fragments)

func _hide_body(body: Node2D) -> void:
	body.hide()
	if body is CollisionObject2D:
		body.collision_layer = 0
		body.collision_mask = 0
	for collision in body.find_children("*","CollisionObject2D",true,false):
		collision.collision_layer = 0
		collision.collision_mask = 0
	body.set_physics_process(false)
	if body.has_meta("interior_actor_presentation"):
		var presentation: Node = body.get_meta("interior_actor_presentation")
		if is_instance_valid(presentation) and is_instance_valid(presentation.anchor): presentation.anchor.hide()

func set_phase(key: String, phase: String) -> void:
	if not records().has(key) or records()[key].phase == phase: return
	if records()[key].phase in TERMINAL: return
	records()[key].phase = phase
	records()[key].age = 0.0
	case_changed.emit(key, phase)

func mark_unrecovered(body: Node2D) -> void:
	var key := register_death(body)
	if key.is_empty(): return
	_hide_body(body)
	if body.has_meta("explosion_remains"):
		var remains: Variant = body.get_meta("explosion_remains")
		if is_instance_valid(remains): remains.queue_free()
		body.remove_meta("explosion_remains")
	set_phase(key,"unrecovered")
	active.erase(key)

func assigned(body: Node2D, unit: Node) -> void:
	var key := register_death(body)
	if key.is_empty(): return
	active[key].unit = weakref(unit)
	set_phase(key, "dispatched")

func begin_collection(target: Node2D, worker: Node2D) -> bool:
	var key := identity(target)
	if key.is_empty(): return true # Compatibility for nonresident fixtures.
	if not records().has(key): register_death(target)
	if not records().has(key): return false
	if records()[key].phase in TERMINAL or records()[key].phase in CUSTODY: return false
	var item: Dictionary = active.get(key, {})
	if item.is_empty(): return false
	var carrier: Variant = item.carrier.get_ref() if item.carrier is WeakRef else null
	if is_instance_valid(carrier) and carrier != worker: return false
	item.carrier = weakref(worker)
	item.unit = weakref(worker.hearse)
	set_phase(key, "carrying")
	worker.set_meta("coroner_cargo", key)
	var body: Variant = item.body.get_ref()
	if is_instance_valid(body):
		_hide_body(body)
		body.set_meta("service_complete", true)
		if body.get_meta("coroner_recovery",false): body.queue_free()
		for stain in get_tree().get_nodes_in_group("ground_blood"):
			if int(stain.get_meta("blood_owner_id",0)) == body.get_instance_id():
				get_node("/root/WorldRenewal").watch_transient(stain, 3.0)
	target.set_meta("service_complete", true)
	get_node("/root/NPCMedicalCare").incidents.erase(key)
	get_node("/root/NPCMedicalCare").records().erase(key)
	return true

func board(worker: Node2D, unit: Node2D) -> void:
	var key := String(worker.get_meta("coroner_cargo", ""))
	if key.is_empty() or not records().has(key) or records()[key].phase != "carrying": return
	var cargo: Array = unit.get_meta("coroner_cargo", [])
	if not cargo.has(key): cargo.append(key)
	unit.set_meta("coroner_cargo", cargo)
	active[key].unit = weakref(unit)
	active[key].carrier = null
	records()[key].x = unit.global_position.x
	records()[key].y = unit.global_position.y
	records()[key].erase("room_path")
	set_phase(key, "transport")

func morgue_arrival(unit: Node2D) -> void:
	for key in unit.get_meta("coroner_cargo", []): set_phase(key, "morgue")

func start_burial(unit: Node2D, worker: Node2D) -> bool:
	var cemetery := get_tree().get_first_node_in_group("cemetery")
	if cemetery == null: return false
	for key in unit.get_meta("coroner_cargo", []):
		if not records().has(key) or records()[key].phase == "buried": continue
		var point: Vector2 = cemetery.reserve_plot(key)
		if point == Vector2.INF:
			set_phase(key,"awaiting_plot")
			return false
		worker.burial_position = point
		worker.set_meta("burial_gate", cemetery.get_gate_position())
		worker.set_meta("burial_identity", key)
		set_phase(key, "burial")
		var keeper := get_tree().get_first_node_in_group("cemetery_keeper")
		if keeper and keeper.has_method("request_burial") and keeper.request_burial(key,point):
			worker.set_meta("burial_keeper",weakref(keeper))
		return true
	return false

func bury(worker: Node2D) -> bool:
	var key := String(worker.get_meta("burial_identity", ""))
	if key.is_empty(): return true
	if not records().has(key) or records()[key].phase != "burial": return false
	if worker.global_position.distance_to(worker.burial_position) > 24: return false
	var reference: Variant = worker.get_meta("burial_keeper") if worker.has_meta("burial_keeper") else null
	var keeper: Variant = reference.get_ref() if reference is WeakRef else null
	if is_instance_valid(keeper) and not keeper.is_dead and not keeper.hostile:
		if keeper.burial_work<5.0: return false
		keeper.finish_burial()
	set_phase(key, "buried")
	active.erase(key)
	return true

func has_cargo(unit: Node) -> bool:
	for key in unit.get_meta("coroner_cargo", []):
		if records().has(key) and records()[key].phase != "buried": return true
	return false

func registry_text() -> String:
	var labels := {"discovered":"Aguardando chamado", "dispatched":"Equipe a caminho", "carrying":"Em coleta",
		"transport":"Em transporte ao IML", "morgue":"No IML", "cemetery":"A caminho do cemitério",
		"awaiting_plot":"Aguardando vaga no cemitério", "burial":"Sepultamento em andamento", "buried":"Sepultado", "recovery":"Aguardando recolhimento da carga", "unrecovered":"Não recolhido"}
	var lines := PackedStringArray()
	var keys := records().keys()
	keys.reverse()
	for key in keys.slice(0,32):
		var record: Dictionary = records()[key]
		var victim := String(record.name) if record.get("identified", false) else "Não identificado"
		var plot := " · Sepultura %02d" % (int(record.plot)+1) if int(record.get("plot",-1)) >= 0 else ""
		lines.append("%s — %s%s" % [victim,labels.get(record.phase,record.phase),plot])
	return "Nenhuma ocorrência registrada." if lines.is_empty() else "\n".join(lines)

func _process(delta: float) -> void:
	if get_tree().paused: return
	_clock += delta
	if _clock < 1.0: return
	var elapsed := _clock
	_clock = 0.0
	var scene := get_tree().current_scene
	if scene and scene.get_instance_id() != _scene_id:
		_scene_id = scene.get_instance_id()
		for key in records():
			var saved: Dictionary = records()[key]
			if saved.phase in TERMINAL or saved.scene != scene.scene_file_path: continue
			if not active.has(key): active[key] = {"body":null, "unit":null, "carrier":null}
			var attachment: Variant = active[key].unit
			if saved.phase in CUSTODY and not (attachment is WeakRef and is_instance_valid(attachment.get_ref())): set_phase(key, "recovery")
	for key in active.keys():
		if not records().has(key):
			active.erase(key)
			continue
		var record: Dictionary = records()[key]
		if record.phase in TERMINAL:
			active.erase(key)
			continue
		record.age += elapsed
		var item: Dictionary = active[key]
		var body: Variant = item.body.get_ref() if item.body is WeakRef else null
		if is_instance_valid(body) and record.phase in ["discovered", "dispatched"]:
			record.x = body.global_position.x
			record.y = body.global_position.y
			var remains: Variant = body.get_meta("explosion_remains") if body.has_meta("explosion_remains") else null
			if is_instance_valid(remains): record.fragments = remains.custody_snapshot()
		var unit: Variant = item.unit.get_ref() if item.unit is WeakRef else null
		var carrier: Variant = item.carrier.get_ref() if item.carrier is WeakRef else null
		if record.phase == "carrying" and is_instance_valid(carrier) and not carrier.is_dead:
			record.x = carrier.global_position.x
			record.y = carrier.global_position.y
		elif record.phase in ["transport", "morgue", "cemetery", "burial", "awaiting_plot"] and is_instance_valid(unit) and unit.visible and not unit.is_broken:
			record.x = unit.global_position.x
			record.y = unit.global_position.y
		elif record.phase in CUSTODY:
			var holder: Variant = carrier if record.phase=="carrying" else unit
			if is_instance_valid(holder):
				record.x = holder.global_position.x
				record.y = holder.global_position.y
			if is_instance_valid(unit):
				var cargo: Array = unit.get_meta("coroner_cargo", [])
				cargo.erase(key)
				unit.set_meta("coroner_cargo",cargo)
			set_phase(key, "recovery")
			item.unit = null
			item.carrier = null
		if record.phase == "recovery": _recover_cargo(key)

func _recover_cargo(key: String) -> void:
	var record: Dictionary = records()[key]
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != record.scene: return
	var item: Dictionary = active[key]
	var existing: Variant = item.get("recovery")
	if existing is WeakRef and is_instance_valid(existing.get_ref()): return
	var point := Vector2(record.x, record.y)
	var parent: Node2D = scene
	if record.has("room_path"):
		parent = scene.get_node_or_null(record.room_path)
		if parent == null: return
	var bag := preload("res://world/shared/emergency/CoronerRecoveryBag.gd").new()
	bag.set_meta("coroner_identity", key)
	bag.hide()
	parent.add_child(bag)
	bag.place(point)
	if parent != scene and not bag.configure_room(parent):
		bag.queue_free()
		return
	# The complete visual footprint must fit; never spawn cargo in furniture.
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = CircleShape2D.new()
	query.shape.radius = bag.clearance_radius
	query.collision_mask = 3
	query.exclude = [bag.solid.get_rid()]
	var free := false
	for radius in [0.0, 65.0, 95.0]:
		for side in 8:
			var candidate: Vector2 = point + Vector2.from_angle(side*PI/4.0)*radius
			if parent != scene and parent.has_method("contains_point") and not parent.contains_point(candidate): continue
			query.transform = Transform2D(0, candidate)
			if scene.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
				point = candidate
				free = true
				break
		if free: break
	if not free:
		bag.queue_free()
		return
	bag.place(point)
	bag.show()
	item.recovery = weakref(bag)
	item.body = weakref(bag)
	bag.request_service()
