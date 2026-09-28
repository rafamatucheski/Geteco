@tool
extends RefCounted
## Static editor context for places owned by the session instead of NativeRegion.
## Only the export worker builds these models. The editor reads the baked JSON.
const PATH := "res://addons/geteco_world_editor/session_context.json"
const CONTEXT := preload("res://addons/geteco_world_editor/WorldContextCatalog.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const PREFIX := "context/harbor/session/"
const VERSION := 5

class ForestSnapshot extends "res://gameplay/urban_v1/FreightOutskirts.gd":
	var editor_batches := {}
	func _flush() -> void:
		# Dummy/headless RenderingServer cannot read back MultiMesh transforms/colors.
		# Preserve the actual generator's CPU data before it uploads and clears it.
		editor_batches = _batches.duplicate(true)
		super._flush()

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}

static func upgrade(catalog: Dictionary, supplement: Dictionary, prefer_supplement := false) -> void:
	if not catalog.has("harbor"): return
	var harbor: Dictionary = catalog.harbor
	if not harbor.has("objects"): harbor.objects = {}
	if not harbor.has("context"): harbor.context = {}
	# A shipped/cached editor catalog may predate a new canonical map extension.
	# Read its ground and roads before applying the user's editor document.
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	if source is Dictionary:
		harbor.land = source.get("harbor_land",[]).duplicate(true)
		for road in source.get("harbor_roads",[]):
			if not str(road.id).begins_with("vertice_"): continue
			var points: Array = []
			for point in road.points: points.append([float(point[0])/16.0,float(point[1])/16.0])
			var id := "road/"+str(road.id)
			harbor.objects[id] = {"id":id,"type":"road","points":points,"width":float(road.width)/16.0,"surface":"asphalt"}
	if not supplement.get("context") is Dictionary: return
	var replace := prefer_supplement or int(harbor.get("session_context_version",0))<int(supplement.get("version",0))
	if replace:
		for id in harbor.context.keys():
			if str(id).begins_with(PREFIX): harbor.context.erase(id)
	for id in supplement.context:
		if replace or not harbor.context.has(id): harbor.context[id] = supplement.context[id].duplicate(true)
	harbor.session_context_version = maxi(int(harbor.get("session_context_version",0)),int(supplement.get("version",0)))

static func build(parent: Node) -> Dictionary:
	var rows := {}
	var company = load("res://gameplay/urban_v1/VerticeCompany.gd").new()
	company.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(company)
	_remove_actors(company)
	var company_id := PREFIX+"vertice"
	rows[company_id] = CONTEXT.from_node(company,company_id,"Vértice","cargo_company",company.global_position)
	company.free()
	var outskirts = ForestSnapshot.new()
	outskirts.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(outskirts)
	var parts: Array = []
	_collect_woodland(outskirts,parts,outskirts.editor_batches)
	parts.sort_custom(func(a,b): return float(a[4])<float(b[4]))
	var bounds := Rect2()
	for index in parts.size():
		var part: Array = parts[index]
		var rect := Rect2(part[0],part[1],part[2],part[3])
		bounds = rect if index==0 else bounds.merge(rect)
	var forest_id := PREFIX+"vertice_woodland"
	rows[forest_id] = {"id":forest_id,"type":"context","kind":"woodland","label":"Bosque da Vértice","locked":true,
		"position":[bounds.get_center().x,bounds.get_center().y],"size":[bounds.size.x,bounds.size.y],"parts":parts}
	outskirts.free()
	var village = load("res://gameplay/urban_v1/TruckersVillageVisuals.gd").new()
	village.process_mode = Node.PROCESS_MODE_DISABLED
	parent.add_child(village)
	_remove_actors(village)
	var village_id := PREFIX+"truckers_village"
	var village_parts: Array = []
	_collect_village(village,village_parts)
	# Parked fleet is session-owned in gameplay; export only the same static models.
	for spot in preload("res://gameplay/urban_v1/TruckersVillageFleet.gd").SPOTS:
		var model := preload("res://runtime/FleetCatalog.gd").create(spot[0])
		if model==null: continue
		parent.add_child(model)
		model.global_position=village.ORIGIN+spot[1]
		model.rotation.y=spot[2]
		var paint=preload("res://runtime/VehiclePaint.gd").new()
		paint.bind(model,spot[0])
		paint.apply(Color.html(spot[3]))
		_collect_village(model,village_parts)
		model.free()
	village_parts.sort_custom(func(a,b): return float(a[4])<float(b[4]))
	var village_bounds := Rect2(-418,62,176,88)
	for part in village_parts:
		village_bounds = village_bounds.merge(Rect2(part[0],part[1],part[2],part[3]))
	rows[village_id] = {"id":village_id,"type":"context","kind":"truckers_village","label":"Posto do Tonico","locked":true,
		"position":[village_bounds.get_center().x,village_bounds.get_center().y],"size":[village_bounds.size.x,village_bounds.size.y],"parts":village_parts}
	village.free()
	return {"version":VERSION,"context":rows}

