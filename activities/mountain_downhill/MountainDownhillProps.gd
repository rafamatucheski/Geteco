extends Node3D
## Marcações refletivas de corrida funcionais. Os postes da estrada existentes e os faróis reais
## dos Vehicle iluminam o percurso; sem fontes de luz nem laços de atualização extras.
var gates: Array[Node3D] = []
var course

func build(authored_course) -> void:
	course = authored_course
	name = "MountainDownhillCourseMarkers"
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color("67c6ef")
	blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var white := StandardMaterial3D.new()
	white.albedo_color = Color("c9d3d8")
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("222a30")
	for i in 7:
		var grid: Transform3D = course.grid(i)
		var slot := Node3D.new()
		slot.transform = grid
		add_child(slot)
		_box(slot,Vector3(0,-.027,2.9),Vector3(2.9,.018,.15),white)
		for side in [-1.0,1.0]: _box(slot,Vector3(side*1.45,-.027,2.1),Vector3(.12,.018,1.6),white)
	for i in course.gate_offsets.size():
		var gate := Node3D.new()
		gate.name = "Gate%d"%i
		gate.position = course.gate(i)+Vector3.UP*.05
		var forward: Vector3 = course.forward(i)
		gate.rotation.y = atan2(-forward.x,-forward.z)
		add_child(gate)
		gates.append(gate)
		for side in [-1.0,1.0]:
			_box(gate,Vector3(side*4.4,.72,0),Vector3(.14,1.44,.14),blue)
			_box(gate,Vector3(side*4.4,.12,0),Vector3(.3,.24,.3),dark)
		if i == course.gate_offsets.size()-1:
			for cell in 16:
				var row := floori(float(cell)/8.0)
				_box(gate,Vector3(-3.75+float(cell%8)*1.075,.006,float(row)*.3),Vector3(1.075,.012,.3),white if cell%2 == row%2 else dark)

func show_checkpoint(index: int, active: bool) -> void:
	for i in gates.size(): gates[i].visible = active and i >= index and i <= index+1

func _box(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = material
	node.position = point
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
