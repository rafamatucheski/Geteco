extends Node2D
## Static 3D infrastructure, projected with the train's 4:3 camera slope.
## Geometry is grouped by material and rendered only on first visibility.
var boxes: Dictionary = {}
var bounds := Rect2()
var viewport: SubViewport
var display: Sprite2D
var _built := false

func box(center: Vector2, size: Vector3, height: float, heading: float, color: String) -> void:
	if not boxes.has(color): boxes[color] = []
	boxes[color].append(Transform3D(Basis(Vector3.UP, -heading).scaled_local(size), Vector3(center.x, height, center.y)))
	var radius := Vector2(size.x + size.z, size.x + size.z) * 0.5
	var rect := Rect2(center - radius - Vector2(0, maxf(0, height)*0.6), radius*2 + Vector2(0,absf(height)*0.6+size.y))
	bounds = rect if bounds.size == Vector2.ZERO else bounds.merge(rect)

func finish() -> void:
	if boxes.is_empty(): return
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = bounds.grow(16)
	add_child(notifier)
	notifier.screen_entered.connect(_build)

func _build() -> void:
	if _built: return
	_built = true
	var area := bounds.grow(8)
	var center := area.get_center()
	viewport = SubViewport.new()
	viewport.size = Vector2i(ceilf(area.size.x * 1.5), ceilf(area.size.y * 1.5))
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var stage := Node3D.new()
	stage.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var projection := Node3D.new()
	projection.scale.z = 1.25
	stage.add_child(projection)
	for color in boxes:
		var mesh := BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color)
		mat.roughness = 0.82
		if color == "b9c8cb":
			mat.metallic = 0.65
			mat.roughness = 0.32
		mesh.material = mat
		mesh.size = Vector3.ONE
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = mesh
		instances.instance_count = boxes[color].size()
		for i in boxes[color].size():
			var transform: Transform3D = boxes[color][i]
			transform.origin -= Vector3(center.x,0,center.y)
			instances.set_instance_transform(i, transform)
		var node := MultiMeshInstance3D.new()
		node.multimesh = instances
		projection.add_child(node)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c5d4df")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52,-32,0)
	light.light_color = Color("ffe6c3")
	light.light_energy = 1.25
	stage.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = area.size.x
	camera.far = 10000
	camera.position = Vector3(0,1600,1200)
	stage.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	display = Sprite2D.new()
	display.texture = viewport.get_texture()
	display.position = center
	display.scale = area.size / Vector2(viewport.size)
	display.material = material
	add_child(display)

static func track(parent: Node2D, rail: Node2D, from: float, to: float, bridge := false) -> void:
	var offset := from
	while offset < to:
		var chunk = load("res://world/shared/rail/RailStructure3D.gd").new()
		chunk.name = "Track3D_%d" % int(offset)
		chunk.material = parent.material
		parent.add_child(chunk)
		var end := minf(offset + 480, to)
		var d := offset
		while d < end:
			var next := minf(d + 12, end)
			var a: Vector2 = rail._route.sample_baked(d, true)
			var b: Vector2 = rail._route.sample_baked(next, true)
			var midpoint := (a+b)*0.5
			var angle := a.angle_to_point(b)
			var normal := a.direction_to(b).orthogonal()
			var length := a.distance_to(b)+0.3
			chunk.box(midpoint, Vector3(length,6,48), -8, angle, "747e78")
			chunk.box(midpoint, Vector3(length,2,36), -4, angle, "555954")
			for side in [-1.0,1.0]:
				var at: Vector2 = midpoint + normal*11*side
				chunk.box(at,Vector3(length,1,4),-2.5,angle,"67554a")
				chunk.box(at,Vector3(length,2,1.2),-1,angle,"687779")
				chunk.box(at,Vector3(length,1,2.8),0,angle,"b9c8cb")
				chunk.box(midpoint+normal*22*side,Vector3(length,3,3),-4,angle,"a5aaa0")
			d = next
		d = ceilf(offset/18)*18
		while d < end:
			var at: Vector2 = rail._route.sample_baked(d,true)
			var angle: float = rail._route_tangent(d).angle()
			var normal: Vector2 = rail._route_tangent(d).orthogonal()
			chunk.box(at,Vector3(5,3,33),-3,angle,"64503c" if int(d/18)%3 else "79634d")
			for side in [-1.0,1.0]:
				chunk.box(at+normal*11*side,Vector3(7,0.8,6),-1.6,angle,"444e50")
			d += 18
		if bridge:
			d = offset
			while d < end:
				var next := minf(d+60,end)
				var a: Vector2 = rail._route.sample_baked(d,true)
				var b: Vector2 = rail._route.sample_baked(next,true)
				var normal := a.direction_to(b).orthogonal()
				for side in [-1.0,1.0]:
					chunk.box((a+b)*0.5+normal*26*side,Vector3(a.distance_to(b)+0.5,3,3),13,a.angle_to_point(b),"7d9593")
					chunk.box(a+normal*26*side,Vector3(3,22,3),3,a.angle_to_point(b),"536e70")
					var start := Vector3(a.x+normal.x*26*side,-7,a.y+normal.y*26*side)
					var finish := Vector3(b.x+normal.x*26*side,13,b.y+normal.y*26*side)
					var direction := finish-start
					var brace := Basis(Quaternion(Vector3.RIGHT,direction.normalized())).scaled_local(Vector3(direction.length(),2,2))
					chunk.boxes["536e70"].append(Transform3D(brace,(start+finish)*0.5))
				d = next
		chunk.finish()
		offset = end

static func supports(parent: Node2D, footprints: Array[Rect2]) -> void:
	for rect in footprints:
		var pier = load("res://world/shared/rail/RailStructure3D.gd").new()
		parent.add_child(pier)
		pier.box(rect.get_center(),Vector3(rect.size.x,2,rect.size.y),1,0,"707a72")
		pier.box(rect.get_center(),Vector3(rect.size.x-2,42,rect.size.y-2),22,0,"a6aea0")
		pier.box(rect.get_center(),Vector3(38,5,rect.size.y),44,0,"89978d")
		pier.finish()


static func barriers(parent: Node2D, footprints: Array[Rect2]) -> void:
	for rect in footprints:
		var y := rect.position.y
		while y < rect.end.y:
			var length := minf(240,rect.end.y-y)
			var chunk = load("res://world/shared/rail/RailStructure3D.gd").new()
			parent.add_child(chunk)
			var center := Vector2(rect.get_center().x,y+length*0.5)
			chunk.box(center,Vector3(rect.size.x,8,length),4,0,"505e62")
			chunk.box(center,Vector3(rect.size.x,2,length),9,0,"c5c3ac")
			chunk.finish()
			y += length
