class_name CentralGarageInterior
extends Node2D

## Interior da Garagem Central Privativa
## Galpão com paredes sólidas travadas, blackout anti-área cinza,
## iluminação industrial e 4 Vagas de Estacionamento Compráveis.

signal player_entered_door(body: Node2D)
signal player_exited_door(body: Node2D)

@export var shop_name: String = "GARAGEM CENTRAL"
@export var accent_color: Color = Color("#f39c12")
@export var floor_color_primary: Color = Color("#1e2329")
@export var floor_color_secondary: Color = Color("#252a30")
@export var wall_color: Color = Color("#0f1216")

var spawn_point: Marker2D
var exit_door: BuildingEntrance
const JAGER_NPC := preload("res://JagerNPC.gd")

var parking_bays: Array[Dictionary] = [
	{"id": 1, "name": "Vaga #1 (Básica)", "price": 500, "pos": Vector2(-220, -120), "is_owned": false, "slot_node": null},
	{"id": 2, "name": "Vaga #2 (Padrão)", "price": 1500, "pos": Vector2(-220, 90), "is_owned": false, "slot_node": null},
	{"id": 3, "name": "Vaga #3 (Executiva)", "price": 3500, "pos": Vector2(220, -120), "is_owned": false, "slot_node": null},
	{"id": 4, "name": "Vaga #4 (VIP Ouro)", "price": 8000, "pos": Vector2(220, 90), "is_owned": false, "slot_node": null}
]

var active_player_near_bay: Dictionary = {}
var prompt_label: Label

func _ready() -> void:
	add_to_group("shop_interior")
	add_to_group("garage_interior")
	
	_build_blackout_and_walls()
	_build_floor_and_lanes()
	_build_parking_bays()
	_build_ceiling_lights()
	_build_jager_lounge()
	_build_mechanic_station()
	_build_ui_prompts()
	_build_spawn_and_exit()

func _build_ceiling_lights() -> void:
	var light_positions := [
		Vector2(-220, -120), Vector2(-220, 90),
		Vector2(0, -160), Vector2(0, 40),
		Vector2(220, -120), Vector2(220, 90)
	]
	
	for l_pos in light_positions:
		# Calha da luminária no teto
		var fixture := Polygon2D.new()
		fixture.color = Color("#2f3640")
		fixture.polygon = PackedVector2Array([
			Vector2(-24, -4), Vector2(24, -4), Vector2(24, 4), Vector2(-24, 4)
		])
		fixture.position = l_pos
		fixture.z_index = 6
		add_child(fixture)
		
		# Tubo Fluorescente Aceso
		var tube := Polygon2D.new()
		tube.color = Color("#f5f6fa")
		tube.polygon = PackedVector2Array([
			Vector2(-20, -2), Vector2(20, -2), Vector2(20, 2), Vector2(-20, 2)
		])
		fixture.add_child(tube)
		
		# Luz Suave Industrial
		var p_light := PointLight2D.new()
		p_light.color = Color(0.92, 0.95, 1.0)
		p_light.energy = 0.85
		p_light.position = l_pos
		p_light.z_index = 6
		
		var grad = Gradient.new()
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.65), Color(1, 1, 1, 0)])
		var tex = GradientTexture2D.new()
		tex.gradient = grad
		tex.width = 280
		tex.height = 280
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		p_light.texture = tex
		add_child(p_light)

func _build_blackout_and_walls() -> void:
	# Blackout total ao redor cobrindo a tela inteira (elimina a zona cinza)
	var blackout := Polygon2D.new()
	blackout.color = Color(0.04, 0.04, 0.05, 1.0)
	blackout.polygon = PackedVector2Array([
		Vector2(-2400, -2000), Vector2(2400, -2000), Vector2(2400, 2000), Vector2(-2400, 2000)
	])
	blackout.z_index = -5
	add_child(blackout)
	
	# Paredes Físicas Sólidas Indestrutíveis
	var walls_body := StaticBody2D.new()
	walls_body.name = "GarageSolidWalls"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	
	_add_wall_segment(walls_body, Vector2(0, -260), Vector2(800, 40))
	_add_wall_segment(walls_body, Vector2(380, 0), Vector2(40, 560))
	_add_wall_segment(walls_body, Vector2(-380, 0), Vector2(40, 560))
	_add_wall_segment(walls_body, Vector2(-230, 260), Vector2(340, 40))
	_add_wall_segment(walls_body, Vector2(230, 260), Vector2(340, 40))
	
	add_child(walls_body)

