extends Node3D
## Wooden freight crate on a pallet with space underneath for the forks.
func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("ad874e")
	wood.roughness = .94
	var frame := wood.duplicate()
	frame.albedo_color = Color("d0ac6b")
	var dark := wood.duplicate()
	dark.albedo_color = Color("735331")
	_box(Vector3(0,.65,0), Vector3(1.25,.9,1.05), wood)
	for z in [-.43, 0, .43]:
		_box(Vector3(0,.06,z), Vector3(1.4,.12,.13), dark)
		_box(Vector3(0,.19,z), Vector3(1.4,.10,.20), frame)
	for x in [-.52,.52]:
		for z in [-.55,.55]:
			_box(Vector3(x,.65,z), Vector3(.12,.95,.06), frame)
		_box(Vector3(x,1.13,0), Vector3(.12,.06,1.15), frame)
	for y in [.3,1.0]:
		for z in [-.55,.55]: _box(Vector3(0,y,z),Vector3(1.3,.1,.06),frame)

func _box(at: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	part.position = at
	add_child(part)
