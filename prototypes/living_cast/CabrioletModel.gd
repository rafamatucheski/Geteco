extends "res://prototypes/living_cast/CoupeDamageModel.gd"

const PREPARED_GEOMETRY := preload("res://prototypes/living_cast/CabrioletPreparedGeometry.scn")
const MATERIAL_KEY_META := &"cabriolet_material_key"


func is_open_top() -> bool:
	return true


func build() -> void:
	# Recreate the authored materials per live car. Geometry is immutable and
	# shared, while paint/lamp damage remains isolated between instances.
	paint = mat("paint", "b83632", 0.25, 0.24)
	mat("rubber", "171b20", 0.0, 0.9)
	mat("trim", "30373d", 0.15, 0.45)
	var glass := mat("glass", "243a47", 0.35, 0.17)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat("alloy", "b5bdc3", 0.72, 0.24)
	mat("headlight", "e6f0ed", 0.15, 0.16, 0.3)
	mat("brake", "cd6133", 0.2, 0.4)
	mat("rotor", "515963", 0.55, 0.55)
	mat("smoked_lens", "293b44", 0.35, 0.16)
	mat("tail", "eb3832", 0.1, 0.25, 0.65)
	mat("upholstery", "292b30", 0.0, 0.9)

	var template := PREPARED_GEOMETRY.instantiate() as Node3D
	assert(template != null)
	set_meta("vehicle_wheel_clearance_signature", int(template.get_meta("vehicle_wheel_clearance_signature", 0)))
	set_meta("cabriolet_prepared_geometry_signature", int(template.get_meta("cabriolet_prepared_geometry_signature", 0)))
	for child in template.get_children():
		_clear_owner(child)
		template.remove_child(child)
		add_child(child)
		_bind_materials(child)
	template.free()


func _bind_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		var material_key := StringName(part.get_meta(MATERIAL_KEY_META, &""))
		assert(not material_key.is_empty() and materials.has(material_key))
		part.material_override = materials[material_key]
	for child in node.get_children():
		_bind_materials(child)


func _clear_owner(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owner(child)