func _add_wall_segment(body: StaticBody2D, pos: Vector2, sz: Vector2) -> void:
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = sz
	col.shape = rect
	col.position = pos
	body.add_child(col)
	
	var poly := Polygon2D.new()
	poly.color = wall_color
	poly.polygon = PackedVector2Array([
		pos - sz * 0.5, Vector2(pos.x + sz.x * 0.5, pos.y - sz.y * 0.5),
		pos + sz * 0.5, Vector2(pos.x - sz.x * 0.5, pos.y + sz.y * 0.5)
	])
	poly.z_index = 4
	add_child(poly)
	
	var trim := Line2D.new()
	trim.points = poly.polygon
	trim.width = 3.0
	trim.default_color = Color("#e0a83d")
	trim.z_index = 5
	add_child(trim)

func _build_floor_and_lanes() -> void:
	var floor_poly := Polygon2D.new()
	floor_poly.color = floor_color_primary
	floor_poly.polygon = PackedVector2Array([
		Vector2(-360, -240), Vector2(360, -240), Vector2(360, 240), Vector2(-360, 240)
	])
	floor_poly.z_index = 0
	add_child(floor_poly)
	
	var lane := Polygon2D.new()
	lane.color = floor_color_secondary
	lane.polygon = PackedVector2Array([
		Vector2(-70, -240), Vector2(70, -240), Vector2(70, 240), Vector2(-70, 240)
	])
	lane.z_index = 1
	add_child(lane)
	
	# Piso estendido no vão da porta sul (elimina corte preto)
	var threshold_poly := Polygon2D.new()
	threshold_poly.color = floor_color_secondary
	threshold_poly.polygon = PackedVector2Array([
		Vector2(-65, 238), Vector2(65, 238), Vector2(65, 260), Vector2(-65, 260)
	])
	threshold_poly.z_index = 1
	add_child(threshold_poly)
	
	for side in [-1, 1]:
		var stripe := Line2D.new()
		stripe.points = PackedVector2Array([Vector2(side * 65, -230), Vector2(side * 65, 230)])
		stripe.width = 4.0
		stripe.default_color = Color("#f1c40f")
		stripe.z_index = 2
		add_child(stripe)

func _build_parking_bays() -> void:
	for i in range(parking_bays.size()):
		var bay = parking_bays[i]
		var bay_root := Node2D.new()
		bay_root.name = "ParkingBay_%d" % bay.id
		bay_root.position = bay.pos
		bay_root.z_index = 2
		add_child(bay_root)
		bay.slot_node = bay_root
		
		var bay_floor := Polygon2D.new()
		bay_floor.color = Color("#14181c")
		bay_floor.polygon = PackedVector2Array([
			Vector2(-90, -65), Vector2(90, -65), Vector2(90, 65), Vector2(-90, 65)
		])
		bay_root.add_child(bay_floor)
		
		var bay_lines := Line2D.new()
		bay_lines.points = PackedVector2Array([
			Vector2(-90, -65), Vector2(90, -65), Vector2(90, 65), Vector2(-90, 65), Vector2(-90, -65)
		])
		bay_lines.width = 3.0
		bay_lines.default_color = Color("#e67e22") if bay.id == 4 else Color("#f39c12")
		bay_root.add_child(bay_lines)
		
		var num_lbl := Label.new()
		num_lbl.text = "VAGA #%d" % bay.id
		num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num_lbl.position = Vector2(-45, -55)
		num_lbl.size = Vector2(90, 20)
		num_lbl.add_theme_font_size_override("font_size", 11)
		num_lbl.add_theme_color_override("font_color", Color("#f1c40f"))
		bay_root.add_child(num_lbl)
		
		var status_lbl := Label.new()
		status_lbl.name = "StatusLabel"
		status_lbl.text = "$ %d" % bay.price
		status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_lbl.position = Vector2(-60, 35)
		status_lbl.size = Vector2(120, 20)
		status_lbl.add_theme_font_size_override("font_size", 10)
		status_lbl.add_theme_color_override("font_color", Color("#2ecc71"))
		bay_root.add_child(status_lbl)
		
		var area := Area2D.new()
		area.name = "BayArea"
		area.collision_layer = 0
		area.collision_mask = 3
		var c := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(170, 130)
		c.shape = r
		area.add_child(c)
		bay_root.add_child(area)
		
		var b_idx = i
		area.body_entered.connect(func(body): _on_bay_body_entered(body, b_idx))
		area.body_exited.connect(func(body): _on_bay_body_exited(body, b_idx))

