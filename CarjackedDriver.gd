class_name CarjackedDriver
extends CharacterBody2D

enum Personality { SUBMISSIVE, CALL_POLICE, FIGHTER }

@export var personality: Personality = Personality.SUBMISSIVE

var stolen_vehicle: Node2D = null
var health: int = 50
var is_dead: bool = false
var state_timer: float = 0.0
var phone_call_duration: float = 6.0
var phone_call_progress: float = 0.0
var has_called_police: bool = false

# Nós visuais e de interface
var visual_root: Node2D
var speech_bubble: PanelContainer
var speech_label: Label
var phone_indicator: PanelContainer
var phone_label: Label
var audio_player: AudioStreamPlayer2D

var shirt_color: Color = Color(0.2, 0.5, 0.8)
var pants_color: Color = Color(0.15, 0.15, 0.2)
var skin_color: Color = Color(0.85, 0.68, 0.55)

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("pedestrian")
	z_index = 10
	
	collision_layer = 4 # Pedestre
	collision_mask = 3 # Paredes & Carros

	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 12.0
	col.shape = shape
	add_child(col)

	# 1. Visual do Pedestre
	visual_root = Node2D.new()
	add_child(visual_root)
	_build_driver_visual()

	# 2. Áudio
	audio_player = AudioStreamPlayer2D.new()
	audio_player.max_distance = 600.0
	add_child(audio_player)

	# 3. Balão de Fala
	_setup_speech_bubble()

	# 4. Indicador de Chamada de Emergência
	_setup_phone_indicator()

func setup(vehicle: Node2D, spawn_pos: Vector2) -> void:
	stolen_vehicle = vehicle
	global_position = spawn_pos
	
	# Sorteia a personalidade
	var roll = randf()
	if roll < 0.35:
		personality = Personality.SUBMISSIVE
	elif roll < 0.75:
		personality = Personality.CALL_POLICE
	else:
		personality = Personality.FIGHTER

	# Ativa reação inicial
	match personality:
		Personality.SUBMISSIVE:
			var scared_phrases = [
				"Leva tudo! Não me machuca!",
				"Meu Deus! Por favor não atira!",
				"Que loucura! Socorro!"
			]
			show_speech(scared_phrases[randi() % scared_phrases.size()], 3.5)
		Personality.CALL_POLICE:
			var caller_phrases = [
				"Ei! Devolve meu carro! Vou chamar a polícia!",
				"Vou ligar pro 190 agora mesmo, seu bandido!",
				"Socorro! Roubaram meu carro!"
			]
			show_speech(caller_phrases[randi() % caller_phrases.size()], 3.0)
			phone_call_progress = phone_call_duration
			if phone_indicator: phone_indicator.visible = true
			if audio_player:
				audio_player.stream = ProceduralAudio.get_phone_dial_stream()
				audio_player.play()
		Personality.FIGHTER:
			var fight_phrases = [
				"Filho da mãe! Devolve meu carro agora!",
				"Você mexeu com o cara errado!",
				"Ladrão desgraçado! Sai do meu volante!"
			]
			show_speech(fight_phrases[randi() % fight_phrases.size()], 4.0)

