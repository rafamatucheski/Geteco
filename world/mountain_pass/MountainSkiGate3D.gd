extends Node3D

var accent := Color("65b9d1")
var colored_parts: Array[MeshInstance3D] = []

func _ready() -> void:
	var dark := _material(Color("28343b"), 0.72, 0.45)
	var color := _material(accent, 0.68)
	for side in [-1.0, 1.0]:
		var post := _box(Vector3(side * 1.15, 0.95, 0), Vector3(0.10, 1.9, 0.10), dark)
		add_child(post)
		var flag := _box(Vector3(side * 1.15, 1.45, 0), Vector3(0.42, 0.68, 0.055), color)
		colored_parts.append(flag)
		add_child(flag)
	var bar := _box(Vector3(0, 1.88, 0), Vector3(2.4, 0.10, 0.10), color)
	colored_parts.append(bar)
	add_child(bar)

func set_accent(value: Color) -> void:
	accent = value
	for part in colored_parts:
		part.material_override.albedo_color = accent

func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material

func _box(point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = point
	node.material_override = material
	return node

