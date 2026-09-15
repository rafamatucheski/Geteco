class_name DanteRealPlayerComparisonScene
extends Node2D

## Cena de Comparação do Protótipo Dante CGI v2 com a Instância REAL do Player de Produção.
## NÃO usa réplicas: instancia diretamente load("res://characters/Player.gd").new() sem alterar Player.gd.
## Comprova paridade em escala real de gameplay (1:1), turnaround 360° e estados de animação.

var real_player_gameplay: CharacterBody2D
var cgi_dante_gameplay: DanteCGIModel

var turn_instances_real: Array[CharacterBody2D] = []
var turn_instances_cgi: Array[DanteCGIModel] = []

var anim_real: Dictionary = {}
var anim_cgi: Dictionary = {}

var clock: float = 0.0

func _ready() -> void:
	_build_background()
	_setup_section1_gameplay_scale()
	_setup_section2_turnaround()
	_setup_section3_animations()
	_build_metrics_hud()

func _build_background() -> void:
	var bg := Polygon2D.new()
	bg.color = Color("#0e1116")
	bg.polygon = PackedVector2Array([
		Vector2(-2000, -1500), Vector2(2000, -1500),
		Vector2(2000, 1500), Vector2(-2000, 1500)
	])
	bg.z_index = -10
	add_child(bg)

	# Linhas de grade técnica de referência
	var grid := Line2D.new()
	grid.default_color = Color(0.18, 0.22, 0.28, 0.40)
	grid.width = 1.0
	for y in range(-340, 360, 60):
		var line := Line2D.new()
		line.points = PackedVector2Array([Vector2(-620, y), Vector2(620, y)])
		line.width = 1.0
		line.default_color = Color(0.16, 0.20, 0.26, 0.40)
		add_child(line)

func _create_real_player(parent: Node2D, pos: Vector2, scale_2d: Vector2) -> CharacterBody2D:
	var player_script = load("res://characters/Player.gd")
	var p: CharacterBody2D = player_script.new()
	p.name = "RealPlayerInstance"
	p.position = pos

	# Adiciona Camera dummy para satisfazer @onready var camera = $Camera de Player.gd
	var cam := Camera2D.new()
	cam.name = "Camera"
	cam.enabled = false
	p.add_child(cam)

	parent.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)

	# Ajustar escala do sprite 2D
	if p.sprite_3d_display:
		p.sprite_3d_display.scale = scale_2d

	return p

func _create_cgi_dante(parent: Node2D, pos: Vector2, scale_2d: Vector2) -> DanteCGIModel:
	var dante := DanteCGIModel.new()
	dante.position = pos
	dante.render_scale = scale_2d
	parent.add_child(dante)
	return dante

