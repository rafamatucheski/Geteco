extends Node3D
## Corte de apresentação reversível para estruturas ferroviárias em frente a um prédio
## ocupado. Colisões da ferrovia, movimento do trem e geometria fora das linhas de visão continuam
## com os sistemas originais. O trabalho só acontece em mudanças de andar/streaming.
const ACCESS = preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd")
const CAMERA = preload("res://world/places/harbor_buildings/HarborBuildingCamera.gd")
var _moving := preload("res://world/places/harbor_buildings/HarborBuildingMovingSightline.gd").new()
var _saved: Array[Dictionary] = []
var _foliage_saved: Array[Dictionary] = []
var _derived: Array[Node3D] = []
var _projection := Transform3D.IDENTITY
var _cut := AABB()
var _active := false
var _generation := 0
var _tree_ref: SceneTree

func configure(definition: Dictionary, index: int, rooftop := false) -> void:
	clear()
	if rooftop or index<0 or index>=int(definition.get("floor_count",0)) or not is_inside_tree(): return
	var direction: Vector3 = CAMERA.offset(definition,index)
	if direction.y<=.01: return
	var size: Vector2 = definition.size
	var floor_y: float = float(index)*float(definition.storey_height)
	global_transform = Transform3D(Basis(Vector3.UP,float(definition.get("exterior_rotation",0.0))),definition.exterior_position)
	# Cisalha a geometria elevada sobre o andar ocupado ao longo dos raios da câmera
	# ortográfica. Um corte alinhado aos eixos neste referencial é um prisma inclinado estreito
	# no mundo, em vez de um buraco largo atravessando a ferrovia em volta.
	var slope := Vector2(direction.x,direction.z)/direction.y
	_projection = Transform3D(Basis(Vector3.RIGHT,Vector3(-slope.x,1,-slope.y),Vector3.BACK),Vector3(slope.x*floor_y,0,slope.y*floor_y))
	# Inclui atores em pé nas bordas do fundo/laterais: as cabeças se projetam além
	# da área do andar mesmo quando os pés estão com segurança dentro do cômodo.
	var occupied := AABB(Vector3(-size.x*.5-.35,floor_y,-size.y*.5-.35),Vector3(size.x+.70,2.2,size.y+2.20))
	var projected: AABB = _projection*occupied
	_cut = AABB(Vector3(projected.position.x,floor_y+.10,projected.position.z),Vector3(projected.size.x,80.0,projected.size.z))
	_active = true
	_tree_ref = get_tree()
	_tree_ref.node_added.connect(_node_added)
	for group: Node in _tree_ref.get_nodes_in_group("railway_geometry"):
		# Os lotes da ferrovia são filhos diretos do grupo de chunk/estação.
		for child: Node in group.get_children():
			if child is MultiMeshInstance3D: _capture_batch(child,_generation)
	_capture_local_canopies(str(definition.get("id","")))
	var scope: Node = get_parent()
	if scope!=null and "session" in scope and is_instance_valid(scope.session): scope = scope.session.world
	_moving.configure(scope,_projection*global_transform.affine_inverse(),_cut)

func clear() -> void:
	_active = false
	_generation += 1
	if is_instance_valid(_tree_ref) and _tree_ref.node_added.is_connected(_node_added):
		_tree_ref.node_added.disconnect(_node_added)
	_tree_ref = null
	_moving.clear()
	for item: Dictionary in _saved:
		if is_instance_valid(item.node) and item.node.multimesh==item.replacement:
			item.node.multimesh = item.original
	for item: Dictionary in _foliage_saved:
		if is_instance_valid(item.node) and item.node.mesh==item.replacement:
			item.node.mesh = item.original
			item.node.visible = item.visible
	for node: Node3D in _derived:
		if is_instance_valid(node):
			node.hide()
			node.queue_free()
	_saved.clear()
	_foliage_saved.clear()
	_derived.clear()

func _exit_tree() -> void:
	clear()

func _node_added(node: Node) -> void:
	if not _active: return
	if _moving.belongs_to_train(node):
		_capture_moving.call_deferred(weakref(node),_generation)
	if node is MeshInstance3D and _is_street_canopy(node):
		_capture_streamed.call_deferred(weakref(node),_generation,true)
		return
	if not node is MultiMeshInstance3D or node.has_meta("harbor_sightline_derived"): return
	var parent := node.get_parent()
	if parent!=null and parent.is_in_group("railway_geometry"):
		_capture_streamed.call_deferred(weakref(node),_generation,false)

func _capture_streamed(reference: WeakRef, generation: int, canopy: bool) -> void:
	if not _active or generation!=_generation: return
	var node: Node = reference.get_ref()
	if not is_instance_valid(node): return
	if canopy: _capture_canopy(node,generation)
	else: _capture_batch(node,generation)

func _capture_moving(reference: WeakRef, generation: int) -> void:
	if not _active or generation!=_generation: return
	var node: Node = reference.get_ref()
	if is_instance_valid(node): _moving.capture_added(node)

