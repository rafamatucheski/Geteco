class_name ChopShopZone
extends Node2D

## Desmanche dos Cobras: dirija qualquer carro até a marca no chão (a mesma
## técnica de "roubar carro" que já existe no jogo — Player.try_enter_vehicle
## + Vehicle.enter_vehicle — funciona pra trazer qualquer veículo aqui) e ele
## é desmanchado: um eletroímã pega o carro, leva até a prensa e esmaga numa
## janela 3D. O jogador sai a pé com a grana da sucata.

const CRUSHER_SCRIPT := preload("res://ChopShopCrusher3D.gd")
const DOCK_OFFSET := Vector2(72, 0)

var _processing_car: Node = null

func _ready() -> void:
	add_to_group("chop_shop")
	_build_yard()
	_build_dock()

func _make_rect(pos: Vector2, size: Vector2, col: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)
	])
	poly.color = col
	return poly

func _create_circle_polygon(r: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * r)
	return arr

func _build_yard() -> void:
	z_index = -2

	# Chão de terra batida/óleo do pátio
	var ground := Polygon2D.new()
	ground.color = Color("#39332c")
	ground.polygon = PackedVector2Array([
		Vector2(-160, -110), Vector2(170, -110), Vector2(170, 120), Vector2(-160, 120)
	])
	add_child(ground)
	for stain_pos in [Vector2(-90, 40), Vector2(20, 80), Vector2(-40, -60)]:
		var stain := Polygon2D.new()
		stain.color = Color(0.03, 0.03, 0.02, 0.55)
		stain.polygon = _create_circle_polygon(18.0, 10)
		stain.position = stain_pos
		add_child(stain)

	# Cerca perimetral enferrujada (três lados, aberta na frente/leste)
	var fence_color := Color("#5c4a37")
	for fx in range(-150, 171, 20):
		add_child(_make_rect(Vector2(fx, -114), Vector2(4, 12), fence_color))
		add_child(_make_rect(Vector2(fx, 106), Vector2(4, 12), fence_color))
	for fy in range(-110, 121, 20):
		add_child(_make_rect(Vector2(-154, fy), Vector2(4, 12), fence_color))

	# Pilhas de pneu nos cantos
	for stack_pos in [Vector2(-130, -90), Vector2(-130, 95)]:
		for i in range(3):
			var tire := Polygon2D.new()
			tire.color = Color("#17181a")
			tire.polygon = _create_circle_polygon(11.0, 14)
			tire.position = stack_pos + Vector2(i * 3.0, -i * 4.0)
			add_child(tire)
			var hub := Polygon2D.new()
			hub.color = Color("#3a3d40")
			hub.polygon = _create_circle_polygon(4.0, 10)
			hub.position = tire.position
			add_child(hub)

	# Silhuetas de carros amassados esperando na fila (fora da marca)
	var wreck_colors := [Color("#5a2a1f"), Color("#33413f"), Color("#4a3b1c")]
	var wreck_positions := [Vector2(-90, -50), Vector2(-60, 70), Vector2(-115, 10)]
	for i in range(wreck_positions.size()):
		var wreck := Polygon2D.new()
		wreck.color = wreck_colors[i]
		wreck.rotation = deg_to_rad(randf_range(-18.0, 18.0))
		wreck.polygon = PackedVector2Array([
			Vector2(-16, -9), Vector2(14, -11), Vector2(18, 0), Vector2(14, 9), Vector2(-16, 9), Vector2(-20, 0)
		])
		wreck.position = wreck_positions[i]
		add_child(wreck)

	# Placa "DESMANCHE"
	var sign_board := Polygon2D.new()
	sign_board.color = Color("#c0521e")
	sign_board.rotation = deg_to_rad(-3.0)
	sign_board.polygon = PackedVector2Array([
		Vector2(-70, -100), Vector2(70, -104), Vector2(74, -76), Vector2(-74, -72)
	])
	add_child(sign_board)
	var sign_label := Label.new()
	sign_label.text = "DESMANCHE DOS COBRAS"
	sign_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_label.position = Vector2(-72, -100)
	sign_label.size = Vector2(148, 24)
	sign_label.rotation = deg_to_rad(-3.0)
	sign_label.add_theme_font_size_override("font_size", 11)
	sign_label.add_theme_color_override("font_color", Color("#fdf2e3"))
	sign_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	sign_label.add_theme_constant_override("shadow_offset_x", 1)
	sign_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(sign_label)

	# Silhueta 2D do guindaste, dando a deixa do que acontece na marca
	var crane_color := Color("#2b2d31")
	add_child(_make_rect(DOCK_OFFSET + Vector2(-6, -130), Vector2(6, 130), crane_color))
	add_child(_make_rect(DOCK_OFFSET + Vector2(-6, -134), Vector2(90, 6), crane_color))

