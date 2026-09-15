class_name MountainChairliftChair
extends Node2D

## Representação 2D com SubViewport 3D da cadeirinha de teleférico móvel.
## Circula ao longo do cabo do teleférico entre a Base e o Cume.

var cable_progress: float = 0.0 # 0.0 = Base, 1.0 = Cume
var is_ascending: bool = true
var speed: float = 0.028 # frações do trajeto por segundo (~35s viagem completa)
var model: Node3D
var viewport_3d: SubViewport
var sprite_3d: Sprite2D
var cable_points: PackedVector2Array
var clock: float = 0.0
var render_clock := 0.0

func setup(points: PackedVector2Array, initial_progress: float, ascending: bool, with_rider: bool, rider_col: Color = Color("c95444")) -> void:
	cable_points = points
	cable_progress = initial_progress
	render_clock = fposmod(initial_progress*1.37,1.0)/24.0
	is_ascending = ascending
	_build_view(with_rider, rider_col)
	_update_position(0.0)

func _build_view(with_rider: bool, rider_col: Color) -> void:
	z_as_relative = false
	z_index = 8
	viewport_3d = SubViewport.new()
	viewport_3d.name = "ChairViewport3D"
	viewport_3d.size = Vector2i(192, 224)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -24, 0)
	sun.light_energy = 1.0
	viewport_3d.add_child(sun)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b8c8d0")
	env.environment.ambient_light_energy = 0.7
	viewport_3d.add_child(env)

	model = preload("res://world/mountain_pass/MountainChairliftChair3D.gd").new()
	model.name = "ChairModel"
	viewport_3d.add_child(model)
	model.set_rider(with_rider, rider_col)

	var cam := Camera3D.new()
	viewport_3d.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 4.8
	cam.position = Vector3(0, 5.2, 5.0)
	cam.look_at(Vector3(0, 1.4, 0))
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	sprite_3d = Sprite2D.new()
	sprite_3d.name = "ChairSprite"
	sprite_3d.texture = viewport_3d.get_texture()
	sprite_3d.scale = Vector2.ONE * (18.0 * 4.8 / 192.0)
	sprite_3d.position = (Vector2(viewport_3d.size)*.5-cam.unproject_position(Vector3(0,3.2,0)))*sprite_3d.scale
	add_child(sprite_3d)

func _process(delta: float) -> void:
	clock += delta
	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	var open := schedule_script.is_open(self)

	# Se a estação estiver aberta, as cadeirinhas circulam pelo cabo
	if open:
		if is_ascending:
			cable_progress += speed * delta
			if cable_progress >= 1.0:
				cable_progress = 1.0
				is_ascending = false # Retorna descendo
				if is_instance_valid(model):
					model.set_rider(false) # Desembarcou no cume
		else:
			cable_progress -= speed * delta
			if cable_progress <= 0.0:
				cable_progress = 0.0
				is_ascending = true # Retorna subindo
				if is_instance_valid(model):
					# Embarca esquiador para subir
					var colors := [Color("c95444"), Color("387799"), Color("d2a844"), Color("508560")]
					model.set_rider(randf() < 0.65, colors[randi() % colors.size()])

	_update_position(delta)
	render_clock += delta
	if is_instance_valid(viewport_3d) and render_clock >= 1.0/24.0:
		render_clock = fmod(render_clock,1.0/24.0)
		var screen := get_viewport().get_canvas_transform() * global_position
		if get_viewport_rect().grow(120).has_point(screen):
			viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _update_position(delta: float) -> void:
	if cable_points.size() < 2: return
	var p_base := cable_points[cable_points.size() - 1]
	var p_summit := cable_points[0]

	# Deslocamento lateral para cabos paralelos de ida e volta (+Z/-Z)
	var dir := p_base.direction_to(p_summit)
	var perp := dir.orthogonal() * (14.0 if is_ascending else -14.0)

	# Os pontos pertencem ao espaço local da área, assim como o cabo e as torres.
	# Percorra todos os segmentos para acompanhar as mudanças de direção do cabo.
	var total_length := 0.0
	for i in range(1, cable_points.size()):
		total_length += cable_points[i - 1].distance_to(cable_points[i])
	var remaining := clampf(cable_progress, 0.0, 1.0) * total_length
	var pos := p_summit
	for i in range(cable_points.size() - 1, 0, -1):
		var segment_length := cable_points[i].distance_to(cable_points[i - 1])
		if segment_length <= 0.0:
			continue
		if remaining <= segment_length:
			pos = cable_points[i].lerp(cable_points[i - 1], remaining / segment_length)
			break
		remaining -= segment_length
	position = pos + perp

	# Balanço sutil do vento
	if is_instance_valid(model):
		model.set_swing(sin(clock * 1.6) * 0.045)
