extends Node3D
var world
var points := PackedVector3Array([Vector3(-1.8,0,0),Vector3(-35.2,0,0),Vector3(1.8,0,-35.2),Vector3(4.25,0,9)])
var stage := -1
var dwell := 0.0
var completed := false
var marker: MeshInstance3D
var label: Label
var arrow: Label
var clock := 0.0

func _ready() -> void:
	marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 2.5
	ring.outer_radius = 2.65
	ring.rings = 40
	ring.ring_segments = 6
	marker.mesh = ring
	marker.scale.y = 0.12
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("7fe2d3")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.hide()
	add_child(marker)
	label = Label.new()
	label.position = Vector2(820,24)
	label.add_theme_font_size_override("font_size",20)
	world.hud.add_child(label)
	arrow = Label.new()
	arrow.text = "▲"
	arrow.add_theme_font_size_override("font_size",32)
	arrow.modulate = Color("7fe2d3")
	arrow.pivot_offset = Vector2(12,20)
	arrow.hide()
	world.hud.add_child(arrow)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R and completed:
		stage = -1
		completed = false
		dwell = 0

func _physics_process(delta: float) -> void:
	if completed: return
	if stage < 0:
		if not world.driving.occupied: return
		stage = 0
		marker.show()
		marker.position = points[stage]+Vector3.UP*0.08
	if world.driving.occupied and world.driving.car.position.distance_to(points[stage]) < 2.6 and absf(world.driving.car.speed) < 0.5:
		dwell += delta
		if dwell >= 1.0:
			stage += 1
			dwell = 0
			if stage >= points.size():
				completed = true
				marker.hide()
			else: marker.position = points[stage]+Vector3.UP*0.08
	else: dwell = 0

func _process(delta: float) -> void:
	clock += delta
	if clock < 0.1: return
	clock = 0
	if completed:
		label.text = "Percurso concluído · R  repetir"
		arrow.hide()
		return
	if stage < 0:
		label.text = "Entre no carro dourado · F"
		arrow.hide()
		return
	var point: Vector3 = world.driving.car.position if is_instance_valid(world.driving.car) else world.player.position
	var distance: float = point.distance_to(points[stage])
	label.text = "Parada %d / %d · %d m · pare na marca" % [stage+1,points.size(),roundi(distance)]
	var screen: Vector2 = world.camera.unproject_position(points[stage])
	var dimensions := get_viewport().get_visible_rect().size
	var border := Rect2(Vector2(50,80),dimensions-Vector2(100,180))
	arrow.visible = not border.has_point(screen)
	arrow.position = Vector2(clampf(screen.x,50,dimensions.x-70),clampf(screen.y,80,dimensions.y-110))
	arrow.rotation = (screen-dimensions/2).angle()+PI/2
