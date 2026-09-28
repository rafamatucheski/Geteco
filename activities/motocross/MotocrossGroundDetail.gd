extends Node3D
## Bounded, spatially culled grass. Same blade geometry/material as Harbor.
const GRASS := preload("res://world/urban_detail/HarborGrassTufts.gd")
const AREA := Rect2(-247,-147,160,125)
const CLEAR := [Rect2(-238,-39,13,9),Rect2(-237,-31,7,6),Rect2(-217,-38,6,13),Rect2(-229,-40,9,18)]
var course: Node3D
var tuft_count := 0
static var _ground: ShaderMaterial
static var _grass: StandardMaterial3D

static func bind_textures(material: ShaderMaterial) -> void:
	material.set_shader_parameter("grass_texture",GRASS.ground_material("grass").albedo_texture)
	material.set_shader_parameter("earth_texture",preload("res://world/urban_detail/RuralGroundMaterial.gd").material().get_shader_parameter("earth_texture"))

static func ground_material() -> ShaderMaterial:
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = preload("res://activities/motocross/MotocrossGround.gdshader")
		bind_textures(_ground)
	return _ground

static func grass_material() -> StandardMaterial3D:
	if _grass == null:
		_grass = GRASS._tuft_material().duplicate()
		_grass.albedo_color = Color(.56,.68,.39)
		_grass.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return _grass

func yard_height(p: Vector2) -> float:
	# A single connected raised earth apron supports the original feet/benches
	# at 13 cm, tapering into native ground instead of separate box-shaped pads.
	var edge := minf(minf(p.x+239,-209-p.x),minf(p.y+40,-24-p.y))
	return maxf(course.surface_height(p),.128*smoothstep(-2,0,edge))+.002

func _yard() -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-43,24):
		for x in range(-242,-206):
			for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
				var p: Vector2 = Vector2(x,z)+offset
				surface.add_vertex(Vector3(p.x,yard_height(p),p.y))
	surface.generate_normals()
	var mesh := surface.commit()
	var display := MeshInstance3D.new(); display.name = "ConnectedEarthYard"
	display.mesh = mesh; display.material_override = ground_material()
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(display)
	var body := StaticBody3D.new(); body.name = "ConnectedYardFloor"
	var shape := CollisionShape3D.new(); shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape); add_child(body)

func _ready() -> void:
	name = "MotocrossGrass"
	_yard()
	var rng := RandomNumberGenerator.new(); rng.seed = 38491
	for z in range(-147,-22,24):
		for x in range(-247,-87,24):
			var transforms: Array[Transform3D] = []
			for attempt in 440:
				var p := Vector2(x+rng.randf()*24,z+rng.randf()*24)
				if not AREA.has_point(p): continue
				var blocked := false
				for rect in CLEAR:
					if rect.grow(.6).has_point(p): blocked = true; break
				if blocked: continue
				var near: Dictionary = course.nearest(Vector3(p.x,0,p.y))
				if float(near.lateral)<course.HALF_WIDTH+1.2: continue
				var height: float = yard_height(p) if Rect2(-242,-43,36,67).has_point(p) else course.surface_height(p)
				var scale_value := rng.randf_range(.65,1.4)
				transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale_value),Vector3(p.x-x,height-.025,p.y-z)))
			if transforms.is_empty(): continue
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = GRASS._tuft_mesh(); mm.instance_count = transforms.size()
			for i in transforms.size(): mm.set_instance_transform(i,transforms[i])
			var display := MultiMeshInstance3D.new()
			display.multimesh = mm
			display.material_override = grass_material()
			display.position = Vector3(x,0,z)
			display.visibility_range_end = 100
			display.visibility_range_end_margin = 15
			display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(display)
			tuft_count += transforms.size()
