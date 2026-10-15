extends Node3D
## A lazy doorway/collision adapter. Original exteriors stay intact until a
## nearby room has been prepared; the same cut volumes serve visuals and solids.
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const RESTAURANT_VENUES := {"CornerDiner":"anchor","PromenadeCafe":"tideline","ServiceCafe":"early_shift"}
var definition: Dictionary
var facade: Node3D
var access_ready := false
var _prepared := false
var _open := false
var _view_key := ""
var _meshes: Array[Dictionary] = []
var _multimeshes: Array[Dictionary] = []
var _labels: Array[Dictionary] = []
var _effects: Array[Dictionary] = []
var _roof_prop_ids := {}
var _original_shapes: Array[Dictionary] = []
var _replacement_body: StaticBody3D
var _door_visual: Node3D
var _scan_clock := 0.0
var _view_floor := -1
var _view_storey := 3.0
var _view_rooftop := false

func _ready() -> void:
	set_process(false)

static func install(art: Node3D, source_id: String) -> Node3D:
	var def := CATALOG.for_source(source_id)
	if def.is_empty() or art == null: return null
	var existing := art.get_node_or_null("BuildingAccess")
	if existing != null: return existing
	var access: Node3D = load("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd").new()
	access.name = "BuildingAccess"
	access.definition = def
	access.facade = art
	art.add_child(access)
	access.global_transform = Transform3D(Basis(Vector3.UP,float(def.exterior_rotation)),def.exterior_position)
	access.set_meta("place_id",def.id)
	access.add_to_group("harbor_building_facade")
	access.call_deferred("_sync_transform")
	return access

func _sync_transform() -> void:
	global_transform = Transform3D(Basis(Vector3.UP,float(definition.exterior_rotation)),definition.exterior_position)

func set_open_amount(value: float) -> void:
	if value <= .01: return
	if not _prepared: _prepare_access()
	if _open: return
	_open = true
	for item in _original_shapes:
		if is_instance_valid(item.node): item.node.set_deferred("disabled",true)
	_replacement_body.collision_layer = 1
	if _door_visual != null: _door_visual.show()
	for item in _multimeshes:
		if is_instance_valid(item.node): item.node.multimesh = item.opened
	for item in _meshes:
		if is_instance_valid(item.node):
			item.node.mesh = item.open_mesh
			item.node.visible = item.visible and item.open_mesh != null
	access_ready = true
	_view_key = ""

func restore_exterior() -> void:
	if not _prepared: return
	for item in _meshes:
		if is_instance_valid(item.node):
			item.node.mesh = item.original
			item.node.visible = item.visible and not item.get("derived",false)
	for item in _multimeshes:
		if is_instance_valid(item.node): item.node.multimesh = item.original
	for item in _original_shapes:
		if is_instance_valid(item.node): item.node.set_deferred("disabled",item.disabled)
	_replacement_body.collision_layer = 0
	if _door_visual != null: _door_visual.hide()
	_hold_painted_doors(false)
	for item in _labels:
		if is_instance_valid(item.node): item.node.visible = item.visible
	for item in _effects:
		if is_instance_valid(item.node): item.node.visible = item.visible
	access_ready = false
	_open = false
	_view_key = ""
	set_process(false)

