extends Area2D

@export var enter_distance: float = 38.0
@export var exit_distance: float = 55.0

var is_busy: bool = false

@onready var shutter: Control = get_node_or_null("ShutterClip/ShutterSprite")
@onready var interior: ColorRect = get_node_or_null("Interior")

func _ready():
	body_entered.connect(_on_body_entered)
	if shutter:
		shutter.position.y = 0.0
	if interior:
		interior.visible = false

func _open_door(duration: float = 0.6) -> Tween:
	if interior:
		interior.visible = true
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if shutter:
		tween.tween_property(shutter, "position:y", -52.0, duration)
	return tween

func _close_door(duration: float = 0.5) -> Tween:
	var tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	if shutter:
		tween.tween_property(shutter, "position:y", 0.0, duration)
	tween.tween_callback(func():
		if interior: interior.visible = false
	)
	return tween

func _on_body_entered(body: Node2D):
	if is_busy:
		return
	
	if body.is_in_group("vehicle") and body.get("is_driven_by_player") == true:
		is_busy = true
		
		# 1. Trava os controles e zera a velocidade
		body.set_physics_process(false)
		body.velocity = Vector2.ZERO
		
		# 2. Alinhamento Perfeito com o vão da porta (-PI/2 e eixo X da garagem)
		var align_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var target_x = global_position.x
		var prep_pos = Vector2(target_x, maxf(body.global_position.y, global_position.y + 12.0))
		
		align_tween.tween_property(body, "rotation", -PI * 0.5, 0.5)
		align_tween.parallel().tween_property(body, "global_position", prep_pos, 0.5)
		
		# 3. Abre a persiana de enrolar (subindo a textura original)
		align_tween.tween_callback(func(): _open_door(0.6))
		align_tween.tween_interval(0.6)
		
		# 4. Carro entra suavemente e desaparece no interior
		var inside_pos = Vector2(target_x, global_position.y - enter_distance)
		align_tween.tween_property(body, "global_position", inside_pos, 0.8)
		align_tween.parallel().tween_property(body, "modulate:a", 0.0, 0.6)
		
		# 5. Fecha a porta atrás do carro
		align_tween.tween_callback(func(): _close_door(0.5))
		align_tween.tween_interval(0.5)
		
		# 6. Efeito sonoro de pintura spray "Tsssssh"
		align_tween.tween_callback(func(): _play_spray_sound())
		align_tween.tween_interval(1.2)
		
		# 7. Executa o reparo e repintura
		align_tween.tween_callback(func(): _process_repair(body))

func _play_spray_sound() -> void:
	var player = AudioStreamPlayer.new()
	player.stream = ProceduralAudio.get_skid_stream() # Modulado para simular jato de spray
	player.pitch_scale = 2.4
	player.volume_db = -10.0
	add_child(player)
	player.play()
	var t = create_tween()
	t.tween_interval(0.9)
	t.tween_callback(player.queue_free)

func _process_repair(body: Node2D):
	var wm = get_node_or_null("/root/WantedManager")
	if wm:
		if wm.has_method("clear_wanted_level"):
			wm.clear_wanted_level()
		elif wm.has_method("reset_crime"):
			wm.reset_crime()
	
	if body.has_method("repair_and_repaint"):
		body.repair_and_repaint()
	elif body.has_method("repair_vehicle"):
		body.repair_vehicle()
	elif "health" in body:
		body.health = 100
		if "is_broken" in body:
			body.is_broken = false
			
	# 1. Verifica se o carro é uma das encomendas da Lousa de 60 Segundos
	var player = get_tree().get_first_node_in_group("player")
	var chalkboard = get_tree().get_first_node_in_group("car_chalkboard")
	if chalkboard and is_instance_valid(player):
		var res = chalkboard.try_deliver_vehicle(body, player)
		if res.get("success", false) == true:
			var hud = get_tree().get_first_node_in_group("hud")
			if hud and hud.has_method("show_notice"):
				hud.show_notice("📋 ENCOMENDA ENTREGUE: %s (+$%d)" % [res["name"], res["reward"]])
				
	# 2. Abre o menu interativo estilo GTA V / Los Santos Customs do Mano Otto
	var workshop := CustomsWorkshopMenu.new()
	get_tree().current_scene.add_child(workshop)
	workshop.setup_workshop(body, player)
	workshop.workshop_closed.connect(func(_data):
		_exit_garage(body)
	)

func _exit_garage(body: Node2D):
	var exit_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# Abre a porta
	exit_tween.tween_callback(func(): _open_door(0.6))
	exit_tween.tween_interval(0.5)
	
	# Carro reaparece restaurado e sai em marcha ré para a rua
	var target_x = global_position.x
	var outside_pos = Vector2(target_x, global_position.y + exit_distance)
	exit_tween.tween_property(body, "modulate:a", 1.0, 0.4)
	exit_tween.tween_property(body, "global_position", outside_pos, 1.1)
	
	# Garante escala restaurada
	exit_tween.parallel().tween_property(body, "scale", Vector2.ONE, 1.1)
	
	# Fecha a porta
	exit_tween.tween_callback(func(): _close_door(0.5))
	exit_tween.tween_interval(0.4)
	
	# Restaura os controles
	exit_tween.tween_callback(func():
		body.set_physics_process(true)
		is_busy = false
	)
