extends Node3D
var manager: Node3D
var source: Node
var intensity := 1.0
var age := 0.0
var tick := 0.0
var flames: MultiMeshInstance3D

func _ready() -> void:
	flames = MultiMeshInstance3D.new()
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	var cone := CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = 0.22
	cone.height = 0.9
	cone.radial_segments = 7
	mesh.mesh = cone
	mesh.instance_count = 7
	flames.multimesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flames.material_override = material
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)

func _physics_process(delta: float) -> void:
	age += delta
	if age > 45: intensity -= delta * 0.1
	if intensity <= 0:
		queue_free()
		return
	for index in 7:
		var angle := float(index) * TAU / 7
		var height := (0.75 + sin(age * 12 + index * 2.3) * 0.2) * minf(1.5, intensity)
		var transform := Transform3D(Basis().scaled(Vector3(1, height, 1)), Vector3(cos(angle) * 0.45, height * 0.4, sin(angle) * 0.45))
		flames.multimesh.set_instance_transform(index, transform)
		flames.multimesh.set_instance_color(index, Color("ff8f20") if index % 2 else Color("f4ce41"))
	tick -= delta
	if tick > 0: return
	tick = 0.5
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = global_position + Vector3.UP * 0.65
	query.collision_mask = 6
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var actor: Node3D = hit.collider
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, actor.global_position + Vector3.UP, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		# Tique de fogo a cada 0,5 s: fonte contínua, denuncia a mesma vítima uma vez por janela (Gameplay._crime_due).
		manager.gameplay._damage(actor, 5 * intensity, source if is_instance_valid(source) else null, true)