func _build_ui_prompts() -> void:
	prompt_label = Label.new()
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.position = Vector2(-200, -220)
	prompt_label.size = Vector2(400, 30)
	prompt_label.add_theme_font_size_override("font_size", 12)
	prompt_label.add_theme_color_override("font_color", Color("#ffffff"))
	prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	prompt_label.z_index = 20
	prompt_label.visible = false
	add_child(prompt_label)

func _build_spawn_and_exit() -> void:
	spawn_point = Marker2D.new()
	spawn_point.name = "SpawnPoint"
	spawn_point.position = Vector2(0, 160)
	add_child(spawn_point)
	
	var exit_scene = load("res://scripts/entrances/BuildingEntrance.tscn")
	if exit_scene:
		exit_door = exit_scene.instantiate() as BuildingEntrance
		exit_door.name = "InteriorExit"
		exit_door.position = Vector2(0, 240)
		exit_door.entrance_kind = 2
		exit_door.display_name = "SAIR DA GARAGEM"
		exit_door.destination_id = &"garage_exterior_return"
		exit_door.panel_slide_distance = 24.0
		
		# Reposiciona o sensor para o lado interno (y = -20)
		# O jogador é detectado no piso da garagem, sem precisar andar pro breu
		var sensor := exit_door.get_node_or_null("InteractionArea") as Area2D
		if sensor:
			sensor.position = Vector2(0, -20)
			
		var prompt := exit_door.get_node_or_null("Prompt") as Label
		if prompt:
			prompt.position = Vector2(-98, -48)
			
		add_child(exit_door)

func _on_bay_body_entered(body: Node2D, bay_index: int) -> void:
	if bay_index < 0 or bay_index >= parking_bays.size(): return
	var bay = parking_bays[bay_index]
	
	if body.is_in_group("player"):
		active_player_near_bay = bay
		_update_prompt_ui()

func _on_bay_body_exited(body: Node2D, bay_index: int) -> void:
	if active_player_near_bay.get("id") == parking_bays[bay_index].get("id"):
		active_player_near_bay = {}
		if prompt_label: prompt_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not active_player_near_bay.is_empty():
		if event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
			_try_buy_bay(active_player_near_bay)

func _try_buy_bay(bay: Dictionary) -> void:
	if bay.is_owned:
		return
		
	var player = get_tree().get_first_node_in_group("player")
	if not player: return
	
	var price: int = bay.price
	var current_money: int = player.money if "money" in player else 0
	
	if current_money >= price:
		player.money -= price
		bay.is_owned = true
		if player.has_method("_refresh_weapon_ui"):
			player._refresh_weapon_ui()
			
		var status_lbl = bay.slot_node.get_node_or_null("StatusLabel") as Label
		if status_lbl:
			status_lbl.text = "RESERVADA"
			status_lbl.add_theme_color_override("font_color", Color("#f1c40f"))
			
		var p := AudioStreamPlayer2D.new()
		p.stream = ProceduralAudio.get_cash_register_stream()
		p.volume_db = -3.0
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)
		
		_update_prompt_ui()
	else:
		if prompt_label:
			prompt_label.text = "DINHEIRO INSUFICIENTE ($ %d NECESSÁRIOS)" % price
			prompt_label.add_theme_color_override("font_color", Color("#e74c3c"))

func _update_prompt_ui() -> void:
	if active_player_near_bay.is_empty() or not prompt_label:
		if prompt_label: prompt_label.visible = false
		return
		
	var bay = active_player_near_bay
	prompt_label.visible = true
	if bay.is_owned:
		prompt_label.text = "[ %s: SUA VAGA PRIVATIVA ]" % bay.name.to_upper()
		prompt_label.add_theme_color_override("font_color", Color("#2ecc71"))
	else:
		prompt_label.text = "E"
		prompt_label.add_theme_color_override("font_color", Color("#f1c40f"))

func _apply_theme() -> void:
	pass

