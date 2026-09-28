@tool
extends RefCounted
const PLACES := {"Police":"harbor_police","Clinic":"harbor_hospital","NorthFireStation":"harbor_fire_station","NorthFrontage0":"harbor_bank","NorthFrontage2":"harbor_ammunation","NorthFrontage3":"harbor_clothing","NorthFrontage4":"harbor_fuel","CanalHomesWest":"canal_north"}
static var _disk_stamp := -1
static var _disk_document: Dictionary = {}

static func upgrade(row: Dictionary) -> void:
	if row.get("type","") != "building": return
	var id := str(row.id).trim_prefix("building/")
	if not PLACES.has(id): return
	row.locked = false
	row.service_building = true
	row.service_base = {"position":row.position.duplicate(),"size":row.size.duplicate(),"height":row.height,"model":row.model,"color":row.color}

static func changes() -> Dictionary:
	if Engine.has_meta("geteco_world_edit_document"): return Engine.get_meta("geteco_world_edit_document").get("regions",{}).get("harbor",{})
	var path := "res://world/editing/world_edits.json"
	var stamp := FileAccess.get_modified_time(path)
	if stamp != _disk_stamp:
		_disk_stamp = stamp
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
		_disk_document = parsed if parsed is Dictionary else {}
	return _disk_document.get("regions",{}).get("harbor",{})

static func row_for(place_id: String) -> Dictionary:
	var id: String = PLACES.find_key(place_id) if PLACES.find_key(place_id) != null else ""
	return changes().get("building/"+id,{})

static func scale_for(row: Dictionary) -> Vector3:
	if not row.has("service_base"): return Vector3.ONE
	var base: Dictionary = row.service_base
	return Vector3(float(row.size[0])/float(base.size[0]),float(row.height)/float(base.height),float(row.size[1])/float(base.size[1]))

static func transform_for(row: Dictionary) -> Transform3D:
	if not row.has("service_base"): return Transform3D.IDENTITY
	var base: Dictionary = row.service_base
	var origin := Vector3(base.position[0],0,base.position[1])
	var destination := Vector3(row.position[0],0,row.position[1])
	var basis := Basis(Vector3.UP,deg_to_rad(float(row.rotation)))*Basis.from_scale(scale_for(row))
	return Transform3D(basis,destination-basis*origin)

static func update_definition(definition: Dictionary) -> void:
	var row := row_for(str(definition.id))
	if not row.has("service_base"): return
	definition.editor_base_exterior = definition.exterior_position
	var transform := transform_for(row)
	definition.editor_transform = transform
	definition.editor_rotation = deg_to_rad(float(row.rotation))
	definition.editor_scale = scale_for(row)
	for key in ["exterior_position","entry_position","return_position"]:
		definition[key] = transform*definition[key]

static func apply_art(art: Node3D, row: Dictionary) -> void:
	var stretch := scale_for(row)
	var origin := art.global_transform
	var target := Transform3D(Basis(Vector3.UP,deg_to_rad(float(row.rotation)))*origin.basis,Vector3(row.position[0],origin.origin.y,row.position[1]))
	preload("res://world/editing/WorldPieceShape.gd").apply(art,{"stretch":[stretch.x,stretch.z],"height_stretch":stretch.y,"rigid_pivots":true},origin,target)
	if row.id == "building/Police":
		# CityLook builds the precinct pilasters, canopy and helipad afterwards.
		# Its nominal dimensions must match the already-deformed native shell.
		art.building_size = Vector2(float(row.size[0]), float(row.size[1]))
		art.height = float(row.height)
	if "fire_door_body" in art and is_instance_valid(art.fire_door_body):
		art.fire_door_shape = art.fire_door_body.get_child(0).shape
		art.fire_door_height = 3.8*stretch.y
		art.set_open_amount(art.open_amount)
	if row.get("color","") != row.service_base.get("color",""): _tint(art,Color(row.color),{})

static func _tint(node: Node, color: Color, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		var source: Material = node.get_active_material(0) if node.mesh != null and node.mesh.get_surface_count() > 0 else null
		var named := "Wall" in str(node.name) or "Body" in str(node.name) or "Wing" in str(node.name) or "Facade" in str(node.name)
		var size: Vector3 = node.mesh.get_aabb().size*node.global_basis.get_scale().abs() if node.mesh != null else Vector3.ZERO
		var wall := size.y > 2.0 and maxf(size.x,size.z) > 2.0
		if source is StandardMaterial3D and (named or (wall and source.roughness > .65 and source.metallic < .3 and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)):
			if not materials.has(source):
				var material := source.duplicate() as StandardMaterial3D
				material.albedo_color = color
				materials[source] = material
			node.material_override = materials[source]
	for child in node.get_children(): _tint(child,color,materials)
