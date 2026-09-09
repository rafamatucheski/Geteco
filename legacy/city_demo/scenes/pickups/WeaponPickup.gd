class_name WeaponPickup
extends Area2D

## Drop Compacto de Arma com Ícone Silhueta Personalizado (GTA Clássico)
## Renderiza o formato geométrico exato da arma (Pistola, Magnum, MP5, 12G, AK-47, M4A1, RPG, etc.)
## Tamanho compacto, rotação suave, halo luminoso e coleta imediata ou por interação.

@export var weapon_id: StringName = &"pistol"
@export_range(0, 300, 1) var ammo_amount: int = 12
@export var interaction_radius: float = 22.0

var _nearby_player: Node2D
var _base_y: float
var _time := 0.0
var _consumed := false

var _art_root: Node2D
var _glow_circle: Polygon2D
var _prompt_label: Label

func _ready() -> void:
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 4 # Camada do Player
	z_index = 8
	
	_base_y = position.y
	_ensure_collision()
	_build_weapon_icon()
	
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Desaparece suavemente após 35 segundos se abandonada na rua
	var tw = create_tween()
	tw.tween_interval(28.0)
	tw.tween_property(self, "modulate:a", 0.0, 7.0)
	tw.tween_callback(queue_free)

func _process(delta: float) -> void:
	if _consumed: return
	_time += delta
	position.y = _base_y + sin(_time * 3.2) * 1.5
	if _art_root:
		_art_root.rotation = _time * 1.6
	if _glow_circle:
		_glow_circle.scale = Vector2.ONE * (1.0 + sin(_time * 2.5) * 0.12)

func _ensure_collision() -> void:
	if get_node_or_null("CollisionShape2D") != null:
		return
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape.shape = circle
	add_child(shape)

func _build_weapon_icon() -> void:
	# 1. Halo circular suave no chão
	_glow_circle = Polygon2D.new()
	_glow_circle.polygon = _create_circle_polygon(12.0, 14)
	_glow_circle.color = _get_halo_color()
	add_child(_glow_circle)

	# 2. Raiz rotativa do modelo 2D da arma
	_art_root = Node2D.new()
	_art_root.name = "WeaponArtRoot"
	add_child(_art_root)

	# 3. Monta a silhueta geométrica proporcional da arma
	_create_weapon_geometry(String(weapon_id).to_lower())

	# 4. Label de prompt compacto
	_prompt_label = Label.new()
	_prompt_label.text = "%s (+%d)" % [_get_weapon_short_name(), ammo_amount]
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.position = Vector2(-36, -24)
	_prompt_label.size = Vector2(72, 14)
	_prompt_label.add_theme_font_size_override("font_size", 8)
	_prompt_label.add_theme_color_override("font_color", Color("#ffffff"))
	_prompt_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	_prompt_label.visible = false
	add_child(_prompt_label)

func _create_circle_polygon(radius: float, points: int) -> PackedVector2Array:
	var arr := PackedVector2Array()
	for i in range(points):
		var ang = (float(i) / float(points)) * TAU
		arr.append(Vector2(cos(ang), sin(ang)) * radius)
	return arr

func _get_halo_color() -> Color:
	match String(weapon_id).to_lower():
		"magnum", "pistol": return Color(1.0, 0.8, 0.2, 0.25) # Amarelo/Ouro
		"smg", "m4a1": return Color(0.2, 0.8, 1.0, 0.25)      # Ciano
		"shotgun", "sawed_off": return Color(1.0, 0.55, 0.15, 0.25) # Laranja
		"ak47", "rpg", "flamethrower": return Color(1.0, 0.25, 0.25, 0.28) # Vermelho
		"grenade": return Color(0.2, 0.9, 0.4, 0.25)          # Verde
		_: return Color(0.5, 0.9, 0.5, 0.25)