func _build_jager_lounge() -> void:
	var lounge_pos := Vector2(0, -180)
	
	# Tapete Persa Ornamental de Luxo
	var carpet := Polygon2D.new()
	carpet.color = Color("#581845")
	carpet.polygon = PackedVector2Array([
		Vector2(-70, -35), Vector2(70, -35), Vector2(70, 35), Vector2(-70, 35)
	])
	carpet.position = lounge_pos
	carpet.z_index = 2
	add_child(carpet)

	# Borda Dourada do Tapete
	var border := Line2D.new()
	border.points = PackedVector2Array([
		Vector2(-70, -35), Vector2(70, -35), Vector2(70, 35), Vector2(-70, 35), Vector2(-70, -35)
	])
	border.default_color = Color("#f1c40f")
	border.width = 3.0
	border.position = lounge_pos
	border.z_index = 3
	add_child(border)

	# Mesa Executiva de Vidro e Ouro
	var desk := Polygon2D.new()
	desk.color = Color("#1c2833")
	desk.polygon = PackedVector2Array([
		Vector2(-28, -14), Vector2(28, -14), Vector2(28, 14), Vector2(-28, 14)
	])
	desk.position = lounge_pos + Vector2(38, -10)
	desk.z_index = 4
	add_child(desk)

	var desk_border := Line2D.new()
	desk_border.points = PackedVector2Array([
		Vector2(-28, -14), Vector2(28, -14), Vector2(28, 14), Vector2(-28, 14), Vector2(-28, -14)
	])
	desk_border.default_color = Color("#d4ac0d")
	desk_border.width = 2.0
	desk_border.position = desk.position
	desk_border.z_index = 5
	add_child(desk_border)

	# Luminária Pendente VIP sobre o Lounge
	var lamp := PointLight2D.new()
	lamp.color = Color(1.0, 0.92, 0.70, 1.0)
	lamp.energy = 0.95
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 240
	tex.height = 240
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	lamp.texture = tex
	lamp.position = lounge_pos
	lamp.z_index = 7
	add_child(lamp)

	# Placa Luminosa de Identificação do Lounge VIP
	var lounge_sign := Label.new()
	lounge_sign.text = "★ ESCRITÓRIO VIP · JÄGER 'MACIOTA' ★"
	lounge_sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lounge_sign.position = lounge_pos + Vector2(-160, -56)
	lounge_sign.size = Vector2(320, 20)
	lounge_sign.add_theme_font_size_override("font_size", 11)
	lounge_sign.add_theme_color_override("font_color", Color("#f1c40f"))
	lounge_sign.add_theme_color_override("font_shadow_color", Color.BLACK)
	lounge_sign.add_theme_constant_override("shadow_offset_x", 1)
	lounge_sign.add_theme_constant_override("shadow_offset_y", 1)
	lounge_sign.z_index = 8
	add_child(lounge_sign)

	# Instanciação do NPC Jäger "Maciota"
	var jager = JAGER_NPC.new()
	jager.name = "JagerMaciota"
	jager.position = lounge_pos + Vector2(-15, 0)
	add_child(jager)

func _build_mechanic_station() -> void:
	var station_pos := Vector2(280, -180)
	
	# Bancada de Ferramentas de Oficina
	var bench := Polygon2D.new()
	bench.color = Color("#b33939")
	bench.polygon = PackedVector2Array([
		Vector2(-40, -14), Vector2(40, -14), Vector2(40, 14), Vector2(-40, 14)
	])
	bench.position = station_pos + Vector2(0, -10)
	bench.z_index = 4
	add_child(bench)
	
	# Borda da bancada
	var bench_trim := Line2D.new()
	bench_trim.points = PackedVector2Array([
		Vector2(-40, -14), Vector2(40, -14), Vector2(40, 14), Vector2(-40, 14), Vector2(-40, -14)
	])
	bench_trim.default_color = Color("#d63031")
	bench_trim.width = 2.0
	bench_trim.position = bench.position
	bench_trim.z_index = 5
	add_child(bench_trim)
	
	# Pilha de Pneus de Competição
	var tires := Polygon2D.new()
	tires.color = Color("#1e272e")
	tires.polygon = PackedVector2Array([
		Vector2(-14, -14), Vector2(14, -14), Vector2(14, 14), Vector2(-14, 14)
	])
	tires.position = station_pos + Vector2(-55, 0)
	tires.z_index = 4
	add_child(tires)
	
	# Letreiro da Oficina
	var mech_label := Label.new()
	mech_label.text = "OFICINA DE PREPARAÇÃO · TITO 'GRAXA'"
	mech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mech_label.position = station_pos + Vector2(-140, -56)
	mech_label.size = Vector2(280, 20)
	mech_label.add_theme_font_size_override("font_size", 10)
	mech_label.add_theme_color_override("font_color", Color("#e67e22"))
	mech_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	mech_label.z_index = 8
	add_child(mech_label)
	
	# Instanciação do Mecânico Tito 'Graxa'
	var tito := AnimatedPedestrian3D.new()
	tito.name = "MechanicTito"
	tito.position = station_pos + Vector2(0, 15)
	tito.archetype_override = 1
	tito.shirt_color = Color("#2980b9")
	tito.pants_color = Color("#1a5276")
	tito.base_walk_speed = 0.0
	add_child(tito)
