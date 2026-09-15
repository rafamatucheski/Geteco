class_name MountainAltitudeParallax
extends Node2D

## Parallax de Altitude: A Cidade Minúscula Lá Embaixo:
## Renderiza a vista panorâmica do vale e da costa a milhares de metros abaixo,
## com a silhueta em miniatura dos arranha-céus, guindastes do porto, a grande ponte
## e nuvens em movimento contínuo passando abaixo do nível da estrada.

@export var parallax_factor: Vector2 = Vector2(0.12, 0.08)
@export var target_camera: Camera2D = null

var _cloud_offset: float = 0.0
var _clouds: Array[Dictionary] = []
var _air_material: ShaderMaterial

func _ready() -> void:
	z_index = -20 # Bem abaixo do piso e da estrada jogável
	_air_material = ShaderMaterial.new()
	_air_material.shader = preload("res://systems/atmosphere/distant_atmosphere.gdshader")
	material = _air_material
	_generate_clouds()

func set_atmosphere(air: Color, amount: float) -> void:
	_air_material.set_shader_parameter("air_color", air)
	_air_material.set_shader_parameter("air_amount", clampf(amount, 0.0, 0.85))

func _generate_clouds() -> void:
	_clouds.clear()
	for i in 12:
		_clouds.append({
			"pos": Vector2(randf_range(-1500, 2500), randf_range(-600, 1400)),
			"size": Vector2(randf_range(180, 420), randf_range(60, 140)),
			"speed": randf_range(15.0, 45.0),
			"alpha": randf_range(0.25, 0.55)
		})

func _process(delta: float) -> void:
	# Atualiza a deriva horizontal das nuvens
	for c in _clouds:
		c["pos"].x += c["speed"] * delta
		if c["pos"].x > 2800.0:
			c["pos"].x = -1600.0
	
	# Segue a câmera com fator de parallax reduzido
	if target_camera and is_instance_valid(target_camera):
		position = get_parent().to_local(target_camera.global_position) * (Vector2.ONE - parallax_factor)
	elif get_viewport().get_camera_2d():
		var cam := get_viewport().get_camera_2d()
		position = get_parent().to_local(cam.global_position) * (Vector2.ONE - parallax_factor)
	
	queue_redraw()

func _draw() -> void:
	# 1. Vale Profundo / Névoa Azulada do Horizonte
	var valley_rect := Rect2(-2500, -1000, 5000, 2500)
	draw_rect(valley_rect, Color(0.14, 0.18, 0.28, 0.9)) # Atmosfera densa fria
	
	# 2. Baía Marítima e Costa em Miniatura
	var water_rect := Rect2(400, 200, 2200, 1200)
	draw_rect(water_rect, Color(0.12, 0.25, 0.42, 0.85))
	
	# Linha de costa
	draw_line(Vector2(400, 200), Vector2(400, 1400), Color(0.35, 0.45, 0.38), 6.0)
	
	# 3. Arranha-céus em Miniatura da Cidade do Porto (Downtown Vista)
	var city_origin := Vector2(700, 450)
	var building_colors: Array[Color] = [
		Color(0.28, 0.35, 0.48),
		Color(0.22, 0.29, 0.40),
		Color(0.32, 0.40, 0.55),
		Color(0.25, 0.32, 0.44)
	]
	
	for col_idx in 14:
		for row_idx in 4:
			var bx := city_origin.x + col_idx * 34.0 + (row_idx % 2) * 8.0
			var by := city_origin.y + row_idx * 45.0
			var bw := 24.0 + (col_idx % 3) * 6.0
			var bh := 40.0 + (row_idx * 15.0) + (col_idx * 5.0)
			
			var bcol: Color = building_colors[(col_idx + row_idx) % building_colors.size()]
			# Prédio
			draw_rect(Rect2(bx, by - bh, bw, bh), bcol)
			# Janelas iluminadas minúsculas
			if (col_idx + row_idx) % 2 == 0:
				for wy in range(4, int(bh) - 6, 8):
					draw_rect(Rect2(bx + 4, by - bh + wy, 3, 3), Color(1.0, 0.9, 0.5, 0.7))
					draw_rect(Rect2(bx + bw - 7, by - bh + wy, 3, 3), Color(1.0, 0.9, 0.5, 0.7))
	
	# 4. Guindastes do Porto em Miniatura (Docks Cranes)
	var dock_origin := Vector2(430, 650)
	for i in 4:
		var cx: float = dock_origin.x + i * 55.0
		var cy: float = dock_origin.y
		draw_line(Vector2(cx, cy), Vector2(cx, cy - 35), Color(0.85, 0.35, 0.2), 3.0)
		draw_line(Vector2(cx - 10, cy - 35), Vector2(cx + 25, cy - 35), Color(0.85, 0.35, 0.2), 2.5)
	
	# 5. A Grande Ponte Estaiada em Miniatura (Ponte de Conexão com o Mapa 1)
	var bridge_start := Vector2(250, 480)
	var bridge_end := Vector2(680, 480)
	draw_line(bridge_start, bridge_end, Color(0.45, 0.5, 0.58), 5.0)
	# Pilares da ponte
	draw_line(Vector2(380, 480), Vector2(380, 420), Color(0.6, 0.65, 0.75), 4.0)
	draw_line(Vector2(520, 480), Vector2(520, 420), Color(0.6, 0.65, 0.75), 4.0)
	# Cabos de aço
	draw_line(Vector2(380, 420), Vector2(320, 480), Color(0.7, 0.75, 0.85, 0.7), 1.5)
	draw_line(Vector2(380, 420), Vector2(450, 480), Color(0.7, 0.75, 0.85, 0.7), 1.5)
	draw_line(Vector2(520, 420), Vector2(450, 480), Color(0.7, 0.75, 0.85, 0.7), 1.5)
	draw_line(Vector2(520, 420), Vector2(620, 480), Color(0.7, 0.75, 0.85, 0.7), 1.5)
	
	# 6. Camadas de Nuvens em Movimento Passando ABAIXO da Montanha
	for c in _clouds:
		var cpos: Vector2 = c["pos"]
		var csize: Vector2 = c["size"]
		var calpha: float = c["alpha"]
		draw_circle(cpos, csize.y * 0.5, Color(0.92, 0.95, 1.0, calpha))
		draw_circle(cpos + Vector2(csize.x * 0.35, 0), csize.y * 0.45, Color(0.92, 0.95, 1.0, calpha * 0.9))
		draw_circle(cpos - Vector2(csize.x * 0.35, 0), csize.y * 0.4, Color(0.92, 0.95, 1.0, calpha * 0.85))
