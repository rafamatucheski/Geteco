class_name CarjackedDriver
extends CharacterBody2D

enum Personality { SUBMISSIVE, CALL_POLICE, FIGHTER }

@export var personality: Personality = Personality.SUBMISSIVE

var stolen_vehicle: Node2D = null
var health: int = 50
var is_dead: bool = false
var fall_presentation := preload("res://CharacterFallPresentation.gd").new()
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
	shape.radius = 8.0
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
	if is_instance_valid(driver_model) and "taxi" in String(vehicle.get("vehicle_id")):
		var detail := preload("res://world/shared/pedestrians/CitizenDetails.gd")
		detail.piece(driver_model,Vector3(.36,.11,.31),Vector3(0,1.79,0),Color("b59855"),true)
		detail.piece(driver_model,Vector3(.27,.025,.15),Vector3(0,1.75,.16),Color("b59855"))
		detail.piece(driver_model,Vector3(.08,.10,.03),Vector3(.12,1.24,.18),Color("e6dfc8"))
		driver_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
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
		fall_presentation.update(delta)
		return

	state_timer += delta
	_age += delta
	if _age > 12 and not civilian_routine: _begin_civilian_routine()
	if civilian_routine:
		_update_civilian_routine(delta)
		return

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
		var effects := get_tree().get_first_node_in_group("weapon_effects")
		if effects: effects.spawn_blood(global_position,Vector2.UP,amount)
		var t = create_tween()
		fall_presentation.start(self, driver_model, driver_viewport)
		t.tween_interval(2.0)
		t.tween_property(self, "modulate:a", 0.0, 3.0)
		t.tween_callback(queue_free)

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	take_damage(100, true)
	velocity = impact_velocity * 0.5
	move_and_slide()

func _fade_and_despawn() -> void:
	_begin_civilian_routine()

# Paleta curada de roupas -- antes era RGB 100% aleatorio (cada canal solto
# entre 0.2 e 0.9), o que gerava combinacoes neon/feias (o "roxo horroroso"
# reportado). Mesma ideia da paleta de skin_tones/hair_tones que
# AnimatedPedestrian3D.gd ja usa para as NPCs com rig 3D.
const DRIVER_SHIRT_COLORS: Array[Color] = [
	Color("e17055"), Color("0984e3"), Color("00b894"), Color("fdcb6e"),
	Color("636e72"), Color("6c5ce7"), Color("d63031"), Color("2d3436"),
	Color("00cec9"), Color("b2bec3"),
]

var driver_viewport: SubViewport
var driver_model: Node3D
var _render_clock := 0.0
var civilian_routine := false
var _routine_points: Array[Vector2] = []
var _routine_index := 0
var _routine_wait := 0.0
var _age := 0.0

func _build_driver_visual() -> void:
	shirt_color = Color("39835a")
	driver_viewport = SubViewport.new()
	driver_viewport.name = "Driver3DRender"
	driver_viewport.size = Vector2i(128,128)
	driver_viewport.own_world_3d = true
	driver_viewport.transparent_bg = true
	driver_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(driver_viewport)
	driver_model = preload("res://prototypes/living_cast/CivilianDriverModel.gd").new()
	driver_viewport.add_child(driver_model)
	driver_model.set_process(false)
	var camera := Camera3D.new()
	driver_viewport.add_child(camera)
	camera.position = Vector3(0,4,3)
	camera.look_at(Vector3(0,0.9,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-25,0)
	sun.light_energy = 1.5
	driver_viewport.add_child(sun)
	var sprite := Sprite2D.new()
	sprite.texture = driver_viewport.get_texture()
	sprite.scale = Vector2.ONE*(15.0*2.6/128.0)
	sprite.position = (Vector2(64,64)-camera.unproject_position(Vector3.ZERO))*sprite.scale
	visual_root.add_child(sprite)

func _process(delta: float) -> void:
	if not is_instance_valid(driver_model): return
	visual_root.global_rotation = 0
	if speech_bubble: speech_bubble.rotation = -global_rotation
	if phone_indicator: phone_indicator.rotation = -global_rotation
	var visible_now := get_viewport().get_visible_rect().grow(100).has_point(get_canvas_transform()*global_position)
	if not visible_now:
		driver_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_render_clock += delta
	if _render_clock < 1.0/20.0: return
	driver_model.walking = not is_dead and velocity.length()>2
	if not is_dead: driver_model.rotation.y = -global_rotation + PI*0.5
	if not is_dead: driver_model._process(_render_clock)
	_render_clock = 0
	driver_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _begin_civilian_routine() -> void:
	if civilian_routine or is_dead: return
	civilian_routine = true
	if phone_indicator: phone_indicator.hide()
	var nearest := INF
	var entry := global_position
	for resident in get_tree().get_nodes_in_group("authored_sidewalk_pedestrian"):
		for i in range(resident.route_points.size()-1):
			var a: Vector2 = resident.get_parent().to_global(resident.route_points[i])
			var b: Vector2 = resident.get_parent().to_global(resident.route_points[i+1])
			var point := Geometry2D.get_closest_point_to_segment(global_position,a,b)
			var distance := global_position.distance_squared_to(point)
			if distance < nearest and distance < 800*800:
				nearest = distance
				entry = point
				_routine_points = [a,b]
	if _routine_points.is_empty(): _routine_points = [global_position+Vector2(-40,0),global_position+Vector2(40,0)]
	_routine_points.push_front(entry)
	_routine_index = 0
	show_speech("Preciso sair daqui e pedir ajuda.",3.0)

func _update_civilian_routine(delta: float) -> void:
	_routine_wait = maxf(0,_routine_wait-delta)
	if _routine_wait>0:
		velocity = Vector2.ZERO
		return
	var point := _routine_points[_routine_index]
	if global_position.distance_to(point)<8:
		_routine_index = 1 if _routine_index==2 else _routine_index+1
		_routine_wait = randf_range(1.0,3.0)
		return
	velocity = global_position.direction_to(point)*42
	rotation = velocity.angle()
	move_and_slide()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if _age>60 and is_instance_valid(player) and player.global_position.distance_to(global_position)>1800:
		queue_free()

func _setup_speech_bubble() -> void:
	speech_bubble = PanelContainer.new()
	speech_bubble.position = Vector2(-115, -68)
	speech_bubble.custom_minimum_size = Vector2(230, 36)
	speech_bubble.visible = false
	speech_bubble.z_index = 25
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	style.border_color = Color(0.95, 0.75, 0.20)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	speech_bubble.add_theme_stylebox_override("panel", style)
	
	speech_label = Label.new()
	speech_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speech_label.add_theme_font_size_override("font_size", 13)
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
