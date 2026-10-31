extends Node3D
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
## Porta de enrolar física da garagem. Só abre para o token de admissão atual da sessão.
signal access_changed(opened: bool)
const GROUP := "digo_vehicle_gate"
const INTERIOR_GROUP := "digo_interior_vehicle_gate"
var interior_gate := false
var _panel: MeshInstance3D
var _ribs: MultiMeshInstance3D
var _barrier: StaticBody3D
var _opened := false

func _ready() -> void:
	add_to_group(INTERIOR_GROUP if interior_gate else GROUP)
	var steel: Material = preload("res://world/desert/DigoWorkshopMaterials.gd").material("steel") if interior_gate else preload("res://world/desert/DesertInteriorFinish.gd").material("steel")
	_panel = MeshInstance3D.new()
	_panel.name = "RollingShutter"
	var panel := BoxMesh.new()
	panel.size = Vector3(5.4,3.3,.16)
	if interior_gate:
		# A porta física não é a silhueta de parede em corte do adaptador.
		var authored := ArrayMesh.new()
		authored.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,MESH_ARRAYS.arrays_of(panel,0))
		_panel.mesh = authored
	else: _panel.mesh = panel
	_panel.material_override = steel
	add_child(_panel)
	_ribs = MultiMeshInstance3D.new()
	var rib := BoxMesh.new()
	rib.size = Vector3(5.32,.035,.045)
	rib.material = steel
	var repeated := MultiMesh.new()
	repeated.transform_format = MultiMesh.TRANSFORM_3D
	repeated.mesh = rib
	repeated.instance_count = 11
	for index in 11: repeated.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(0,.16+float(index)*.3,.105)))
	_ribs.multimesh = repeated
	add_child(_ribs)
	_barrier = StaticBody3D.new()
	_barrier.name = "ClosedShutterCollision"
	_barrier.position.y = 1.65
	_barrier.collision_mask = 0
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.4,3.3,.22)
	collider.shape = box
	_barrier.add_child(collider)
	add_child(_barrier)
	set_vehicle_access(false)

func set_vehicle_access(opened: bool, authorize: Callable = Callable()) -> bool:
	if opened and (not authorize.is_valid() or not bool(authorize.call())): return false
	if not is_instance_valid(_barrier): return false
	_barrier.collision_layer = 0 if opened else 1
	_panel.scale.y = .05 if opened else 1.0
	_panel.position.y = 3.2175 if opened else 1.65
	_ribs.scale.y = .05 if opened else 1.0
	_ribs.position.y = 3.135 if opened else 0.0
	var changed := _opened != opened
	_opened = opened
	if changed: access_changed.emit(opened)
	return true

func is_open() -> bool:
	return _opened