func set_floor_view(floor_index: int, storey_height: float, rooftop := false) -> void:
	if not _prepared: _prepare_access()
	set_open_amount(1.0)
	# Jogador dentro: a folha pintada da entrada fica aberta até ele sair.
	_hold_painted_doors(true)
	var key := "%d/%s"%[floor_index,str(rooftop)]
	if key == _view_key: return
	_view_key = key
	_view_floor = floor_index
	_view_storey = storey_height
	_view_rooftop = rooftop
	set_process(floor_index>=0 and not rooftop)
	for item in _labels:
		if is_instance_valid(item.node): item.node.visible = item.visible and (rooftop or floor_index<0)
	for item in _effects:
		if is_instance_valid(item.node): item.node.visible = item.visible and (rooftop or floor_index<0)
	var cuts: Array[AABB] = [_door_cut()]
	if floor_index >= 0 and not rooftop:
		# Camera-facing walls and upper volumes cut away together, while their
		# full colliders remain. The active floor supplies the inner wall finish.
		var size: Vector2 = definition.size
		var front_margin := float(definition.get("facade_cut_front",1.2))
		cuts.append(AABB(Vector3(-size.x*.5-1.2,floor_index*storey_height+.78,-size.y*.5-1.2),Vector3(size.x+2.4,500,size.y+1.2+front_margin)))
	for item in _meshes:
		if not is_instance_valid(item.node): continue
		if not item.has("views"): item.views = {}
		if not item.views.has(key):
			if rooftop or floor_index<0: item.views[key] = item.open_mesh
			elif item.get("hide_inside",false): item.views[key] = null
			elif item.get("owned_architecture",false):
				# All wings and projections of this building share its cutaway.
				# A narrow playable parcel must not leave its own forward wing,
				# doorway glass or awning projected over the room.
				var bounds: AABB = item.transform*item.original.get_aabb()
				var owned_cut := AABB(Vector3(bounds.position.x-1.0,floor_index*storey_height+.78,bounds.position.z-1.0),Vector3(bounds.size.x+2.0,500,bounds.size.z+2.0))
				# Setback crowns may sit inside the playable footprint: remove the
				# same cavity as their collider, including the bottom 78cm.
				item.views[key] = _cut_mesh(item.original,item.transform,[_door_cut(),_interior_cut(),owned_cut])
			else: item.views[key] = _cut_mesh(item.original,item.transform,cuts)
		var result: Mesh = item.views[key]
		item.node.mesh = result
		item.node.visible = item.visible and result != null
	if _door_visual != null: _door_visual.visible = floor_index < 1 and not rooftop

func _process(delta: float) -> void:
	_scan_clock -= delta
	if _scan_clock>0 or not _open: return
	_scan_clock = .5
	# City dressing is scheduled after the building record. Capture only newly
	# mounted presentation nodes so late rooftop details cannot float indoors.
	var known := {}
	for item in _meshes:
		if is_instance_valid(item.node): known[item.node.get_instance_id()] = true
	var changed := false
	for node in _presentation_nodes("MeshInstance3D"):
		if is_ancestor_of(node) or known.has(node.get_instance_id()) or node.mesh==null or node.skin!=null or node.is_queued_for_deletion(): continue
		var relative: Transform3D = global_transform.affine_inverse()*node.global_transform
		var owned: bool = _owns_architecture(node) or _belongs_to_native_roof(relative*node.mesh.get_aabb())
		var canopy: bool = _is_venue_canopy(node)
		if not _relevant_visual(relative*node.mesh.get_aabb(),owned or canopy): continue
		_meshes.append({"node":node,"original":node.mesh,"open_mesh":_cut_mesh(node.mesh,relative,[_door_cut()]),"transform":relative,"visible":node.visible,"owned_architecture":owned,"hide_inside":canopy})
		changed = true
	var known_labels := {}
	for item in _labels:
		if is_instance_valid(item.node): known_labels[item.node.get_instance_id()] = true
	for label in _presentation_nodes("Label3D"):
		if not known_labels.has(label.get_instance_id()) and (_owns_architecture(label) or _access_bounds().has_point(to_local(label.global_position))):
			_labels.append({"node":label,"visible":label.visible})
			changed = true
	if _capture_effects(): changed = true
	var batch_count := _multimeshes.size()
	_prepare_multimeshes()
	if _multimeshes.size()!=batch_count:
		for item in _multimeshes: item.node.multimesh = item.opened
		changed = true
	if changed:
		_add_roof_prop_solids()
		_view_key = ""
		set_floor_view(_view_floor,_view_storey,_view_rooftop)

