extends RefCounted
## Visual ownership adapter for the authored passenger train, not its transport
## controller. World-space clipping follows coach, doors, engine and wheels on
## the GPU. There is no CPU update/mesh reconstruction during motion.
const CLIP_SHADER := preload("res://world/places/harbor_buildings/HarborBuildingMovingSightline.gdshader")
var _saved: Array[Dictionary] = []
var _materials: Dictionary = {}
var _projection := Transform3D.IDENTITY
var _cut := AABB()

func configure(scope: Node, projection: Transform3D, cut: AABB) -> void:
	clear()
	_projection = projection
	_cut = cut
	if not is_instance_valid(scope): return
	# RailwayTransit attaches its train directly to ProductionWorld. A bounded
	# entry-time scan of those children avoids searching the whole streamed city.
	for child: Node in scope.get_children():
		if child.get_meta("railway_train",false): _capture_train(child)

func clear() -> void:
	for item: Dictionary in _saved:
		if not is_instance_valid(item.node): continue
		if int(item.surface)<0:
			if item.node.material_override==item.replacement: item.node.material_override = item.original
		elif item.node.get_surface_override_material(int(item.surface))==item.replacement:
			item.node.set_surface_override_material(int(item.surface),item.original)
	_saved.clear()
	_materials.clear()

func capture_added(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion(): return
	if belongs_to_train(node): _capture_geometry(node)

func belongs_to_train(node: Node) -> bool:
	if not node is MeshInstance3D and not node is MultiMeshInstance3D: return false
	var parent := node.get_parent()
	while parent!=null:
		if parent.get_meta("railway_train",false):
			return true
		parent = parent.get_parent()
	return false

func _capture_train(train: Node) -> void:
	for child: Node in train.get_children():
		if child is MeshInstance3D or child is MultiMeshInstance3D: _capture_geometry(child)
		if child.get_child_count()>0: _capture_train(child)

func _capture_geometry(node: GeometryInstance3D) -> void:
	for saved: Dictionary in _saved:
		if saved.node==node: return
	if node.material_override!=null:
		_replace(node,-1,node.material_override,node.material_override)
	elif node is MeshInstance3D and node.mesh!=null:
		for surface: int in node.mesh.get_surface_count():
			_replace(node,surface,node.get_active_material(surface),node.get_surface_override_material(surface))
	elif node is MultiMeshInstance3D and node.multimesh!=null and node.multimesh.mesh!=null:
		# TrainModel's batches each own a single-material primitive mesh.
		if node.multimesh.mesh.get_surface_count()==1:
			_replace(node,-1,node.multimesh.mesh.surface_get_material(0),null)

func _replace(node: GeometryInstance3D, surface: int, source: Material, original: Material) -> void:
	if not source is StandardMaterial3D: return
	var replacement: ShaderMaterial = _materials.get(source)
	if replacement==null:
		replacement = ShaderMaterial.new()
		replacement.shader = CLIP_SHADER
		replacement.render_priority = source.render_priority
		replacement.set_shader_parameter("albedo",source.albedo_color)
		replacement.set_shader_parameter("metallic",source.metallic)
		replacement.set_shader_parameter("roughness",source.roughness)
		replacement.set_shader_parameter("specular",source.metallic_specular)
		replacement.set_shader_parameter("emission",source.emission if source.emission_enabled else Color.BLACK)
		replacement.set_shader_parameter("emission_energy",source.emission_energy_multiplier)
		replacement.set_shader_parameter("building_projection",_projection)
		replacement.set_shader_parameter("building_cut_min",_cut.position)
		replacement.set_shader_parameter("building_cut_max",_cut.end)
		_materials[source] = replacement
	_saved.append({"node":node,"surface":surface,"original":original,"replacement":replacement})
	if surface<0: node.material_override = replacement
	else: node.set_surface_override_material(surface,replacement)

func debug_snapshot() -> Dictionary:
	return {"geometry":_saved.size(),"materials":_materials.size()}
