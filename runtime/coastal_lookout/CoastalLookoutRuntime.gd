extends Node
## Local scenery and interaction residency; never unlocks or mounts another region.
const SITE = preload("res://world/places/coastal_lookout/CoastalLookout.gd")
const BINOCULARS = preload("res://runtime/coastal_lookout/CoastalBinoculars.gd")
const HORIZON = preload("res://world/desert/DesertHorizon.gd")
const CITY = preload("res://world/places/coastal_lookout/LookoutDistantCity.gd")
const SEA = preload("res://world/places/coastal_lookout/LookoutDistantSea.gd")
const STALL_WORK = preload("res://runtime/StallWorkTrace.gd")
const ENTRY := Vector3(319.5,0.05,-130.5)
var world
var site: Node3D
var binoculars: Node
var horizon: Node3D
var distant_city: Node3D
var clock := 0.0
var _site_template: PackedScene
var _horizon_template: PackedScene
var _city_template: PackedScene
var _city_sources: Array[Dictionary] = []
var _preparing := false
var _reveal_pending := false
var active: bool:
	get: return is_instance_valid(binoculars) and binoculars.active

func configure(owner_world) -> void:
	world = owner_world

func _ready() -> void:
	name = "CoastalLookoutRuntime"
	_prepare_templates()
	_update_residency()

func _prepare_templates() -> void:
	if _site_template != null or _preparing: return
	_preparing = true
	var began := Time.get_ticks_usec()
	# FullSession creates this runtime under its loading curtain, before physics
	# or play is admitted. Build detached templates here, not on first approach.
	# Only resources remain cached: distant collision/light/render nodes are freed.
	# Cede o quadro entre as partes: montado de uma vez levava ~11 s num quadro só (o
	# horizonte do deserto, ~9 s), a janela parava de responder no carregamento
	# (auditoria de 16/10). _update_residency já espera os modelos ficarem prontos.
	var tree := get_tree()
	await tree.process_frame
	if not is_inside_tree():
		_preparing = false
		return
	var t := STALL_WORK.begin()
	var model = SITE.new()
	model.build()
	STALL_WORK.finish("lookout.site.build", t)
	await tree.process_frame
	if not is_inside_tree():
		model.free()
		return
	t = STALL_WORK.begin()
	model.add_child(SEA.build())
	_site_template = _pack_detached(model)
	STALL_WORK.finish("lookout.site.pack", t)
	await tree.process_frame
	if not is_inside_tree(): return
	var relief: Node3D = await HORIZON.build_sliced(tree)
	if not is_inside_tree():
		relief.free()
		return
	t = STALL_WORK.begin()
	relief.name = "LookoutDesertHorizon"
	_horizon_template = _pack_detached(relief)
	STALL_WORK.finish("lookout.pack_horizon", t)
	await tree.process_frame
	if not is_inside_tree(): return
	t = STALL_WORK.begin()
	var city = CITY.new()
	city.build(world.production)
	_city_sources.assign(city.source_buildings)
	_city_template = _pack_detached(city)
	STALL_WORK.finish("lookout.city", t)
	_preparing = false
	set_meta("template_prepare_ms",float(Time.get_ticks_usec()-began)/1000.0)
	set_meta("template_generation_count",int(get_meta("template_generation_count",0))+1)
	_update_residency()

## ProductionWorld segura `ready_for_play` até isto ficar falso: as fatias do preparo não podem cair no jogo.
func is_preparing() -> bool:
	return _preparing and is_inside_tree()

func _pack_detached(model: Node) -> PackedScene:
	_assign_template_owners(model,model)
	var packed := PackedScene.new()
	var result := packed.pack(model)
	model.free()
	if result != OK:
		push_error("Could not prepare coastal scenery template: %s"%error_string(result))
		return null
	return packed

func _assign_template_owners(root_node: Node, parent: Node) -> void:
	for child in parent.get_children():
		child.owner = root_node
		_assign_template_owners(root_node,child)

func _process(delta: float) -> void:
	clock += delta
	if clock < .5: return
	clock = 0
	_update_residency()

func _update_residency() -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player): return
	var point: Vector3 = world.player.global_position
	var distance := Vector2(point.x-ENTRY.x,point.z-ENTRY.z).length()
	var outdoors: bool = world.production.state.region_id == "harbor" and world.production.state.place_id.is_empty()
	if not outdoors or distance > 260.0:
		_release()
		return
	if not is_instance_valid(site) and distance < 190.0:
		if _site_template == null or _horizon_template == null or _city_template == null: return
		var began := Time.get_ticks_usec()
		site = _site_template.instantiate()
		# PackedScene deliberately stores geometry/resources, not script-private
		# generator state. Hydrate only the live handles required by this site.
		site._built = true
		site._head = site.get_node("BinocularHead")
		site._lighthouse_sightline = null
		world.add_child(site)
		if site.has_method("configure_lighthouse_player"): site.configure_lighthouse_player(world.player)
		horizon = _horizon_template.instantiate()
		world.add_child(horizon)
		distant_city = _city_template.instantiate()
		distant_city.restore_prebuilt(_city_sources)
		world.add_child(distant_city)
		binoculars = BINOCULARS.new()
		binoculars.configure(world,site)
		add_child(binoculars)
		set_meta("last_residency_install_ms",float(Time.get_ticks_usec()-began)/1000.0)
		set_meta("residency_install_count",int(get_meta("residency_install_count",0))+1)
		# Escondido no 1º meio segundo (22/10, 3ª rodada): a 190 m o mirante entra com shaders próprios
		# (arrebentação, farol, mirante) e o 1º desenho compilava 7 pipelines `surface` num quadro de 36 ms
		# (sonda de pipelines, estresse nos sobrados a quente). Escondido, o motor compila em segundo plano;
		# aparece no próximo passo da residência, ainda a ~190 m. Desligado por padrão (GETECO_LOOKOUT_HIDDEN_FIRST=1):
		# o quadro menor (36 → 24 ms) só foi visto em rodadas com a sonda ligada, não em medição limpa.
		if OS.get_environment("GETECO_LOOKOUT_HIDDEN_FIRST") == "1":
			site.visible = false
			horizon.visible = false
			distant_city.visible = false
			_reveal_pending = true
			return
	if _reveal_pending:
		_reveal_pending = false
		if is_instance_valid(site): site.visible = true
		if is_instance_valid(distant_city): distant_city.visible = true
	if is_instance_valid(horizon):
		# A resident desert already supplies these exact world-coordinate meshes.
		horizon.visible = not world.production.regions.has("desert")
	if is_instance_valid(distant_city): distant_city.refresh(world.production)

func nearest_action() -> Dictionary:
	return binoculars.nearest_action() if is_instance_valid(binoculars) else {}

func perform(target) -> bool:
	return binoculars.perform(target) if is_instance_valid(binoculars) else false

func handle_input(event: InputEvent) -> bool:
	return binoculars.handle_input(event) if is_instance_valid(binoculars) else false

func leave() -> void:
	if is_instance_valid(binoculars): binoculars.leave()

func _release() -> void:
	leave()
	if is_instance_valid(binoculars): binoculars.queue_free()
	if is_instance_valid(site): site.queue_free()
	if is_instance_valid(horizon): horizon.queue_free()
	if is_instance_valid(distant_city): distant_city.queue_free()
	binoculars = null
	site = null
	horizon = null
	distant_city = null
	_reveal_pending = false

func _exit_tree() -> void:
	_release()
	_site_template = null
	_horizon_template = null
	_city_template = null
	_city_sources.clear()