func _get_weapon_short_name() -> String:
	match String(weapon_id).to_lower():
		"pistol": return "9MM"
		"magnum": return "MAGNUM"
		"smg": return "MP5"
		"shotgun": return "12G"
		"sawed_off": return "SERRADA"
		"ak47": return "AK-47"
		"m4a1": return "M4A1"
		"rpg": return "RPG-7"
		"flamethrower": return "CHAMAS"
		"grenade": return "GRANADA"
		_: return String(weapon_id).to_upper()

func _create_weapon_geometry(id: String) -> void:
	match id:
		"pistol":
			# Pistola 9mm Compacta (12x8px)
			var slide = _make_rect(Vector2(-5, -3), Vector2(10, 3.5), Color("#2d3436"))
			var barrel = _make_rect(Vector2(4, -2.5), Vector2(2, 2.5), Color("#636e72"))
			var grip = _make_rect(Vector2(-4, 0.5), Vector2(3.5, 5.5), Color("#1e272e"))
			_art_root.add_child(slide)
			_art_root.add_child(barrel)
			_art_root.add_child(grip)
		"magnum":
			# Revólver .44 Magnum Cromado com Cano Longo (16x9px)
			var barrel = _make_rect(Vector2(-6, -3), Vector2(13, 3), Color("#bdc3c7"))
			var cylinder = _make_rect(Vector2(-2, -2.5), Vector2(5, 4.5), Color("#7f8c8d"))
			var grip = _make_rect(Vector2(-5, 1.5), Vector2(3.5, 6), Color("#795548")) # Empunhadura de madeira
			_art_root.add_child(barrel)
			_art_root.add_child(cylinder)
			_art_root.add_child(grip)
		"smg":
			# Submetralhadora MP5 (16x9px)
			var body = _make_rect(Vector2(-7, -3), Vector2(14, 3.5), Color("#2f3542"))
			var mag = _make_rect(Vector2(0, 0.5), Vector2(2.5, 6), Color("#1e272e"))
			var grip = _make_rect(Vector2(-5, 0.5), Vector2(3, 5), Color("#1e272e"))
			var stock = _make_rect(Vector2(-10, -2), Vector2(3, 2), Color("#747d8c"))
			_art_root.add_child(body)
			_art_root.add_child(mag)
			_art_root.add_child(grip)
			_art_root.add_child(stock)
		"shotgun":
			# Escopeta 12G Pump (20x6px)
			var barrel = _make_rect(Vector2(-9, -2), Vector2(18, 2.5), Color("#2f3542"))
			var pump = _make_rect(Vector2(-1, -1), Vector2(5, 3), Color("#a0522d")) # Telha de madeira
			var stock = _make_rect(Vector2(-10, 0), Vector2(4, 3.5), Color("#a0522d")) # Coronha de madeira
			_art_root.add_child(barrel)
			_art_root.add_child(pump)
			_art_root.add_child(stock)
		"sawed_off":
			# Cano Serrado Duplo (14x7px)
			var barrels = _make_rect(Vector2(-5, -2), Vector2(11, 3), Color("#57606f"))
			var grip = _make_rect(Vector2(-6, 1), Vector2(3.5, 5), Color("#8d6e63"))
			_art_root.add_child(barrels)
			_art_root.add_child(grip)
		"ak47":
			# Fuzil AK-47 Clássico (22x9px)
			var barrel = _make_rect(Vector2(-10, -3), Vector2(20, 2.5), Color("#2f3542"))
			var stock = _make_rect(Vector2(-11, -1), Vector2(5, 4), Color("#d35400")) # Coronha de madeira avermelhada
			var mag = Polygon2D.new() # Carregador banana curvo
			mag.polygon = PackedVector2Array([
				Vector2(0, -0.5), Vector2(3, -0.5), Vector2(1.5, 6.5), Vector2(-1.5, 6.5)
			])
			mag.color = Color("#e67e22")
			_art_root.add_child(barrel)
			_art_root.add_child(stock)
			_art_root.add_child(mag)
		"m4a1":
			# Carabina M4A1 Tática (22x9px)
			var barrel = _make_rect(Vector2(-10, -2.5), Vector2(20, 2.5), Color("#1e272e"))
			var handle = _make_rect(Vector2(-3, -5), Vector2(6, 2.5), Color("#2f3542")) # Alça de mira
			var mag = _make_rect(Vector2(0, 0), Vector2(2.5, 6), Color("#57606f"))
			var stock = _make_rect(Vector2(-11, -1.5), Vector2(4, 3.5), Color("#1e272e"))
			_art_root.add_child(barrel)
			_art_root.add_child(handle)
			_art_root.add_child(mag)
			_art_root.add_child(stock)
		"rpg":
			# Lança-Foguetes RPG-7 (24x9px)
			var tube = _make_rect(Vector2(-9, -2), Vector2(18, 3.5), Color("#27ae60")) # Tubo verde militar
			var exhaust = Polygon2D.new() # Cone de exaustão traseiro
			exhaust.polygon = PackedVector2Array([
				Vector2(-9, -2), Vector2(-9, 1.5), Vector2(-12, 3), Vector2(-12, -3.5)
			])
			exhaust.color = Color("#2c3e50")
			var warhead = Polygon2D.new() # Ogiva pontiaguda vermelha
			warhead.polygon = PackedVector2Array([
				Vector2(9, -3), Vector2(14, 0), Vector2(9, 3)
			])
			warhead.color = Color("#e74c3c")
			_art_root.add_child(tube)
			_art_root.add_child(exhaust)
			_art_root.add_child(warhead)
		"flamethrower":
			# Lança-Chamas com Tanque Duplo (18x10px)
			var tanks = _make_rect(Vector2(-7, -4), Vector2(9, 6), Color("#c0392b"))
			var nozzle = _make_rect(Vector2(2, -1.5), Vector2(8, 2.5), Color("#7f8c8d"))
			var flame_tip = _make_rect(Vector2(9, -2), Vector2(2.5, 3.5), Color("#f39c12"))
			_art_root.add_child(tanks)
			_art_root.add_child(nozzle)
			_art_root.add_child(flame_tip)
		"grenade":
			# Granada de Fragmentação Oval (8x11px)
			var body = Polygon2D.new()
			body.polygon = PackedVector2Array([
				Vector2(-3.5, -4), Vector2(3.5, -4), Vector2(4.5, 0),
				Vector2(3.5, 4), Vector2(-3.5, 4), Vector2(-4.5, 0)
			])
			body.color = Color("#27ae60")
			var pin = _make_rect(Vector2(-1.5, -6.5), Vector2(3, 2.5), Color("#bdc3c7"))
			_art_root.add_child(body)
			_art_root.add_child(pin)
		_:
			# Padrão compacto
			var default_box = _make_rect(Vector2(-6, -3), Vector2(12, 6), Color("#57606f"))
			_art_root.add_child(default_box)

func _make_rect(pos: Vector2, size: Vector2, col: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		pos, pos + Vector2(size.x, 0), pos + size, pos + Vector2(0, size.y)
	])
	poly.color = col
	return poly

func _on_body_entered(body: Node2D) -> void:
	if _consumed: return
	if body.is_in_group("player"):
		_nearby_player = body
		if _prompt_label: _prompt_label.visible = true
		# Coleta automática imediata ao passar por cima
		_take(body)

func _on_body_exited(body: Node2D) -> void:
	if body == _nearby_player:
		_nearby_player = null
		if _prompt_label: _prompt_label.visible = false

func _take(player: Node) -> void:
	if _consumed: return
	_consumed = true
	
	if player.has_method("add_weapon_loot"):
		player.add_weapon_loot(weapon_id, ammo_amount)
	
	# Som de recarga/equipamento
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = ProceduralAudio.get_gunshot_pistol_stream()
	p.pitch_scale = 1.6
	p.volume_db = -10.0
	p.max_distance = 450.0
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)
	
	# Efeito de absorção suave
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)
