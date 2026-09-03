class_name SpikeStrip
extends Area2D

## Fita de Pregos Policial ("Jacaré" / Road Spike Strip)
## Lançada pela polícia em perseguições de alto nível (3+ estrelas) para furar pneus de veículos.
## Carros com Pneus Anti-Furo (Kevlar) passam por cima destruindo a fita e mantendo velocidade máxima!

var is_triggered: bool = false
var strobe_light: PointLight2D
var _clock: float = 0.0

func _ready() -> void:
	z_index = 3
	collision_layer = 0
	collision_mask = 1 # Detecta veículos
	add_to_group("spike_strip")
	
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(96, 20)
	col.shape = shape
	add_child(col)
	
	_build_visuals()
	body_entered.connect(_on_body_entered)
	
	# Desaparece suavemente após 40s se não atingida
	var tw = create_tween()
	tw.tween_interval(32.0)
	tw.tween_property(self, "modulate:a", 0.0, 8.0)
	tw.tween_callback(queue_free)

func _build_visuals() -> void:
	# Base metálica sanfonada de aço escuro
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-48, -8), Vector2(48, -8), Vector2(48, 8), Vector2(-48, 8)
	])
	base.color = Color("#2d3436")
	add_child(base)
	
	# Faixas zebradas de alerta amarelo e preto
	for i in range(8):
		var x = -42.0 + float(i * 12)
		var stripe = Line2D.new()
		stripe.width = 3.0
		stripe.default_color = Color("#f1c40f") if i % 2 == 0 else Color("#1e272e")
		stripe.add_point(Vector2(x, -7))
		stripe.add_point(Vector2(x + 5, 7))
		add_child(stripe)
		
	# Estacas pontiagudas de aço prateado afiado
	for p in range(10):
		var px = -44.0 + float(p * 9.5)
		var spike = Polygon2D.new()
		spike.polygon = PackedVector2Array([
			Vector2(px - 2, 4), Vector2(px + 2, 4), Vector2(px, -9)
		])
		spike.color = Color("#bdc3c7")
		add_child(spike)

func _process(delta: float) -> void:
	_clock += delta * 8.0
	queue_redraw()

func _draw() -> void:
	# LED vermelho piscante da fita de pregos
	var strobe_on = int(_clock) % 2 == 0
	if strobe_on:
		draw_circle(Vector2(-42, 0), 4.0, Color(1.0, 0.2, 0.2, 0.9))
		draw_circle(Vector2(42, 0), 4.0, Color(1.0, 0.2, 0.2, 0.9))

func _on_body_entered(body: Node2D) -> void:
	if is_triggered: return
	if not body.is_in_group("vehicle"): return
	
	is_triggered = true
	
	var has_kevlar: bool = body.get("has_puncture_proof_tires") == true
	
	if has_kevlar:
		# Pneus Blindados Anti-Furo (Kevlar / Run-Flat) protegem o carro!
		var p = AudioStreamPlayer2D.new()
		p.stream = ProceduralAudio.get_ricochet_stream()
		p.pitch_scale = 0.7
		p.volume_db = 0.0
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)
		
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_notice"):
			hud.show_notice("🛡️ PNEUS KEVLAR ANTI-FURO: PREGOS ABSORVIDOS!")
	else:
		# Fura os pneus do carro!
		if body.has_method("puncture_tires"):
			body.puncture_tires()
		else:
			body.set("has_punctured_tires", true)
			if "max_speed" in body:
				body.max_speed *= 0.45
			if "acceleration" in body:
				body.acceleration *= 0.50
				
		var p = AudioStreamPlayer2D.new()
		p.stream = ProceduralAudio.get_tire_pop_stream()
		p.volume_db = 2.0
		p.max_distance = 600.0
		get_tree().current_scene.add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)
		
		var hud = get_tree().get_first_node_in_group("hud")
		if hud and hud.has_method("show_notice"):
			hud.show_notice("⚠️ PNEU FURADO! PERDA SEVERA DE VELOCIDADE E TRAÇÃO!")

	# Destrói a fita de pregos com esmagamento e faíscas
	var tw = create_tween().set_parallel(true)
	tw.tween_property(self, "scale:y", 0.1, 0.25)
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(queue_free)