func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return

	state_timer += delta

	# BUG REAL CORRIGIDO: speech_bubble/phone_indicator sao filhos deste
	# CharacterBody2D, entao quando "rotation" muda abaixo (o motorista vira
	# pra fugir), o balao de fala e o aviso "Ligando pra Policia..." giravam
	# junto -- um Label vira uma faixa diagonal gigante atravessando a tela.
	# Cancela a rotacao herdada todo frame para que essas UIs fiquem sempre
	# na horizontal, na tela, independente de para onde o NPC esta olhando.
	# NOTA: PanelContainer (Control) nao tem propriedade "global_rotation"
	# (isso so existe em Node2D) -- por isso setamos a rotacao LOCAL como o
	# inverso da rotacao global do proprio NPC, que cancela exatamente o
	# mesmo jeito, sem dar erro de tipo em runtime.
	if speech_bubble:
		speech_bubble.rotation = -global_rotation
	if phone_indicator:
		phone_indicator.rotation = -global_rotation

	match personality:
		Personality.SUBMISSIVE:
			# Foge desesperadamente na direção oposta ao carro
			if is_instance_valid(stolen_vehicle):
				var flee_dir = stolen_vehicle.global_position.direction_to(global_position).normalized()
				velocity = flee_dir * 140.0
				rotation = flee_dir.angle()
			move_and_slide()
			
			if state_timer >= 5.0:
				_fade_and_despawn()

		Personality.CALL_POLICE:
			# Recua devagar mantendo distância enquanto disca o telefone
			if is_instance_valid(stolen_vehicle):
				var dist = global_position.distance_to(stolen_vehicle.global_position)
				if dist < 120.0:
					var step_back = stolen_vehicle.global_position.direction_to(global_position).normalized()
					velocity = step_back * 70.0
					rotation = step_back.angle()
				else:
					velocity = Vector2.ZERO
				
				# Janela de fuga do jogador
				if dist > 520.0 and not has_called_police:
					# Jogador escapou antes do motorista completar a ligação!
					has_called_police = true
					show_speech("Droga, ele sumiu no trânsito!", 3.0)
					if phone_indicator: phone_indicator.visible = false
					_fade_and_despawn()
					return

			move_and_slide()

			# Contagem regressiva da ligação
			if not has_called_police and phone_call_progress > 0.0:
				phone_call_progress -= delta
				if phone_label:
					phone_label.text = "📱 [190] Ligando pra Polícia... %.1fs" % maxf(0.0, phone_call_progress)
				
				if phone_call_progress <= 0.0:
					has_called_police = true
					if phone_indicator: phone_indicator.visible = false
					show_speech("Alô Polícia? Roubaram meu carro aqui na avenida!", 3.5)
					
					# Dispara o sistema de Procurado (+1 estrela)
					var wanted = get_node_or_null("/root/WantedManager")
					if wanted:
						wanted.report_crime(20)
					
					# Despacha viatura policial
					if wanted and wanted.has_method("_dispatch_police"):
						wanted._dispatch_police()
						
					await get_tree().create_timer(4.0).timeout
					_fade_and_despawn()

		Personality.FIGHTER:
			# Corre furioso atrás do carro para bater no vidro ou tentar retomar
			if is_instance_valid(stolen_vehicle):
				var dist = global_position.distance_to(stolen_vehicle.global_position)
				var dir = global_position.direction_to(stolen_vehicle.global_position).normalized()
				rotation = dir.angle()

				if dist > 35.0 and dist < 380.0:
					velocity = dir * 180.0
					move_and_slide()
				elif dist <= 35.0:
					velocity = Vector2.ZERO
					# Desfere socos no carro
					if state_timer > 0.8:
						state_timer = 0.0
						if audio_player:
							audio_player.stream = ProceduralAudio.get_punch_whack_stream()
							audio_player.play()
						if stolen_vehicle.has_method("take_damage"):
							stolen_vehicle.take_damage(4)
						show_speech("Sai desse carro agora!", 1.5)
				else:
					# O carro acelerou muito longe, desiste cansado
					velocity = Vector2.ZERO
					show_speech("Na próxima você não me escapa!", 3.0)
					_fade_and_despawn()
			else:
				_fade_and_despawn()

func show_speech(text: String, duration: float = 3.0) -> void:
	if speech_label and speech_bubble:
		speech_label.text = text
		speech_bubble.visible = true
		var t = create_tween()
		t.tween_interval(duration)
		t.tween_callback(func():
			if speech_bubble: speech_bubble.visible = false
		)

func take_damage(amount: int, _is_player_attacker: bool = false) -> void:
	health -= amount
	if health <= 0 and not is_dead:
		is_dead = true
		if phone_indicator: phone_indicator.visible = false
		show_speech("Aaaagh!", 1.0)
		var t = create_tween()
		t.tween_property(visual_root, "rotation", PI * 0.5, 0.2)
		t.tween_property(self, "modulate:a", 0.0, 3.0)
		t.tween_callback(queue_free)

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	take_damage(100, true)
	velocity = impact_velocity * 0.5
	move_and_slide()

func _fade_and_despawn() -> void:
	var tw = create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(self, "modulate:a", 0.0, 1.5)
	tw.tween_callback(queue_free)

# Paleta curada de roupas -- antes era RGB 100% aleatorio (cada canal solto
# entre 0.2 e 0.9), o que gerava combinacoes neon/feias (o "roxo horroroso"
# reportado). Mesma ideia da paleta de skin_tones/hair_tones que
# AnimatedPedestrian3D.gd ja usa para as NPCs com rig 3D.
const DRIVER_SHIRT_COLORS: Array[Color] = [
	Color("e17055"), Color("0984e3"), Color("00b894"), Color("fdcb6e"),
	Color("636e72"), Color("6c5ce7"), Color("d63031"), Color("2d3436"),
	Color("00cec9"), Color("b2bec3"),
]

