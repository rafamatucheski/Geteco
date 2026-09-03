class_name IronCobraCulDeSac
extends Node2D

## Cul-de-Sac dos Cobras de Ferro (Território Hostil / No-Go Zone)
## Rua circular sem saída estilo Grove Street (GTA San Andreas) com asfalto marcado,
## brasão de serpente, tambores de fogo fumegantes, barricadas e esquadrão armado.

const CENTER_POS := Vector2(610, 205)
const CULDESAC_RADIUS := 72.0
const TERRITORY_BOUNDS := Rect2(480, 90, 290, 310)

var territory_area: Area2D
var burning_barrel_1: Node2D
var burning_barrel_2: Node2D
var active_gangsters: Array[IronCobraMember] = []
var max_patrol: int = 5
var respawn_timer: float = 0.0

var hud_warning_active: bool = false
var alert_stinger_played: bool = false

func _ready() -> void:
	z_index = 1
	position = CENTER_POS
	add_to_group("no_go_zone")
	add_to_group("iron_cobra_territory")
	
	_create_hostile_trigger()
	_create_burning_barrels()
	_create_barricades_and_cover()
	_spawn_initial_squad()
	queue_redraw()

func _draw() -> void:
	# 1. Asfalto de Acesso (Rua conectando a Avenida ao Cul-de-Sac)
	var access_road = Rect2(Vector2(-10, -28), Vector2(180, 56))
	draw_rect(access_road, Color("#18191c"))
	draw_line(Vector2(0, -28), Vector2(170, -28), Color("#57606f"), 3.0)
	draw_line(Vector2(0, 28), Vector2(170, 28), Color("#57606f"), 3.0)

	# 2. Círculo do Cul-de-Sac (Rua Redonda estilo GTA San Andreas)
	draw_circle(Vector2.ZERO, CULDESAC_RADIUS + 6.0, Color("#57606f")) # Meio-fio de concreto
	draw_circle(Vector2.ZERO, CULDESAC_RADIUS, Color("#141416"))       # Asfalto escuro
	
	# Faixas de zebra na borda da calçada circular
	var steps := 24
	for i in range(steps):
		var ang := (float(i) / float(steps)) * TAU
		var p1 := Vector2.RIGHT.rotated(ang) * (CULDESAC_RADIUS - 2.0)
		var p2 := Vector2.RIGHT.rotated(ang) * (CULDESAC_RADIUS + 4.0)
		var col := Color("#e74c3c") if i % 2 == 0 else Color("#f5f6fa")
		draw_line(p1, p2, col, 3.0)

	# 3. Grande Brasão Central de Serpente / Pichação de Chão
	_draw_cobra_emblem()

	# 4. Pichações de Asfalto e Tags da Gangue
	_draw_asphalt_graffiti()

func _draw_cobra_emblem() -> void:
	# Círculo vermelho de fundo
	draw_circle(Vector2.ZERO, 34.0, Color(0.35, 0.02, 0.04, 0.85))
	draw_arc(Vector2.ZERO, 34.0, 0, TAU, 32, Color("#800000"), 3.0)
	
	# Corpo estilizado da cobra em forma de 'S' agressivo
	var snake_body = PackedVector2Array([
		Vector2(0, -22), Vector2(12, -14), Vector2(14, -2), Vector2(4, 8),
		Vector2(-12, 14), Vector2(-10, 22), Vector2(0, 24), Vector2(8, 20)
	])
	draw_polyline(snake_body, Color("#e74c3c"), 6.0)
	
	# Cabeça de Naja e Presas
	draw_circle(Vector2(0, -22), 8.0, Color("#ff4757"))
	draw_line(Vector2(-3, -20), Vector2(-3, -13), Color.WHITE, 2.0) # Presa L
	draw_line(Vector2(3, -20), Vector2(3, -13), Color.WHITE, 2.0)  # Presa R
	
	# Olhos amarelos brilhantes
	draw_circle(Vector2(-3, -24), 2.0, Color("#f1c40f"))
	draw_circle(Vector2(3, -24), 2.0, Color("#f1c40f"))

func _draw_asphalt_graffiti() -> void:
	# Linhas marcando o território
	draw_line(Vector2(95, -24), Vector2(95, 24), Color("#800000"), 4.0)

func _create_hostile_trigger() -> void:
	territory_area = Area2D.new()
	territory_area.name = "HostileTerritoryTrigger"
	territory_area.collision_layer = 0
	territory_area.collision_mask = 7 # Detecta Jogador, Veículos e Policiais
	
	var col = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 160.0
	col.shape = circle
	territory_area.add_child(col)
	
	territory_area.body_entered.connect(_on_body_entered_territory)
	territory_area.body_exited.connect(_on_body_exited_territory)
	add_child(territory_area)

func _create_burning_barrels() -> void:
	burning_barrel_1 = _make_barrel_node(Vector2(-42, -32))
	add_child(burning_barrel_1)
	
	burning_barrel_2 = _make_barrel_node(Vector2(-38, 38))
	add_child(burning_barrel_2)