func _setup_section1_gameplay_scale() -> void:
	# Painel Esquerdo: Escala Real de Gameplay (1:1, scale 0.38)
	var sec_title := Label.new()
	sec_title.text = "1. TAMANHO REAL DO GAMEPLAY (1:1 - ESCALA 0.38)"
	sec_title.position = Vector2(-580, -325)
	sec_title.size = Vector2(400, 24)
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#f1c40f"))
	add_child(sec_title)

	# Calçada urbana sob os pés
	var sidewalk := Polygon2D.new()
	sidewalk.color = Color("#2c3440")
	sidewalk.polygon = PackedVector2Array([
		Vector2(-580, -220), Vector2(-220, -220),
		Vector2(-220, -170), Vector2(-580, -170)
	])
	add_child(sidewalk)

	var curb := Line2D.new()
	curb.points = PackedVector2Array([Vector2(-580, -170), Vector2(-220, -170)])
	curb.width = 3.0
	curb.default_color = Color("#85929e")
	add_child(curb)

	# Instância do PLAYER REAL
	real_player_gameplay = _create_real_player(self, Vector2(-490, -200), Vector2(0.38, 0.38))
	var lbl_real := Label.new()
	lbl_real.text = "PLAYER REAL\n(Produção Atual)"
	lbl_real.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_real.position = Vector2(-560, -160)
	lbl_real.size = Vector2(140, 32)
	lbl_real.add_theme_font_size_override("font_size", 9)
	lbl_real.add_theme_color_override("font_color", Color("#bdc3c7"))
	add_child(lbl_real)

	# Instância do DANTE CGI v2
	cgi_dante_gameplay = _create_cgi_dante(self, Vector2(-310, -200), Vector2(0.38, 0.38))
	cgi_dante_gameplay.facing_angle = PI
	var lbl_cgi := Label.new()
	lbl_cgi.text = "DANTE CGI v2\n(Jaqueta Xadrez / Henley)"
	lbl_cgi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_cgi.position = Vector2(-380, -160)
	lbl_cgi.size = Vector2(140, 32)
	lbl_cgi.add_theme_font_size_override("font_size", 9)
	lbl_cgi.add_theme_color_override("font_color", Color("#2ecc71"))
	add_child(lbl_cgi)

	# Inspeção Ampliada (2.0x) em pedestais
	var insp_title := Label.new()
	insp_title.text = "INSPEÇÃO DETALHADA (AMPLIAÇÃO 2.0x)"
	insp_title.position = Vector2(-580, -110)
	insp_title.size = Vector2(400, 20)
	insp_title.add_theme_font_size_override("font_size", 10)
	insp_title.add_theme_color_override("font_color", Color("#e67e22"))
	add_child(insp_title)

	var p_real_big := _create_real_player(self, Vector2(-490, 0), Vector2(0.76, 0.76))
	var p_cgi_big := _create_cgi_dante(self, Vector2(-310, 0), Vector2(0.76, 0.76))
	p_cgi_big.facing_angle = PI

func _setup_section2_turnaround() -> void:
	var sec_title := Label.new()
	sec_title.text = "2. TURNAROUND SINCRONIZADO 360° (PLAYER REAL vs DANTE CGI v2)"
	sec_title.position = Vector2(-180, -325)
	sec_title.size = Vector2(500, 24)
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#f1c40f"))
	add_child(sec_title)

	var angles = [
		{"name": "FRENTE (180°)", "ang": PI, "x": -110},
		{"name": "PERFIL ESQ (90°)", "ang": PI * 0.5, "x": 60},
		{"name": "COSTAS (0°)", "ang": 0.0, "x": 230},
		{"name": "PERFIL DIR (-90°)", "ang": -PI * 0.5, "x": 400}
	]

	for item in angles:
		var lbl := Label.new()
		lbl.text = item.name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(item.x - 70, -295)
		lbl.size = Vector2(140, 20)
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color("#d5dbdb"))
		add_child(lbl)

		# Linha 1: Player Real (Y = -230)
		var pr := _create_real_player(self, Vector2(item.x, -240), Vector2(0.45, 0.45))
		if pr.model_root:
			pr.model_root.rotation.y = item.ang
		turn_instances_real.append(pr)

		# Linha 2: Dante CGI v2 (Y = -140)
		var pc := _create_cgi_dante(self, Vector2(item.x, -145), Vector2(0.45, 0.45))
		pc.facing_angle = item.ang
		turn_instances_cgi.append(pc)

	var lbl_row1 := Label.new()
	lbl_row1.text = "PLAYER REAL ▶"
	lbl_row1.position = Vector2(-200, -245)
	lbl_row1.size = Vector2(90, 20)
	lbl_row1.add_theme_font_size_override("font_size", 8)
	lbl_row1.add_theme_color_override("font_color", Color("#bdc3c7"))
	add_child(lbl_row1)

	var lbl_row2 := Label.new()
	lbl_row2.text = "DANTE CGI v2 ▶"
	lbl_row2.position = Vector2(-200, -150)
	lbl_row2.size = Vector2(90, 20)
	lbl_row2.add_theme_font_size_override("font_size", 8)
	lbl_row2.add_theme_color_override("font_color", Color("#2ecc71"))
	add_child(lbl_row2)