func _door_cut() -> AABB:
	var half_depth: float = definition.size.y*.5
	# Includes the original .85m recessed shop alcove as well as its doorstep.
	# Otherwise the shallow rear wall remains visible across the open threshold.
	var inward := 1.2
	if str(definition.building_kind)=="urban_slab":
		# This model's residential wall sits behind its .14-depth balcony bay.
		inward = maxf(inward,float(definition.size.y)*.14+.6)
	return AABB(Vector3(float(definition.entrance_local.x)-1.10,-.16,half_depth-inward),Vector3(2.20,2.90,3.6+inward))

func _interior_cut() -> AABB:
	var size: Vector2 = definition.size
	var ceiling: float = float(definition.storey_height)*int(definition.floor_count)-.12
	return AABB(Vector3(-size.x*.5+.22,-.16,-size.y*.5+.22),Vector3(size.x-.44,ceiling+.14,size.y-.44))

func _prepare_access() -> void:
	if _prepared: return
	_sync_transform()
	_prepared = true
	var cuts: Array[AABB] = [_interior_cut(),_door_cut()]
	_replacement_body = StaticBody3D.new()
	_replacement_body.name = "OpenedFacadeSolids"
	_replacement_body.collision_layer = 0
	_replacement_body.collision_mask = 0
	for label in _presentation_nodes("Label3D"):
		if _owns_architecture(label) or _access_bounds().has_point(to_local(label.global_position)):
			_labels.append({"node":label,"visible":label.visible})
	_capture_effects()
	# Snapshot before creating adapter-owned meshes and collisions.
	for node in _presentation_nodes("MeshInstance3D"):
		if node.mesh == null or node.skin != null or node.is_queued_for_deletion(): continue
		var relative: Transform3D = global_transform.affine_inverse()*node.global_transform
		var original: Mesh = node.mesh
		var owned: bool = _owns_architecture(node) or _belongs_to_native_roof(relative*original.get_aabb())
		var canopy: bool = _is_venue_canopy(node)
		if not _relevant_visual(relative*original.get_aabb(),owned or canopy): continue
		# Fachada pintada já tem o vão aberto no lugar da porta desenhada; o corte
		# de 2,1 m abria um buraco largo no meio das janelas pintadas.
		var opened: Mesh = original if _painted_part(node) else _cut_mesh(original,relative,[_door_cut()])
		_meshes.append({"node":node,"original":original,"open_mesh":opened,"transform":relative,"visible":node.visible,"owned_architecture":owned,"hide_inside":canopy})
	_prepare_multimeshes()
	for node in facade.find_children("*","CollisionShape3D",true,false):
		if node.shape == null or node.is_queued_for_deletion(): continue
		# A folha pintada da entrada tem colisão própria que gira com ela. Área de
		# detecção não é sólido: desligá-la junto com as paredes deixava a porta
		# pintada sem abrir para sempre depois que a sala era preparada (a 8 m).
		if node.get_parent().has_meta("painted_door_leaf") or node.get_parent() is Area3D: continue
		var relative: Transform3D = global_transform.affine_inverse()*node.global_transform
		if node.shape is BoxShape3D and not _access_bounds().intersects(relative*AABB(-node.shape.size*.5,node.shape.size)): continue
		_original_shapes.append({"node":node,"disabled":node.disabled})
		if node.disabled: continue
		if node.shape is BoxShape3D:
			var source: AABB = relative*AABB(-node.shape.size*.5,node.shape.size)
			var pieces: Array[AABB] = [source]
			for cut in cuts:
				var next: Array[AABB] = []
				for piece in pieces: next.append_array(_subtract_box(piece,cut))
				pieces = next
			for piece in pieces: _add_box_shape(piece)
		elif node.shape is ConcavePolygonShape3D:
			var faces: PackedVector3Array = node.shape.get_faces()
			var remaining := PackedVector3Array()
			for index in range(0,faces.size(),3):
				var polygon: Array = [relative*faces[index],relative*faces[index+1],relative*faces[index+2]]
				var polygons: Array = [polygon]
				for cut in cuts: polygons = _subtract_polygons(polygons,cut)
				for piece in polygons:
					for corner in range(1,piece.size()-1): remaining.append_array(PackedVector3Array([piece[0],piece[corner],piece[corner+1]]))
			if not remaining.is_empty():
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(remaining)
				var collider := CollisionShape3D.new()
				collider.shape = shape
				_replacement_body.add_child(collider)
		else:
			# Non-box authored details retain their exact physical shape.
			var collider := CollisionShape3D.new()
			collider.shape = node.shape
			collider.transform = relative
			_replacement_body.add_child(collider)
	_add_roof_prop_solids()
	add_child(_replacement_body)
	_make_open_door()