func _build_driver_visual() -> void:
	shirt_color = DRIVER_SHIRT_COLORS[randi() % DRIVER_SHIRT_COLORS.size()]

	# Bracos e pernas simples -- antes o "corpo" era so um retangulo achatado
	# (sem membro nenhum), o que junto com a cor aleatoria feia lia como um
	# borrao qualquer em vez de uma pessoa (bug real reportado: "esse NPC que
	# sai do carro horroroso").
	var arm_l = Polygon2D.new()
	arm_l.color = skin_color
	arm_l.polygon = PackedVector2Array([
		Vector2(-12, -10), Vector2(-8, -10), Vector2(-9, 13), Vector2(-13, 13)
	])
	visual_root.add_child(arm_l)

	var arm_r = Polygon2D.new()
	arm_r.color = skin_color
	arm_r.polygon = PackedVector2Array([
		Vector2(8, -10), Vector2(12, -10), Vector2(13, 13), Vector2(9, 13)
	])
	visual_root.add_child(arm_r)

	var leg_l = Polygon2D.new()
	leg_l.color = pants_color
	leg_l.polygon = PackedVector2Array([
		Vector2(-8, 12), Vector2(-1, 12), Vector2(-1, 20), Vector2(-8, 20)
	])
	visual_root.add_child(leg_l)

	var leg_r = Polygon2D.new()
	leg_r.color = pants_color
	leg_r.polygon = PackedVector2Array([
		Vector2(1, 12), Vector2(8, 12), Vector2(8, 20), Vector2(1, 20)
	])
	visual_root.add_child(leg_r)

	# Corpo do Pedestre Top-Down
	var body = Polygon2D.new()
	body.color = shirt_color
	body.polygon = PackedVector2Array([
		Vector2(-9, -14), Vector2(9, -14), Vector2(10, 14), Vector2(-10, 14)
	])
	visual_root.add_child(body)

	# Cabeça
	var head = Polygon2D.new()
	head.color = skin_color
	var head_pts = PackedVector2Array()
	for i in 12:
		var a = i * TAU / 12.0
		head_pts.append(Vector2(cos(a) * 7.5, sin(a) * 7.5))
	head.polygon = head_pts
	visual_root.add_child(head)

	# Cabelo
	var hair = Polygon2D.new()
	hair.color = Color(0.1, 0.08, 0.06)
	var hair_pts = PackedVector2Array()
	for i in 8:
		var a = (i + 2) * TAU / 12.0
		hair_pts.append(Vector2(cos(a) * 8.0, sin(a) * 8.0))
	hair.polygon = hair_pts
	visual_root.add_child(hair)

func _setup_speech_bubble() -> void:
	speech_bubble = PanelContainer.new()
	speech_bubble.position = Vector2(-90, -58)
	speech_bubble.custom_minimum_size = Vector2(180, 26)
	speech_bubble.visible = false
	speech_bubble.z_index = 25
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.92)
	style.border_color = Color(0.95, 0.75, 0.20)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	speech_bubble.add_theme_stylebox_override("panel", style)
	
	speech_label = Label.new()
	speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech_label.add_theme_font_size_override("font_size", 10)
	speech_label.add_theme_color_override("font_color", Color.WHITE)
	speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speech_bubble.add_child(speech_label)
	add_child(speech_bubble)

func _setup_phone_indicator() -> void:
	phone_indicator = PanelContainer.new()
	phone_indicator.position = Vector2(-100, -84)
	phone_indicator.custom_minimum_size = Vector2(200, 22)
	phone_indicator.visible = false
	phone_indicator.z_index = 26
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.75, 0.15, 0.15, 0.95)
	style.border_color = Color(1.0, 0.90, 0.20)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	phone_indicator.add_theme_stylebox_override("panel", style)
	
	phone_label = Label.new()
	phone_label.text = "📱 [190] Ligando pra Polícia... 6.0s"
	phone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phone_label.add_theme_font_size_override("font_size", 9)
	phone_label.add_theme_color_override("font_color", Color.WHITE)
	phone_indicator.add_child(phone_label)
	add_child(phone_indicator)