func _setup_section3_animations() -> void:
	var sec_title := Label.new()
	sec_title.text = "3. ESTADOS DE ANIMAÇÃO SINCRONIZADOS (PARADO / CAMINHADA / CORRIDA)"
	sec_title.position = Vector2(-180, -75)
	sec_title.size = Vector2(500, 24)
	sec_title.add_theme_font_size_override("font_size", 11)
	sec_title.add_theme_color_override("font_color", Color("#f1c40f"))
	add_child(sec_title)

	var states = [
		{"id": "idle", "name": "PARADO (IDLE)", "x": -80},
		{"id": "walk", "name": "CAMINHADA (WALK)", "x": 120},
		{"id": "run", "name": "CORRIDA (RUN)", "x": 320}
	]

	for st in states:
		var lbl := Label.new()
		lbl.text = st.name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.position = Vector2(st.x - 70, -45)
		lbl.size = Vector2(140, 20)
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color", Color("#d5dbdb"))
		add_child(lbl)

		# Linha de cima: Player Real
		var pr := _create_real_player(self, Vector2(st.x - 25, 10), Vector2(0.48, 0.48))
		if pr.model_root:
			pr.model_root.rotation.y = PI * 0.85
		anim_real[st.id] = pr

		# Linha de baixo: Dante CGI v2
		var pc := _create_cgi_dante(self, Vector2(st.x + 25, 10), Vector2(0.48, 0.48))
		pc.current_state = st.id
		pc.facing_angle = PI * 0.85
		anim_cgi[st.id] = pc

func _build_metrics_hud() -> void:
	# Medição real de nós e triângulos em runtime
	var cgi_stats: Dictionary = {}
	if cgi_dante_gameplay:
		cgi_stats = cgi_dante_gameplay.get_model_stats()

	var real_stats := _measure_node_stats(real_player_gameplay)

	var panel := Polygon2D.new()
	panel.color = Color(0.08, 0.10, 0.14, 0.95)
	panel.polygon = PackedVector2Array([
		Vector2(-580, 110), Vector2(580, 110),
		Vector2(580, 320), Vector2(-580, 320)
	])
	add_child(panel)

	var border := Line2D.new()
	border.points = panel.polygon
	border.width = 1.5
	border.default_color = Color("#34495e")
	add_child(border)

	var title := Label.new()
	title.text = "PAINEL TÉCNICO DE MEDIÇÃO REAL (COMPATIBILITY / OPENGL3)"
	title.position = Vector2(-560, 120)
	title.size = Vector2(500, 20)
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color("#f1c40f"))
	add_child(title)

	var t1 := Label.new()
	t1.text = "PLAYER REAL (Produção Atual):\n• Triângulos Medidos: %d tris\n• Nós MeshInstance3D: %d nós\n• Materiais Únicos: %d materiais\n• SubViewports Ativos: %d viewport\n• Rig: %s" % [
		real_stats.triangles, real_stats.meshes, real_stats.materials, real_stats.viewports, "Articulado 3D com PlayerCombatPose"
	]
	t1.position = Vector2(-560, 145)
	t1.size = Vector2(540, 100)
	t1.add_theme_font_size_override("font_size", 8)
	t1.add_theme_color_override("font_color", Color("#bdc3c7"))
	add_child(t1)

	var t2 := Label.new()
	t2.text = "DANTE CGI v2 (Novo Protótipo):\n• Triângulos Medidos: %d tris\n• Nós MeshInstance3D: %d nós\n• Materiais Únicos: %d materiais\n• SubViewports Ativos: %d viewport\n• Visual: Jaqueta Xadrez Escura + Henley Vinho + Ombros Retos" % [
		cgi_stats.get("triangle_count", 0), cgi_stats.get("mesh_count", 0), cgi_stats.get("materials_count", 0), cgi_stats.get("active_viewports", 0)
	]
	t2.position = Vector2(-10, 145)
	t2.size = Vector2(560, 100)
	t2.add_theme_font_size_override("font_size", 8)
	t2.add_theme_color_override("font_color", Color("#2ecc71"))
	add_child(t2)

	var t3 := Label.new()
	t3.text = "INCOMPATIBILIDADES IDENTIFICADAS / PENDÊNCIAS DE INTEGRAÇÃO:\n1. Sistema de Armas/Combate: PlayerCombatPose.gd possui offsets de encaixe específicos (grip points) nos nós de membros do Player.gd oficial.\n2. Sistema de Veículos: A rotina try_enter_vehicle() depende de nós de colisão e grupos que foram preservados intactos no Player de produção.\n3. Nenhuma substituição automática realizada. O Player de produção permanece 100% inalterado."
	t3.position = Vector2(-560, 245)
	t3.size = Vector2(1120, 65)
	t3.add_theme_font_size_override("font_size", 8)
	t3.add_theme_color_override("font_color", Color("#e74c3c"))
	add_child(t3)