func _access_bounds() -> AABB:
	var size: Vector2 = definition.size
	return AABB(Vector3(-size.x*.5-1.2,-.5,-size.y*.5-1.2),Vector3(size.x+2.4,float(definition.roof_height)+12.0,size.y+4.8))

func _owns_architecture(node: Node) -> bool:
	# Some storefront adapters own a whole batched village/meet site. Only
	# a single native building has an unambiguous architectural boundary.
	return facade is UrbanBuildingBase and (node==facade or facade.is_ancestor_of(node))

func _restaurant_venue() -> String:
	return RESTAURANT_VENUES.get(str(definition.get("source_id","")),"")

func _belongs_to_native_roof(bounds: AABB) -> bool:
	if not facade is UrbanBuildingBase or bounds.end.y<float(definition.roof_height)-.30: return false
	# Roof finishes are chunk siblings. The east wing of an L-shaped building
	# extends beyond its playable north wing, but still owns its roof dressing.
	# Associate by the original building footprint, never the sidewalk margin.
	var native := facade as UrbanBuildingBase
	var center := native.to_local(to_global(bounds.get_center()))
	return absf(center.x)<=native.building_size.x*.5+.08 and absf(center.z)<=native.building_size.y*.5+.08

func _is_attached_fire_escape(batch: Node, bounds: AABB) -> bool:
	if not str(batch.name).begins_with("CityLook_fe_"): return false
	var size: Vector2 = definition.size
	# These batches mix several buildings; associate only the platforms and
	# stairs on this facade's front, never another parcel's street furniture.
	return absf(bounds.get_center().x)<size.x*.5+.15 and bounds.end.z>size.y*.5-.2 and bounds.position.z<size.y*.5+1.9 and bounds.position.z>size.y*.5-.4

func _is_venue_canopy(node: Node) -> bool:
	var venue := _restaurant_venue()
	if venue.is_empty(): return false
	var overhead := false
	var ancestor := node
	while ancestor!=null:
		if str(ancestor.name) in ["Parasol","ParasolPole"]: overhead=true
		if ancestor.has_meta("venue_id"): return overhead and str(ancestor.get_meta("venue_id"))==venue
		ancestor = ancestor.get_parent()
	return false

func _relevant_visual(bounds: AABB, owned := false) -> bool:
	if owned: return true
	if not _access_bounds().intersects(bounds): return false
	# Torque batches the facade together with matching materials elsewhere
	# on its lot. Capture that batch, but clip only its bounded storefront.
	if str(definition.get("source_id","")) == "TorqueStore": return true
	var center := bounds.get_center()
	# Street furniture is beside the room, and must remain complete. Elevated
	# attachments (window ACs, pipes, neon) still participate in floor cutaway.
	if bounds.position.y<.35 and (absf(center.x)>definition.size.x*.5+.12 or absf(center.z)>definition.size.y*.5+.12): return false
	return true

