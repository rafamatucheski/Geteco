extends Node
## Local scenery and interaction residency; never unlocks or mounts another region.
const SITE = preload("res://world/places/coastal_lookout/CoastalLookout.gd")
const BINOCULARS = preload("res://runtime/coastal_lookout/CoastalBinoculars.gd")
const HORIZON = preload("res://world/desert/DesertHorizon.gd")
const CITY = preload("res://world/places/coastal_lookout/LookoutDistantCity.gd")
const SEA = preload("res://world/places/coastal_lookout/LookoutDistantSea.gd")
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
var active: bool:
	get: return is_instance_valid(binoculars) and binoculars.active

func configure(owner_world) -> void:
	world = owner_world

func _ready() -> void:
	name = "CoastalLookoutRuntime"
	_prepare_templates()
	_update_residency()

func _prepare_templates() -> void:
	if _site_template != null: return
	var began := Time.get_ticks_usec()
	# FullSession creates this runtime under its loading curtain, before physics
	# or play is admitted. Build detached templates here, not on first approach.
	# Only resources remain cached: distant collision/light/render nodes are freed.
	var model = SITE.new()
	model.build()
	model.add_child(SEA.build())
	_site_template = _pack_detached(model)
	var relief: Node3D = HORIZON.build()
	relief.name = "LookoutDesertHorizon"
	_horizon_template = _pack_detached(relief)
	var city = CITY.new()
	city.build(world.production)
	_city_sources.assign(city.source_buildings)
	_city_template = _pack_detached(city)
	set_meta("template_prepare_ms",float(Time.get_ticks_usec()-began)/1000.0)
	set_meta("template_generation_count",int(get_meta("template_generation_count",0))+1)

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

func _exit_tree() -> void:
	_release()
	_site_template = null
	_horizon_template = null
	_city_template = null
	_city_sources.clear()
