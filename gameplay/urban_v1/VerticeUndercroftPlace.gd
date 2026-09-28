extends "res://world/places/NativePlace.gd"
## Uses the existing place transition, physical admission and reward/save flow.
const HATCH := Vector3(-364,0,-95.7)
const RETURN := Vector3(-364,0,-94.2)
var pickup_phase := 0.0

static func definition_data() -> Dictionary:
	var weapon := {"id":"vertice_hidden_m4a1","kind":"weapon","item":"m4a1","amount":1,"ammo":90,"local_position":Vector3(0,0,-3)}
	var cash := {"id":"vertice_undercroft_cache","kind":"cash","amount":2500,"local_position":Vector3(3,0,1)}
	return {"id":"vertice_undercroft","original_name":"Vértice","region":"harbor",
		"source_id":"vertice_undercroft","model":"res://gameplay/urban_v1/VerticeUndercroft.gd",
		"exterior_position":HATCH,"entry_position":HATCH,"return_position":RETURN,
		"spawn":Vector3(0,0,3),"exit":Vector3(0,0,4),"size":Vector2(12,10),
		"camera_target":Vector3(0,.7,0),"camera_size":14.5,"variant":0,"service":"secret",
		"reward":weapon,"rewards":[weapon,cash],"npcs":[],"npc_model":"","npc_point":Vector3.ZERO,
		"hidden_access":true,"silent_access":true,"integration_status":"native"}

func _ready() -> void:
	name = definition.id
	model = load(definition.model).new()
	add_child(model)
	for body in model.solids:
		solid_bodies.append(body)
		solid_bounds.append(body.get_meta("bounds"))
	solid_bodies.append(model.floor_body)
	model.set_cutaway(true)
	interaction_points["service"] = spawn_position
	_install_reward()
	for point in reward_points:
		if point.reward.kind != "weapon": continue
		var ring := MeshInstance3D.new()
		ring.name = "PickupRing"
		var torus := TorusMesh.new()
		torus.inner_radius = .48
		torus.outer_radius = .54
		torus.rings = 24
		torus.ring_segments = 8
		ring.mesh = torus
		ring.position.y = .065
		ring.scale.y = .15
		var surface := StandardMaterial3D.new()
		surface.albedo_color = Color("dfa65e")
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = surface
		point.visual.add_child(ring)

func _process(delta: float) -> void:
	if not active: return
	pickup_phase += delta
	for point in reward_points:
		if point.reward.kind != "weapon" or not point.visual.visible: continue
		var weapon: Node3D = point.visual.get_child(0)
		weapon.position.y = .8+sin(pickup_phase*2)*.08
		weapon.rotation.y = pickup_phase*.35

func set_active(value: bool) -> void:
	super.set_active(value)
	if is_instance_valid(model): model.set_active(value)
