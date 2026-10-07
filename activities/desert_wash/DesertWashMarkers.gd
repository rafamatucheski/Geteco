extends Node3D
const COURSE := preload("res://activities/desert_wash/DesertWashCourse.gd")
var gates: Array[Node3D]=[]
var orange: StandardMaterial3D
var green: StandardMaterial3D
var dark: StandardMaterial3D

func build(height: Callable) -> void:
	orange=_material(Color(.95,.38,.07))
	green=_material(Color(.26,.80,.41))
	dark=_material(Color(.20,.17,.13))
	var cone:=CylinderMesh.new()
	cone.top_radius=.035; cone.bottom_radius=.24; cone.height=.85
	cone.radial_segments=8
	for i in COURSE.GATES:
		var pair:=Node3D.new()
		pair.name="Gate%d"%i
		add_child(pair)
		var side:=COURSE.direction(i).cross(Vector3.UP)
		for sign_value in [-1.0,1.0]:
			var position_value: Vector3=COURSE.gate(i)+side*COURSE.HALF_WIDTH*sign_value
			position_value.y=float(height.call(Vector2(position_value.x,position_value.z)))+.425
			var mesh:=MeshInstance3D.new()
			mesh.mesh=cone
			mesh.material_override=orange
			mesh.position=position_value
			mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pair.add_child(mesh)
		gates.append(pair)
	# Flexible sporting cones intentionally have no solid obstruction.
	show_gate(-1)

func show_gate(current: int) -> void:
	for i in gates.size():
		for mesh in gates[i].get_children():
			mesh.material_override=green if i==current else (dark if current>=0 and i<current else orange)

func _material(color: Color) -> StandardMaterial3D:
	var material:=StandardMaterial3D.new()
	material.albedo_color=color
	material.roughness=1.0
	return material
