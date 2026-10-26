extends Node3D
## Source braziers, streamed only near the actor. No Light3D or viewport added.
const SOURCES = preload("res://runtime/cold/OriginalHeatSources.gd")
const CAMPFIRES := ["logging_camp","summit_camp","smuggler_camp","hermit_camp","mountain_refuge"]
var visuals: Dictionary = {}
var provider_ids: Dictionary = {}
var elapsed := 1.0
## Fontes montadas uma vez e estacionadas (escondidas, sem colisão, sem processo) em vez de liberadas.
## Antes cada entrada no raio de 80 m montava fogo, pedras e colisão no _process: na serra (17/10) a sonda
## por subárvore achou 43-45 ms nesse ponto (ColdSurvival), o último quadro > 33 ms da rota do benchmark.
## As variantes completas são montadas em `prewarm` sob a cortina. GETECO_HEAT_POOL=0 volta ao antigo.
static var pool_enabled := OS.get_environment("GETECO_HEAT_POOL") != "0"
var _parked: Dictionary = {}
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

## Sob a cortina: monta a versão completa de cada fonte e a deixa estacionada.
func prewarm() -> void:
	if not pool_enabled: return
	for source in SOURCES.SOURCES:
		var key := _key(source.id, null)
		if _parked.has(key): continue
		var visual := _build(source.id, null)
		add_child(visual)
		visual.position = SOURCES.to_world(source.point)
		if source.id == "resort_brazier": visual.build("brazier")
		_install_solids(visual, source.id)
		_park(visual, key)

static func _key(id: String, existing: Node3D) -> String:
	if existing == null: return id + "|full"
	return id + "|wrap|" + str(existing.get_meta("native_heat_has_effects",false)) + "|" + str(existing.get_meta("native_heat_has_solids",false))

func _build(id: String, existing: Node3D) -> Node3D:
	var visual: Node3D
	if existing != null:
		# Borrow the streamed source without reparenting or freeing it.
		# This owned wrapper contains only missing effects/collisions.
		visual = Node3D.new()
		visual.set_meta("reuses_native_heat_source",true)
		if not existing.get_meta("native_heat_has_effects",false):
			var flame := preload("res://runtime/cold/HearthEffects.gd").new()
			flame.scale = Vector3.ONE*1.5
			flame.position = existing.get_meta("native_heat_flame_offset",Vector3(0,.15,0))
			visual.add_child(flame)
	elif id == "resort_brazier":
		visual = preload("res://runtime/cold/ResortBrazier.gd").new()
	elif id in CAMPFIRES:
		visual = _campfire()
	else:
		# Original transit brazier materializes V1 heater-only markers explicitly.
		visual = preload("res://runtime/cold/TransitBrazier.gd").new()
	visual.name = id
	return visual

func _park(visual: Node3D, key: String) -> void:
	visual.set_meta("heat_pool_key", key)
	for body: CollisionObject3D in visual.find_children("*","CollisionObject3D",true,false):
		if not body.has_meta("heat_pool_layer"): body.set_meta("heat_pool_layer", body.collision_layer)
		body.collision_layer = 0
	visual.hide()
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	_parked[key] = visual

func _unpark(key: String) -> Node3D:
	var visual: Variant = _parked.get(key)
	_parked.erase(key)
	if not is_instance_valid(visual) or visual.is_queued_for_deletion(): return null
	for body: CollisionObject3D in visual.find_children("*","CollisionObject3D",true,false):
		body.collision_layer = int(body.get_meta("heat_pool_layer", 1))
	visual.process_mode = Node.PROCESS_MODE_INHERIT
	visual.show()
	return visual
func update_sources(delta: float,point: Vector3,enabled: bool,retain_existing: bool = false,radius: float = 80.0) -> void:
	elapsed += delta
	if elapsed<.25: return
	elapsed = 0
	var wanted: Dictionary = {}
	var providers: Array[Node] = get_tree().get_nodes_in_group("native_heat_source")
	if enabled:
		for source in SOURCES.SOURCES:
			var at := SOURCES.to_world(source.point)
			if at.distance_squared_to(point)>radius*radius: continue
			wanted[source.id] = true
			var existing: Node3D
			for provider in providers:
				if not is_instance_valid(provider) or provider.is_queued_for_deletion() or not provider is Node3D: continue
				var declared_id: String = str(provider.get_meta("native_heat_source",""))
				if not declared_id.is_empty() and declared_id != source.id: continue
				if provider.is_visible_in_tree() and provider.global_position.distance_to(at)<1:
					existing = provider
					break
			var provider_id: int = existing.get_instance_id() if existing != null else 0
			if visuals.has(source.id):
				if is_instance_valid(visuals[source.id]) and not visuals[source.id].is_queued_for_deletion() and provider_ids.get(source.id,0) == provider_id: continue
				_discard(source.id)
			var key := _key(source.id, existing)
			var visual: Node3D = _unpark(key) if pool_enabled else null
			if visual == null:
				var began := STALL_WORK.begin()
				visual = _build(source.id, existing)
				add_child(visual)
				visual.global_position = at
				if source.id == "resort_brazier" and existing == null: visual.build("brazier")
				if existing == null or not existing.get_meta("native_heat_has_solids",false): _install_solids(visual,source.id)
				if pool_enabled: visual.set_meta("heat_pool_key", key)
				STALL_WORK.finish_slow("cold.heat_source.build", began, 2000, visual)
			# Colisão religada ou nova: a admissão espera um passo de física antes de confiar nela.
			visual.set_meta("thermal_created_frame",Engine.get_physics_frames())
			visuals[source.id] = visual
			provider_ids[source.id] = provider_id
	if retain_existing: return
	for id in visuals.keys():
		if not wanted.has(id):
			_discard(id)

func _discard(id: String) -> void:
	var visual: Variant = visuals.get(id)
	if pool_enabled and is_instance_valid(visual) and visual.has_meta("heat_pool_key") and not _parked.has(str(visual.get_meta("heat_pool_key"))):
		_park(visual, str(visual.get_meta("heat_pool_key")))
	elif is_instance_valid(visual):
		# Remove owned solids immediately before replacing the wrapper; deferred
		# deletion must not leave overlapping old/new colliders in admission queries.
		for body: CollisionObject3D in visual.find_children("*","CollisionObject3D",true,false):
			body.collision_layer = 0
			body.collision_mask = 0
		visual.hide()
		visual.queue_free()
	visuals.erase(id)
	provider_ids.erase(id)
func _campfire() -> Node3D:
	var node := Node3D.new()
	node.add_child(preload("res://runtime/cold/FireArt.gd").stone_ring())
	node.add_child(preload("res://runtime/cold/FireArt.gd").fuel())
	var flame := preload("res://runtime/cold/HearthEffects.gd").new()
	flame.position.y = .15
	flame.scale = Vector3.ONE*1.5
	node.add_child(flame)
	return node
func _install_solids(visual: Node3D,id: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = .73 if id == "resort_brazier" else .67
	cylinder.height = .85 if id not in CAMPFIRES else .25
	shape.shape = cylinder
	shape.position.y = cylinder.height*.5
	body.add_child(shape)
	visual.add_child(body)
	if id == "resort_brazier":
		for side in [-1,1]:
			var bench := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(.85,1.15,1.6)
			bench.shape = box
			bench.position = Vector3(side*2,.575,0)
			body.add_child(bench)
