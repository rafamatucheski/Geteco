extends "res://world/mountain_pass/MountainPineTree.gd"
## O mesmo modelo projetado e a mesma escala dos atores. Oito renders estáticos
## são compartilhados pela floresta inteira, sem um viewport por árvore.
static var _views: Dictionary = {}

func _ready() -> void:
	super._ready()
	var variant := posmod(variant_seed, 4)
	var key := "%s_%d_%d" % [get_parent().get_instance_id(), int(is_snowy), variant]
	var data: Dictionary = _views.get(key, {})
	if data.is_empty() or not is_instance_valid(data.viewport.get_ref()):
		data = _build_shared_view(variant)
		_views[key] = data
	var sprite := Sprite2D.new()
	sprite.texture = data.texture
	sprite.scale = Vector2.ONE * float(data.scale) * tree_scale
	sprite.position = Vector2(data.offset) * tree_scale
	add_child(sprite)

func _draw() -> void:
	if not _shadow_poly.is_empty():
		draw_colored_polygon(_shadow_poly, Color(0.02,0.035,0.045,0.25))

func _build_shared_view(variant: int) -> Dictionary:
	var view := SubViewport.new()
	view.name = "PineAtlas_%d_%d" % [int(is_snowy), variant]
	view.size = Vector2i(160,224)
	view.transparent_bg = true
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	get_parent().add_child(view)
	var tree := Node3D.new()
	view.add_child(tree)
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color("554333")
	var needles := StandardMaterial3D.new()
	needles.albedo_color = [Color("294337"),Color("345140"),Color("3e5544"),Color("2c4a40")][variant]
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("dde9ec")
	_cylinder(tree,Vector3(0,1.1,0),0.18,0.24,2.2,trunk,8)
	for tier in 4:
		var radius := 1.45 - tier*0.30
		var height := 1.9 - tier*0.15
		var center := 1.7+tier*0.83
		var branch := _cylinder(tree,Vector3(0,center,0),0.08,radius,height,needles,9)
		branch.rotation.y = variant*0.7+tier*0.25
		if is_snowy:
			var cap := _cylinder(tree,Vector3(0,center+0.26,0),0.02,radius*0.79,height*0.80,snow,9)
			cap.rotation.y = branch.rotation.y
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(0,10,6)
	camera.look_at(Vector3(0,2.0,0))
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_energy = 1.1
	view.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b5cbd5")
	env.environment.ambient_light_energy = 0.65
	view.add_child(env)
	var ppm := camera.unproject_position(Vector3.RIGHT).distance_to(camera.unproject_position(Vector3.ZERO))
	var display_scale := 18.0/ppm
	var offset := (Vector2(view.size)*0.5-camera.unproject_position(Vector3.ZERO))*display_scale
	# Limpa a referência quando a região é descarregada, inclusive após load.
	var key := "%s_%d_%d" % [get_parent().get_instance_id(), int(is_snowy), variant]
	view.tree_exiting.connect(func(): _views.erase(key))
	return {"viewport":weakref(view),"texture":view.get_texture(),"scale":display_scale,"offset":offset}

func _cylinder(parent: Node3D, point: Vector3, top: float, bottom: float, height: float, material: Material, sides: int) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top
	cylinder.bottom_radius = bottom
	cylinder.height = height
	cylinder.radial_segments = sides
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = point
	parent.add_child(mesh)
	return mesh
