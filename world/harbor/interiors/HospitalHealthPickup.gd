extends "res://HealthPickup.gd"
var viewport_3d: SubViewport
var cross_3d: Node3D
func _ready() -> void:
	super._ready()
	collision_mask=5
	for child in cross_root.get_children(): child.queue_free()
	viewport_3d=SubViewport.new()
	viewport_3d.size=Vector2i(96,96)
	viewport_3d.transparent_bg=true
	viewport_3d.own_world_3d=true
	add_child(viewport_3d)
	var camera=Camera3D.new()
	viewport_3d.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=1.9
	camera.look_at_from_position(Vector3(0,1.4,3),Vector3.ZERO)
	cross_3d=Node3D.new()
	viewport_3d.add_child(cross_3d)
	var detail=preload("res://world/shared/pedestrians/CitizenDetails.gd")
	for size in [Vector3(.9,.28,.24),Vector3(.28,.9,.24)]:
		var part=detail.piece(cross_3d,size,Vector3.ZERO,Color("ef647d"))
		part.material_override.emission_enabled=true
		part.material_override.emission=Color("762238")
	var light=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-40,-35,0)
	viewport_3d.add_child(light)
	var display=Sprite2D.new()
	display.texture=viewport_3d.get_texture()
	display.scale=Vector2.ONE*.48
	cross_root.add_child(display)
func _process(delta: float) -> void:
	super._process(delta)
	cross_root.scale.x=1.0
	cross_root.position.y=-16+sin(_clock*2)*3
	cross_3d.rotation.y=_clock*.65
func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player") or body.get("health")==null: return
	if body.health>=body.max_health: return
	super._on_body_entered(body)
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_DISABLED
func _respawn_pickup() -> void:
	super._respawn_pickup()
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
func set_rendering_active(active: bool) -> void:
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_ALWAYS if active and not _is_collected else SubViewport.UPDATE_DISABLED