func _presentation_nodes(type: String) -> Array[Node]:
	# Chunk dressing is owned by streamed chunks, beside (not below) the
	# building. Restrict the extra search to those known presentation roots;
	# roads, neighboring building architecture and gameplay bodies stay owned.
	var result: Array[Node] = []
	var roots: Array[Node] = [facade]
	var chunk := facade.get_parent()
	if chunk != null:
		for sibling in chunk.get_children():
			var label := str(sibling.name)
			if label.begins_with("CityLook_") or label.begins_with("RoofNeon_") or label.begins_with("Billboard_") or label.begins_with("RoofSteam"):
				roots.append(sibling)
	var venue := _restaurant_venue()
	if not venue.is_empty():
		for terrace in get_tree().get_nodes_in_group("harbor_restaurant_terrace"):
			if str(terrace.get_meta("venue_id",""))!=venue: continue
			for component in ["Parasol","ParasolPole"]:
				var overhead: Node = terrace.get_node_or_null(component)
				if overhead!=null: roots.append(overhead)
	for root_owner in roots:
		if root_owner.is_class(type): result.append(root_owner)
		result.append_array(root_owner.find_children("*",type,true,false))
	return result

func _capture_effects() -> bool:
	var changed := false
	for type in ["CPUParticles3D","GPUParticles3D"]:
		for node in _presentation_nodes(type):
			if not _owns_architecture(node) and not _access_bounds().has_point(to_local(node.global_position)): continue
			var known := false
			for item in _effects:
				if item.node==node: known=true; break
			if known: continue
			_effects.append({"node":node,"visible":node.visible})
			changed = true
	return changed

func _prepare_multimeshes() -> void:
	# The village/meet owners batch their whole sites. Split only instances in
	# this parcel, leaving their neighbors, actors and materials in the batch.
	for batch in _presentation_nodes("MultiMeshInstance3D"):
		if batch.multimesh == null or batch.multimesh.mesh == null: continue
		var captured := false
		for item in _multimeshes:
			if item.node == batch: captured = true; break
		if captured: continue
		var source: MultiMesh = batch.multimesh
		var owned: bool = _owns_architecture(batch)
		var opened: MultiMesh = null
		var frame: Transform3D = global_transform.affine_inverse()*batch.global_transform
		for index in source.instance_count:
			var relative: Transform3D = frame*source.get_instance_transform(index)
			var bounds: AABB = relative*source.mesh.get_aabb()
			var attachment: bool = _is_attached_fire_escape(batch,bounds) or _belongs_to_native_roof(bounds)
			if not _relevant_visual(bounds,owned or attachment): continue
			if opened == null: opened = _copy_multimesh(source)
			var hidden: Transform3D = source.get_instance_transform(index)
			hidden.basis = Basis.from_scale(Vector3.ZERO)
			opened.set_instance_transform(index,hidden)
			var single := MeshInstance3D.new()
			single.name = "ParcelDetail%d"%index
			single.mesh = source.mesh
			single.material_override = preload("res://scripts/camera/ExteriorReveal.gd").source_material(batch.material_override)
			single.cast_shadow = batch.cast_shadow
			single.layers = batch.layers
			single.transform = relative
			single.visible = false
			add_child(single)
			_meshes.append({"node":single,"original":source.mesh,"open_mesh":_cut_mesh(source.mesh,relative,[_door_cut()]),"transform":relative,"visible":batch.visible,"derived":true,"owned_architecture":owned or attachment})
		if opened != null: _multimeshes.append({"node":batch,"original":source,"opened":opened})

static func _copy_multimesh(source: MultiMesh) -> MultiMesh:
	# Resource.duplicate can replay the buffer before instance_count on Godot
	# 4.7.2. Allocate the destination layout first, then copy each instance.
	var copy := MultiMesh.new()
	copy.transform_format = source.transform_format
	copy.use_colors = source.use_colors
	copy.use_custom_data = source.use_custom_data
	copy.mesh = source.mesh
	copy.instance_count = source.instance_count
	copy.visible_instance_count = source.visible_instance_count
	copy.custom_aabb = source.custom_aabb
	for index in source.instance_count:
		copy.set_instance_transform(index,source.get_instance_transform(index))
		if source.use_colors: copy.set_instance_color(index,source.get_instance_color(index))
		if source.use_custom_data: copy.set_instance_custom_data(index,source.get_instance_custom_data(index))
	return copy