func _build_dock() -> void:
	# Marca no chão: faixas de risco onde o carro precisa parar.
	var pad := Polygon2D.new()
	pad.color = Color("#2f2b26")
	pad.polygon = PackedVector2Array([
		DOCK_OFFSET + Vector2(-46, -26), DOCK_OFFSET + Vector2(46, -26),
		DOCK_OFFSET + Vector2(46, 26), DOCK_OFFSET + Vector2(-46, 26)
	])
	add_child(pad)
	for i in range(-40, 41, 16):
		var stripe := _make_rect(DOCK_OFFSET + Vector2(i, -26), Vector2(6, 52), Color("#f6c445"))
		stripe.rotation = deg_to_rad(18.0)
		add_child(stripe)

	var pad_label := Label.new()
	pad_label.text = "PARE AQUI PARA DESMANCHAR"
	pad_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pad_label.position = DOCK_OFFSET + Vector2(-70, -46)
	pad_label.size = Vector2(140, 14)
	pad_label.add_theme_font_size_override("font_size", 9)
	pad_label.add_theme_color_override("font_color", Color("#f6c445"))
	pad_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	pad_label.add_theme_constant_override("shadow_offset_x", 1)
	pad_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(pad_label)

	var trigger := Area2D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 1 | 2 | 4 | 8 # Qualquer veículo, seja qual for a camada
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(92, 52)
	col.shape = shape
	col.position = DOCK_OFFSET
	trigger.add_child(col)
	add_child(trigger)
	trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _processing_car != null or body == null:
		return
	if not body.is_in_group("vehicle"):
		return
	if body.is_in_group("personal_vehicle"):
		var player := get_tree().get_first_node_in_group("player")
		if player != null:
			player._show_weapon_notice("A MONALIZA É SUA. CUIDE DELA." if not TranslationServer.get_locale().begins_with("en") else "MONALIZA IS YOURS. TAKE CARE OF HER.")
		return
	_processing_car = body
	_start_crushing(body)

func _start_crushing(car: Node) -> void:
	if "velocity" in car:
		car.velocity = Vector2.ZERO
	if car.has_method("set_physics_process"):
		car.set_physics_process(false)
	car.global_position = global_position + DOCK_OFFSET
	if "rotation" in car:
		car.rotation = rotation

	if car.get("is_driven_by_player") == true and car.has_method("exit_vehicle"):
		car.exit_vehicle()

	var skid := AudioStreamPlayer2D.new()
	skid.bus = &"SFX"
	skid.stream = ProceduralAudio.get_skid_stream()
	skid.volume_db = -8.0
	skid.max_distance = 500.0
	get_tree().current_scene.add_child(skid)
	skid.global_position = car.global_position
	skid.play()
	skid.finished.connect(skid.queue_free)

	_show_crusher_overlay(car)

func _show_crusher_overlay(car: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	get_tree().current_scene.add_child(layer)

	var dimmer := ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.0)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dimmer)

	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.03, 0.04, 0.95)
	style.border_color = Color("#ffa502")
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	frame.add_theme_stylebox_override("panel", style)
	layer.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -290
	frame.offset_right = 290
	frame.offset_top = -220
	frame.offset_bottom = 220

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	frame.add_child(vbox)

	var caption := Label.new()
	caption.text = "DESMANCHANDO..."
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color("#ffa502"))
	vbox.add_child(caption)

	var crusher := CRUSHER_SCRIPT.new()
	vbox.add_child(crusher)

	var fade_in := create_tween()
	fade_in.tween_property(dimmer, "color:a", 0.72, 0.3)

	await get_tree().process_frame
	await get_tree().process_frame
	crusher.play_sequence()
	crusher.finished.connect(func(): _finish_crushing(car, layer))

func _finish_crushing(car: Node, layer: CanvasLayer) -> void:
	if is_instance_valid(layer):
		layer.queue_free()

	var reward := randi_range(300, 700)
	if is_instance_valid(car) and "target_length" in car:
		reward = int(300.0 + float(car.get("target_length")) * 4.0 + randi_range(0, 200))

	if is_instance_valid(car):
		car.queue_free()

	var player := get_tree().get_first_node_in_group("player")
	if player:
		if "money" in player:
			player.money += reward
		if player.has_method("report_chop_shop_delivery"):
			player.report_chop_shop_delivery(reward)
		if player.has_method("_refresh_weapon_ui"):
			player._refresh_weapon_ui()

	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_notice"):
		hud.show_notice("DESMANCHADO! +$%d EM SUCATA" % reward, Color("#ffa502"))

	_processing_car = null
