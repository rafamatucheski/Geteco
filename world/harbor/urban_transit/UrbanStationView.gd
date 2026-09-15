extends "res://world/mountain_pass/MountainStaticModelView.gd"
var orientation := 0.0
var terminal := false
var animated_people := 0
var on_screen := false
func _ready() -> void:
	build_view(preload("res://world/harbor/urban_transit/UrbanStationModel3D.gd"),29.0,18.0,Vector3(0,1,0))
	viewport_3d.size = Vector2i(1440,1200)
	var rendered_metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE*18.0/rendered_metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*0.5)*sprite_3d.scale
	viewport_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	model.build(orientation,terminal)
	for child in viewport_3d.get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = true
			child.directional_shadow_max_distance = 45
			child.light_energy = 0.8
			child.shadow_bias = 0.10
			child.shadow_normal_bias = 2.0
	var visibility := VisibleOnScreenNotifier2D.new()
	visibility.rect = Rect2(-255,-290,510,500)
	visibility.screen_entered.connect(func(): on_screen=true; request_redraw())
	visibility.screen_exited.connect(func(): on_screen=false; request_redraw())
	add_child(visibility)

func request_redraw() -> void:
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED if not on_screen else (SubViewport.UPDATE_WHEN_VISIBLE if animated_people>0 else SubViewport.UPDATE_ONCE)

func set_service(active: bool) -> void:
	model.set_service(active)
	request_redraw()