func _add_roof_prop_solids() -> void:
	for item in _meshes:
		var key: int = item.node.get_instance_id()
		if _roof_prop_ids.has(key): continue
		_roof_prop_ids[key] = true
		var bounds: AABB = item.transform*item.original.get_aabb()
		var roof_y: float = definition.roof_height
		if bounds.position.y < roof_y-.35 or bounds.end.y < roof_y+.12 or bounds.size.y < .12: continue
		if bounds.size.x < .12 or bounds.size.z < .12: continue
		# Only physical rooftop objects; pitched roof planes are floors/roofscape.
		if bounds.size.x > definition.size.x*.75 or bounds.size.z > definition.size.y*.75: continue
		bounds.size.y = bounds.end.y-roof_y
		bounds.position.y = roof_y
		_add_box_shape(bounds)

func _add_box_shape(bounds: AABB) -> void:
	if minf(bounds.size.x,minf(bounds.size.y,bounds.size.z)) < .003: return
	var shape := BoxShape3D.new()
	shape.size = bounds.size
	var node := CollisionShape3D.new()
	node.shape = shape
	node.position = bounds.get_center()
	_replacement_body.add_child(node)

func _hold_painted_doors(open: bool) -> void:
	if facade == null: return
	for anchor in facade.find_children("Doorway_front*","Node3D",true,false):
		if anchor.has_meta("walk_in") and anchor.has_node("Door"): anchor.get_node("Door").hold(open)

## Peça de PaintedFacadeKit (paredes/telhado pintados, porta própria que abre devagar).
static func _painted_part(node: Node) -> bool:
	var current := node
	while current != null:
		if String(current.name).begins_with("PaintedFacade_"): return true
		current = current.get_parent()
	return false

func _make_open_door() -> void:
	# Sobrado pintado: a folha pintada do kit é a porta de verdade, abre devagar e só
	# ao alcance do braço; a folha de metal fixa aparecia aberta a 8 m de distância.
	if not facade.find_children("PaintedFacade_*","",true,false).is_empty(): return
	_door_visual = Node3D.new()
	_door_visual.name = "OpenDoorLeaf"
	var leaf := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.07,2.45,.95)
	leaf.mesh = mesh
	leaf.position = Vector3(float(definition.entrance_local.x)-1.045,1.225,definition.size.y*.5+.50)
	leaf.material_override = preload("res://world/places/ShopInteriorMaterials.gd").material("metal",Color("485451"))
	_door_visual.add_child(leaf)
	add_child(_door_visual)
	_door_visual.hide()
	_add_box_shape(AABB(leaf.position-mesh.size*.5,mesh.size))

static func _subtract_box(source: AABB, cut: AABB) -> Array[AABB]:
	var result: Array[AABB] = []
	if not source.intersects(cut): return [source]
	var common := source.intersection(cut)
	var lo := source.position
	var hi := source.end
	var a := common.position
	var b := common.end
	for pair in [
		[lo,Vector3(a.x,hi.y,hi.z)], [Vector3(b.x,lo.y,lo.z),hi],
		[Vector3(a.x,lo.y,lo.z),Vector3(b.x,a.y,hi.z)], [Vector3(a.x,b.y,lo.z),Vector3(b.x,hi.y,hi.z)],
		[Vector3(a.x,a.y,lo.z),Vector3(b.x,b.y,a.z)], [Vector3(a.x,a.y,b.z),Vector3(b.x,b.y,hi.z)],
	]:
		var size: Vector3 = pair[1]-pair[0]
		if minf(size.x,minf(size.y,size.z)) > .0001: result.append(AABB(pair[0],size))
	return result