func _capture_local_canopies(place_id: String) -> void:
	# O HarborProp3D é dono de malhas de copa separadas e de um colisor de tronco. Limita a
	# busca na entrada ao chunk do prédio e aos oito vizinhos carregados.
	for access: Node in _tree_ref.get_nodes_in_group("harbor_building_facade"):
		if str(access.definition.get("id",""))!=place_id or not is_instance_valid(access.facade): continue
		var chunk: Node = access.facade.get_parent()
		var region: Node = chunk.get_parent() if chunk!=null else null
		if region==null or not "chunks" in region: return
		var chunks: Dictionary = region.chunks
		var found := false
		var center := Vector2i.ZERO
		for key: Vector2i in chunks:
			if chunks[key]==chunk:
				center = key
				found = true
				break
		if not found: return
		for x: int in range(-1,2):
			for z: int in range(-1,2):
				var nearby: Node = chunks.get(center+Vector2i(x,z))
				if not is_instance_valid(nearby): continue
				for prop: Node in nearby.get_children():
					if not prop is HarborProp3D or str(prop.definition.get("kind",""))!="tree": continue
					for canopy: Node in prop.get_children():
						if canopy is MeshInstance3D and _is_street_canopy(canopy): _capture_canopy(canopy,_generation)
		return

func _is_street_canopy(node: MeshInstance3D) -> bool:
	var prop := node.get_parent()
	# A árvore autorada tem só uma malha de madeira; os MeshInstances restantes
	# são lóbulos da copa. O Godot pode trocar internamente nomes TreeCanopy duplicados.
	return prop is HarborProp3D and str(prop.definition.get("kind",""))=="tree" and not str(node.name).begins_with("TreeTrunk")

func _capture_canopy(node: MeshInstance3D, generation: int) -> void:
	if not _active or generation!=_generation or not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion() or node.mesh==null: return
	for item: Dictionary in _foliage_saved:
		if item.node==node: return
	var relative: Transform3D = _projection*global_transform.affine_inverse()*node.global_transform
	if not _cut.intersects(relative*node.mesh.get_aabb()): return
	var remaining: Mesh = ACCESS._cut_mesh(node.mesh,relative,[_cut])
	_foliage_saved.append({"node":node,"original":node.mesh,"replacement":remaining,"visible":node.visible})
	node.mesh = remaining
	node.visible = node.visible and remaining!=null

func _capture_batch(batch: MultiMeshInstance3D, generation: int) -> void:
	if not _active or generation!=_generation or not is_instance_valid(batch) or not batch.is_inside_tree() or batch.is_queued_for_deletion(): return
	var source: MultiMesh = batch.multimesh
	if source==null or source.mesh==null or source.transform_format!=MultiMesh.TRANSFORM_3D: return
	for item: Dictionary in _saved:
		if item.node==batch: return
	var frame: Transform3D = _projection*global_transform.affine_inverse()*batch.global_transform
	if not _cut.intersects(frame*source.get_aabb()): return
	var clipped_multimesh: MultiMesh = null
	var visible_count: int = source.instance_count if source.visible_instance_count<0 else mini(source.visible_instance_count,source.instance_count)
	for index: int in visible_count:
		var original: Transform3D = source.get_instance_transform(index)
		if absf(original.basis.determinant())<.000001: continue
		var relative: Transform3D = frame*original
		if not _cut.intersects(relative*source.mesh.get_aabb()): continue
		var remaining: Mesh = ACCESS._cut_mesh(source.mesh,relative,[_cut])
		if clipped_multimesh==null: clipped_multimesh = ACCESS._copy_multimesh(source)
		var hidden := original
		hidden.basis = Basis.from_scale(Vector3.ZERO)
		clipped_multimesh.set_instance_transform(index,hidden)
		if remaining==null: continue
		# Preserva os atributos de instância e também o material e as camadas do lote.
		var one := MultiMesh.new()
		one.transform_format = MultiMesh.TRANSFORM_3D
		one.use_colors = source.use_colors
		one.use_custom_data = source.use_custom_data
		one.mesh = remaining
		one.instance_count = 1
		one.set_instance_transform(0,original)
		if source.use_colors: one.set_instance_color(0,source.get_instance_color(index))
		if source.use_custom_data: one.set_instance_custom_data(0,source.get_instance_custom_data(index))
		var derived := MultiMeshInstance3D.new()
		derived.name = "BuildingSightline%d"%index
		derived.set_meta("harbor_sightline_derived",true)
		derived.multimesh = one
		derived.material_override = batch.material_override
		derived.material_overlay = batch.material_overlay
		derived.cast_shadow = batch.cast_shadow
		derived.layers = batch.layers
		batch.add_child(derived)
		_derived.append(derived)
	if clipped_multimesh!=null:
		_saved.append({"node":batch,"original":source,"replacement":clipped_multimesh})
		batch.multimesh = clipped_multimesh

func debug_snapshot() -> Dictionary:
	return {"active":_active,"batches":_saved.size(),"fragments":_derived.size(),"canopies":_foliage_saved.size(),"generation":_generation,"moving":_moving.debug_snapshot()}