func _measure_node_stats(root_node: Node) -> Dictionary:
	var tris := 0
	var meshes := 0
	var mats: Dictionary = {}
	var vps := 0

	if root_node:
		var stack: Array[Node] = [root_node]
		while not stack.is_empty():
			var curr: Node = stack.pop_back()
			if curr is SubViewport:
				vps += 1
			elif curr is MeshInstance3D:
				meshes += 1
				var mi = curr as MeshInstance3D
				var m = mi.mesh
				if m:
					var faces = m.get_faces()
					if faces.size() > 0:
						tris += faces.size() / 3
					elif m is BoxMesh:
						tris += 12
					elif m is CylinderMesh:
						tris += 128
					elif m is CapsuleMesh:
						tris += 192
					elif m is SphereMesh:
						tris += 160
				if mi.material_override:
					mats[mi.material_override.get_instance_id()] = true
			for ch in curr.get_children():
				stack.append(ch)

	return {
		"triangles": tris,
		"meshes": meshes,
		"materials": mats.size(),
		"viewports": vps
	}

func _process(delta: float) -> void:
	clock += delta

	# Animar Player Real no painel 3
	_animate_real_player(anim_real.get("idle"), "idle", clock)
	_animate_real_player(anim_real.get("walk"), "walk", clock)
	_animate_real_player(anim_real.get("run"), "run", clock)

	# Atualizar Player Real no painel 1
	_animate_real_player(real_player_gameplay, "idle", clock)

func _animate_real_player(p: CharacterBody2D, state: String, t: float) -> void:
	if not p: return

	match state:
		"idle":
			var breath := sin(t * 2.2)
			if p.torso_node: p.torso_node.position.y = 0.85 + breath * 0.005
			if p.head_node: p.head_node.position.y = 1.25 + breath * 0.008
			if p.combat_pose: p.combat_pose.update(p, 0.016, false, false, 0.0)

		"walk":
			var cycle := t * 7.5
			var s_leg := sin(cycle)
			var step_angle := s_leg * 0.36
			var arm_swing := -step_angle * 0.65
			var bobbing := absf(cos(cycle)) * 0.012

			if p.left_upper_leg and p.right_upper_leg:
				p.left_upper_leg.rotation.x = step_angle
				p.right_upper_leg.rotation.x = -step_angle
				if p.left_lower_leg and p.right_lower_leg:
					p.left_lower_leg.rotation.x = maxf(0.0, -step_angle * 0.70)
					p.right_lower_leg.rotation.x = maxf(0.0, step_angle * 0.70)

			if p.torso_node and p.head_node:
				p.torso_node.position.y = 0.85 + bobbing
				p.head_node.position.y = 1.25 + bobbing

			if p.combat_pose:
				p.combat_pose.update(p, 0.016, false, false, arm_swing)

		"run":
			var cycle := t * 12.0
			var s_leg := sin(cycle)
			var step_angle := s_leg * 0.50
			var arm_swing := -step_angle * 0.65
			var bobbing := absf(cos(cycle)) * 0.022

			if p.left_upper_leg and p.right_upper_leg:
				p.left_upper_leg.rotation.x = step_angle
				p.right_upper_leg.rotation.x = -step_angle
				if p.left_lower_leg and p.right_lower_leg:
					p.left_lower_leg.rotation.x = maxf(0.0, -step_angle * 0.70)
					p.right_lower_leg.rotation.x = maxf(0.0, step_angle * 0.70)

			if p.torso_node and p.head_node:
				p.torso_node.position.y = 0.85 + bobbing
				p.head_node.position.y = 1.25 + bobbing

			if p.combat_pose:
				p.combat_pose.update(p, 0.016, false, true, arm_swing)
