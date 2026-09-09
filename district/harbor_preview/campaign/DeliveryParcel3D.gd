extends Node2D
## Mission-only parcel: readable at street zoom, gentle pulse, no global lights.
var model: Node3D
var viewport: SubViewport
var elapsed := 0.0
var screen_visible := false
func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(128,128)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	model = Node3D.new()
	viewport.add_child(model)
	_box(Vector3.ZERO,Vector3(1.25,0.85,0.85),Color("b87b38"))
	_box(Vector3(0,0.01,0),Vector3(0.15,0.89,0.9),Color("f6d996"))
	_box(Vector3(0,0.01,0),Vector3(1.29,0.89,0.14),Color("f6d996"))
	_box(Vector3(0.34,0.44,0.16),Vector3(0.3,0.025,0.23),Color("eaf2df"))
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position = Vector3(0,3,4)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55,-30,0)
	viewport.add_child(light)
	var sprite := Sprite2D.new()
	sprite.texture = viewport.get_texture()
	sprite.scale = Vector2.ONE*0.28
	sprite.position.y = -10
	add_child(sprite)
	var notifier := VisibleOnScreenNotifier2D.new()
	notifier.rect = Rect2(-48,-60,96,100)
	notifier.screen_entered.connect(func(): screen_visible = true)
	notifier.screen_exited.connect(func(): screen_visible = false)
	add_child(notifier)
	visibility_changed.connect(_update_visibility)
	_update_visibility()
func _box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	mesh.position = pos
	model.add_child(mesh)
func _update_visibility() -> void:
	set_process(is_visible_in_tree())
	if not is_visible_in_tree(): viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
func _process(delta: float) -> void:
	if not screen_visible: return
	elapsed += delta
	model.rotation.y += delta*0.8
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()
func _draw() -> void:
	var pulse := 0.55+0.2*sin(elapsed*2.5)
	draw_circle(Vector2.ZERO,18,Color(1,0.73,0.26,0.10))
	draw_arc(Vector2.ZERO,16,0,TAU,48,Color(1,0.79,0.35,pulse),2,true)
	draw_circle(Vector2.ZERO,9,Color(0,0,0,0.25))