func _make_barrel_node(at: Vector2) -> Node2D:
	var barrel = Node2D.new()
	barrel.position = at
	
	# Tambor metálico escuro
	var drum = Polygon2D.new()
	drum.polygon = PackedVector2Array([
		Vector2(-7, -7), Vector2(7, -7), Vector2(7, 7), Vector2(-7, 7)
	])
	drum.color = Color("#2f3542")
	barrel.add_child(drum)
	
	# Partículas de Fogo & Brasas
	var fire_particles = CPUParticles2D.new()
	fire_particles.amount = 22
	fire_particles.lifetime = 0.65
	fire_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	fire_particles.emission_rect_extents = Vector2(5, 5)
	fire_particles.gravity = Vector2(0, -110)
	fire_particles.direction = Vector2(0, -1)
	fire_particles.spread = 25.0
	fire_particles.initial_velocity_min = 35.0
	fire_particles.initial_velocity_max = 75.0
	fire_particles.scale_amount_min = 2.0
	fire_particles.scale_amount_max = 4.5
	fire_particles.color = Color("#ff6b6b")
	barrel.add_child(fire_particles)
	
	# Brilho de Luz de Fogo Quente
	var glow = Polygon2D.new()
	glow.polygon = PackedVector2Array([
		Vector2(-18, -18), Vector2(18, -18), Vector2(18, 18), Vector2(-18, 18)
	])
	glow.color = Color(1.0, 0.45, 0.1, 0.18)
	barrel.add_child(glow)
	
	var tw = barrel.create_tween().set_loops()
	tw.tween_property(glow, "scale", Vector2(1.25, 1.25), 0.18)
	tw.tween_property(glow, "scale", Vector2(0.85, 0.85), 0.18)
	
	return barrel

func _create_barricades_and_cover() -> void:
	# Pilha de Pneus de Cobertura
	var tire_stack = Polygon2D.new()
	tire_stack.position = Vector2(85, -28)
	tire_stack.polygon = PackedVector2Array([
		Vector2(-6, -10), Vector2(6, -10), Vector2(6, 10), Vector2(-6, 10)
	])
	tire_stack.color = Color("#111113")
	add_child(tire_stack)

func _spawn_initial_squad() -> void:
	var spawn_offsets := [
		Vector2(-35, -15), Vector2(-20, 28), Vector2(25, -24),
		Vector2(10, 32), Vector2(70, 0)
	]
	for i in range(mini(max_patrol, spawn_offsets.size())):
		var member = IronCobraMember.new()
		member.global_position = global_position + spawn_offsets[i]
		member.guard_center = global_position
		member.guard_radius = 150.0
		get_parent().call_deferred("add_child", member)
		active_gangsters.append(member)

func _process(delta: float) -> void:
	# Limpa instâncias destruídas/mortas
	var alive_count = 0
	for i in range(active_gangsters.size() - 1, -1, -1):
		var g = active_gangsters[i]
		if not is_instance_valid(g) or (g.get("is_dead") == true):
			active_gangsters.remove_at(i)
		else:
			alive_count += 1
			
	# Repopula patrulha se estiver abaixo do limite
	if alive_count < max_patrol:
		respawn_timer += delta
		if respawn_timer > 9.0:
			respawn_timer = 0.0
			var member = IronCobraMember.new()
			member.global_position = global_position + Vector2(randf_range(-40, 40), randf_range(-40, 40))
			member.guard_center = global_position
			member.guard_radius = 150.0
			get_parent().add_child(member)
			active_gangsters.append(member)

func _on_body_entered_territory(body: Node2D) -> void:
	if body.is_in_group("player"):
		_show_hud_warning("⚠️ TERRITÓRIO HOSTIL: OS COBRAS DE FERRO (NO-GO ZONE)")
		# Alerta todos os membros da gangue para vigiar
		for g in active_gangsters:
			if is_instance_valid(g) and not (g.get("is_dead") == true):
				g.combat_target = body
				g._shout_gang_bark("INVADIU O CÍRCULO DOS COBRAS! DERRUBA!")
	elif body.is_in_group("police_officer"):
		# Ataque imediato contra policiais
		for g in active_gangsters:
			if is_instance_valid(g) and not (g.get("is_dead") == true):
				g.combat_target = body
				g._shout_gang_bark("POLÍCIA NA NOSSA QUEBRADA! FOGO!")

func _on_body_exited_territory(body: Node2D) -> void:
	if body.is_in_group("player"):
		_hide_hud_warning()

func _show_hud_warning(text_msg: String) -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("show_notice"):
		hud.show_notice(text_msg)
		
	var mm = get_tree().get_first_node_in_group("mission_manager")
	if mm and "banner_panel" in mm and mm.banner_panel:
		if mm.current_state == 0: # INACTIVE
			mm.banner_panel.visible = true
			mm.objective_label.text = "⚠️ TERRITÓRIO HOSTIL"
			mm.objective_label.add_theme_color_override("font_color", Color("#ff4757"))
			mm.subtitle_label.text = "OS COBRAS DE FERRO - A POLÍCIA NÃO ENTRA AQUI!"

func _hide_hud_warning() -> void:
	var mm = get_tree().get_first_node_in_group("mission_manager")
	if mm and "banner_panel" in mm and mm.banner_panel:
		if mm.current_state == 0:
			mm.banner_panel.visible = false
