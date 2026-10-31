extends Node3D
## Só indicação de compra: sem colisor, luz, viewport nem tratador de entrada.
const HOMES := preload("res://data/catalogs/ResidenceCatalog.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
var property_id := ""
var glyph: Node3D
var _world: Node
var _clock := 0.0
var _next_check := 0.0

static func install(facade: Node3D) -> void:
	var data: Dictionary = facade.get_meta("_urban_data",{})
	var id := str(data.get("id",""))
	id = str(preload("res://world/editing/WorldServiceBuildings.gd").PLACES.get(id,id))
	if not HOMES.PROPERTIES.has(id): return
	var marker = load("res://world/places/ResidenceSaleMarker.gd").new()
	marker.name = "ResidenceSaleMarker"
	marker.property_id = id
	facade.add_child(marker)
	var definition: Dictionary = PLACES.get_definition(id)
	# Ao lado do caminho a pé, dentro da interação de compra existente.
	marker.global_position = definition.entry_position + Vector3(1.1,1.55,.55).rotated(Vector3.UP,float(definition.get("editor_rotation",0)))

func _ready() -> void:
	add_to_group("residence_sale_marker")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_world = get_parent()
	while _world != null and not "session" in _world: _world = _world.get_parent()
	glyph = Node3D.new()
	glyph.name = "RotatingDollar"
	add_child(glyph)
	var text := TextMesh.new()
	text.text = "$"
	text.font = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
	text.font_size = 72
	text.pixel_size = .013
	text.depth = .12
	var mesh := MeshInstance3D.new()
	mesh.mesh = text
	mesh.position = -text.get_aabb().get_center()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("55e58b")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	glyph.add_child(mesh)
	visible = false

func _process(delta: float) -> void:
	_clock += delta
	if _clock >= _next_check:
		_next_check = _clock + .2
		visible = false
		if is_instance_valid(_world) and _world.session != null:
			var session = _world.session
			visible = session.ready_for_play and session.state.region_id == "harbor" and session.state.place_id.is_empty() and not session.activities.residence.can_enter(property_id) and _world.player.global_position.distance_squared_to(global_position) < 8100.0
	if not visible or not is_visible_in_tree(): return
	glyph.rotation.y = fmod(_clock * 1.8,TAU)
	glyph.position.y = sin(_clock * 2.5) * .12