static func _collect_village(node: Node,parts: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		CONTEXT.part(node.mesh,node.global_transform,node.material_override,parts)
	elif node is MultiMeshInstance3D and node.multimesh != null:
		var transforms: Array = node.get_meta("editor_transforms",[])
		var colors: Array = node.get_meta("editor_colors",[])
		for index in transforms.size():
			var material := StandardMaterial3D.new()
			material.albedo_color = colors[index] if index < colors.size() else Color.WHITE
			CONTEXT.part(node.multimesh.mesh,node.global_transform*transforms[index],material,parts)
	for child in node.get_children(): _collect_village(child,parts)

static func _remove_actors(node: Node) -> void:
	for child in node.get_children():
		if child is CharacterBody3D: child.free()
		else: _remove_actors(child)

static func _collect_woodland(node: Node,parts: Array,batches: Dictionary) -> void:
	if node is MultiMeshInstance3D and node.multimesh!=null:
		var mm: MultiMesh = node.multimesh
		var material: Material = node.material_override
		if material==null and mm.mesh!=null: material=mm.mesh.surface_get_material(0)
		var tint: Color = material.albedo_color if material is BaseMaterial3D else Color("596c4c")
		var count := mm.instance_count if mm.visible_instance_count<0 else mini(mm.visible_instance_count,mm.instance_count)
		var batch: Dictionary = batches.get(str(node.name),{})
		for index in count:
			var instance_color: Color = batch.colors[index] if not batch.is_empty() else mm.get_instance_color(index)
			var instance_transform: Transform3D = batch.transforms[index] if not batch.is_empty() else mm.get_instance_transform(index)
			var color: Color = tint*instance_color if mm.use_colors else tint
			_silhouette(mm.mesh,node.global_transform*instance_transform,color,parts)
	elif node is MeshInstance3D and node.mesh!=null:
		CONTEXT.part(node.mesh,node.global_transform,node.material_override,parts)
	for child in node.get_children(): _collect_woodland(child,parts,batches)

static func _silhouette(mesh: Mesh,transform: Transform3D,color: Color,parts: Array) -> void:
	if mesh==null: return
	var points := PackedVector2Array()
	var high := -INF
	for surface in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var world := transform*vertex
			points.append(Vector2(world.x,world.z))
			high = maxf(high,world.y)
	var hull := Geometry2D.convex_hull(points)
	if hull.size()<4: return
	if hull[0].is_equal_approx(hull[-1]): hull.remove_at(hull.size()-1)
	var polygon: Array = []
	var bounds := Rect2(hull[0],Vector2.ZERO)
	for point in hull:
		polygon.append([snappedf(point.x,.01),snappedf(point.y,.01)])
		bounds = bounds.expand(point)
	# One silhouette per instance, instead of exporting every leaf triangle.
	parts.append([snappedf(bounds.position.x,.01),snappedf(bounds.position.y,.01),snappedf(bounds.size.x,.01),snappedf(bounds.size.y,.01),snappedf(high,.01),color.to_html(false),polygon])
