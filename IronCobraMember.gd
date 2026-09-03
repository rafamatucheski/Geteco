class_name IronCobraMember
extends AnimatedPedestrian3D

## Membro de Elite da Gangue "Os Cobras de Ferro" (Bairro 1 / Mercado Velho)
## Veste jaqueta de couro preta com detalhes vinho, bandana escura e corrente dourada.
## Guarda o esconderijo do Don e o Cobra V8 Custom.

@export var guard_center: Vector2 = Vector2(610, 200)
@export var guard_radius: float = 180.0
@export var is_boss_guard: bool = false

var _shout_cooldown: float = 0.0

func _ready() -> void:
	district_theme = DistrictTheme.CITY_DOWNTOWN
	archetype = Archetype.CITY_GANGSTER
	is_gangster = true
	has_handgun = true
	dropped_cash = randi_range(65, 140)
	max_health = 120 if is_boss_guard else 80
	health = max_health
	
	# Cores exclusivas dos Cobras de Ferro
	shirt_color = Color("#111114") # Jaqueta preta de couro
	pants_color = Color("#1e272e") # Jeans escuro
	shoe_color = Color("#0a0a0c")  # Botas pretas
	hat_color = Color("#800000")   # Bandana vinho
	has_bandana = true
	has_sunglasses = true
	accessory_color = Color("#121214")
	
	add_to_group("iron_cobras")
	add_to_group("gang_member")
	
	super._ready()

func _physics_process(delta: float) -> void:
	if is_dead:
		return
		
	_shout_cooldown = maxf(0.0, _shout_cooldown - delta)
	
	# Procura alvos prioritários: policiais invasores ou o jogador
	if not is_instance_valid(combat_target) or combat_target.get("is_dead") == true:
		# 1. Prioriza policiais entrando no território dos Cobras
		for cop in get_tree().get_nodes_in_group("police_officer"):
			if is_instance_valid(cop) and not (cop.get("is_dead") == true):
				if global_position.distance_to(cop.global_position) < guard_radius * 1.2:
					combat_target = cop
					_shout_gang_bark("POLÍCIA NO NOSSO BECO! FOGO NELES!")
					break

		# 2. Se não há policiais, vigia o Dante
		if not is_instance_valid(combat_target):
			var player = get_tree().get_first_node_in_group("player")
			if is_instance_valid(player):
				var dist = global_position.distance_to(player.global_position)
				if dist < guard_radius:
					combat_target = player
					_shout_gang_bark("AQUI É OS COBRAS DE FERRO! SAI DO BECO!")
	
	super._physics_process(delta)
	
	# Se estiver longe do posto de guarda e sem alvo, retorna suavemente
	if not is_instance_valid(combat_target) and global_position.distance_to(guard_center) > guard_radius:
		walk_target = guard_center + Vector2(randf_range(-40, 40), randf_range(-40, 40))

func _shout_gang_bark(specific_text: String = "") -> void:
	if _shout_cooldown > 0.0: return
	_shout_cooldown = 4.0
	var text_to_show = specific_text
	if text_to_show.is_empty():
		var barks = [
			"AQUI É OS COBRAS DE FERRO!",
			"MEXEU COM O BONDE ERRADO!",
			"LARGA O V8 OU MORRE!",
			"DERRUBA ELE!"
		]
		text_to_show = barks[randi() % barks.size()]
	_spawn_speech_bubble(text_to_show, Color("#ff4757"))

func _spawn_speech_bubble(text_msg: String, text_color: Color) -> void:
	var label = Label.new()
	label.text = text_msg
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-75, -55)
	label.size = Vector2(150, 20)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	
	var tw = create_tween()
	tw.tween_property(label, "position:y", -72.0, 2.2)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 2.2)
	tw.tween_callback(label.queue_free)