static func _cut_mesh(source: Mesh, relative: Transform3D, cuts: Array[AABB]) -> Mesh:
	var bounds := relative*source.get_aabb()
	var touches := false
	for cut in cuts:
		if cut.encloses(bounds): return null
		if bounds.intersects(cut): touches = true
	if not touches: return source
	var output := ArrayMesh.new()
	var inverse := relative.affine_inverse()
	for surface_index in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var texcoords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var emitted := 0
		for index in range(0,count,3):
			var original_points: Array[Vector3] = []
			var uv_points: Array[Vector2] = []
			var color_points: Array[Color] = []
			for corner in 3:
				var vertex_index := indices[index+corner] if not indices.is_empty() else index+corner
				original_points.append(relative*vertices[vertex_index])
				uv_points.append(texcoords[vertex_index] if vertex_index < texcoords.size() else Vector2.ZERO)
				if not colors.is_empty(): color_points.append(colors[vertex_index])
			var polygons: Array = [original_points]
			for cut in cuts: polygons = _subtract_polygons(polygons,cut)
			for polygon in polygons:
				for corner in range(1,polygon.size()-1):
					for point: Vector3 in [polygon[0],polygon[corner],polygon[corner+1]]:
						tool.set_uv(_triangle_uv(point,original_points,uv_points))
						if not color_points.is_empty():
							var weights := _triangle_weights(point,original_points)
							tool.set_color(color_points[0]*weights.x+color_points[1]*weights.y+color_points[2]*weights.z)
						tool.add_vertex(inverse*point)
						emitted += 1
		if emitted > 0:
			tool.generate_normals()
			tool.set_material(source.surface_get_material(surface_index))
			tool.commit(output)
	return output if output.get_surface_count()>0 else null

static func _triangle_uv(point: Vector3, vertices: Array[Vector3], uv: Array[Vector2]) -> Vector2:
	var weights := _triangle_weights(point,vertices)
	return uv[0]*weights.x+uv[1]*weights.y+uv[2]*weights.z

static func _triangle_weights(point: Vector3, vertices: Array[Vector3]) -> Vector3:
	var edge0 := vertices[1]-vertices[0]
	var edge1 := vertices[2]-vertices[0]
	var delta := point-vertices[0]
	var aa := edge0.dot(edge0)
	var ab := edge0.dot(edge1)
	var bb := edge1.dot(edge1)
	var det := aa*bb-ab*ab
	if absf(det)<.000001: return Vector3(1,0,0)
	var v := (bb*delta.dot(edge0)-ab*delta.dot(edge1))/det
	var w := (aa*delta.dot(edge1)-ab*delta.dot(edge0))/det
	return Vector3(1.0-v-w,v,w)

static func _subtract_polygons(polygons: Array, cut: AABB) -> Array:
	var result: Array = []
	for polygon in polygons:
		var inside: Array = polygon
		for plane in [Vector4(1,0,0,cut.position.x),Vector4(-1,0,0,-cut.end.x),Vector4(0,1,0,cut.position.y),Vector4(0,-1,0,-cut.end.y),Vector4(0,0,1,cut.position.z),Vector4(0,0,-1,-cut.end.z)]:
			if inside.size()<3: break
			var outside := _clip_polygon(inside,plane,false)
			if outside.size()>=3: result.append(outside)
			inside = _clip_polygon(inside,plane,true)
	return result

static func _clip_polygon(polygon: Array, plane: Vector4, positive: bool) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	var normal := Vector3(plane.x,plane.y,plane.z)
	var last: Vector3 = polygon[-1]
	var last_distance := normal.dot(last)-plane.w
	var last_inside := last_distance>=0 if positive else last_distance<0
	for point: Vector3 in polygon:
		var distance := normal.dot(point)-plane.w
		var current_inside := distance>=0 if positive else distance<0
		if current_inside != last_inside:
			result.append(last.lerp(point,last_distance/(last_distance-distance)))
		if current_inside: result.append(point)
		last = point
		last_distance = distance
		last_inside = current_inside
	return result
