class_name DanteComparisonScene
extends Node2D

## Cena de Comparação e Apresentação do Protótipo do Dante CGI
## Compara lado a lado com o Dante atual na escala real de gameplay (1:1),
## turnaround 360°, demonstração de animações e ficha técnica de renderização.

const DANTE_CGI := preload("res://prototypes/dante_cgi/DanteCGIModel.gd")
const DANTE_PROD := preload("res://prototypes/dante_cgi/DanteProductionComparisonModel.gd")

func _ready() -> void:
	_build_backdrop()
	_build_section_real_scale()
	_build_section_turnaround()
	_build_section_animations()
	_build_tech_specs_panel()

func _build_backdrop() -> void:
	# Fundo estúdio de apresentação em ardósia escura técnica
	var bg := ColorRect.new()
	bg.size = Vector2(1920, 1080)
	bg.color = Color("#14181c")
	add_child(bg)

	# Grid sutil de alinhamento
	var grid := Line2D.new()
	grid.default_color = Color(1.0, 1.0, 1.0, 0.04)
	grid.width = 1.0
	for y in range(60, 1080, 40):
		grid.points = PackedVector2Array([Vector2(0, y), Vector2(1920, y)])
		add_child(grid.duplicate())
	for x in range(60, 1920, 40):
		grid.points = PackedVector2Array([Vector2(x, 0), Vector2(x, 1080)])
		add_child(grid.duplicate())

	# Cabeçalho da Cena
	var title := Label.new()
	title.text = "GETECO · PROTÓTIPO A: DANTE RIBEIRO (CGI FIDELITY)"
	title.position = Vector2(40, 24)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f1c40f"))
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Comparação Visual Lado a Lado · Escala Real de Gameplay 1:1 · Turnaround · Animações Procedurais"
	subtitle.position = Vector2(40, 56)
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#a4b0be"))
	add_child(subtitle)

func _build_section_real_scale() -> void:
	# Container da Seção 1: Escala Real de Jogo
	var section_panel := PanelContainer.new()
	section_panel.position = Vector2(40, 95)
	section_panel.size = Vector2(580, 440)
	add_child(section_panel)

	var lbl := Label.new()
	lbl.text = "1. COMPARAÇÃO EM ESCALA REAL DE GAMEPLAY (1:1)\nAmbiente de Calçada & Rua do Jogo"
	lbl.position = Vector2(55, 108)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("#ffffff"))
	add_child(lbl)

	# Simulação visual de calçada e asfalto do jogo
	var sidewalk := ColorRect.new()
	sidewalk.size = Vector2(540, 100)
	sidewalk.position = Vector2(60, 155)
	sidewalk.color = Color("#b8b2a5") # Tom de calçada de Breakwater
	add_child(sidewalk)

	var curb := ColorRect.new()
	curb.size = Vector2(540, 8)
	curb.position = Vector2(60, 255)
	curb.color = Color("#8c8577") # Meio-fio
	add_child(curb)

	var asphalt := ColorRect.new()
	asphalt.size = Vector2(540, 160)
	asphalt.position = Vector2(60, 263)
	asphalt.color = Color("#26292d") # Asfalto
	add_child(asphalt)

	# Linha amarela da via
	var road_line := ColorRect.new()
	road_line.size = Vector2(540, 4)
	road_line.position = Vector2(60, 340)
	road_line.color = Color("#e5b73b")
	add_child(road_line)

	# Faixa de pedestres
	for i in 6:
		var stripe := ColorRect.new()
		stripe.size = Vector2(28, 70)
		stripe.position = Vector2(410 + i * 36, 270)
		stripe.color = Color("#dedede")
		add_child(stripe)

	# Dante Atual em Escala Real (1:1 no jogo = scale 0.38)
	var prod_dante := DANTE_PROD.new()
	prod_dante.position = Vector2(150, 220)
	prod_dante.render_scale = Vector2(0.38, 0.38)
	prod_dante.facing_angle = PI
	add_child(prod_dante)

	var lbl_prod := Label.new()
	lbl_prod.text = "DANTE ATUAL\n(Boné + Shades + Moletom)\n[Escala Real 1:1]"
	lbl_prod.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_prod.position = Vector2(65, 275)
	lbl_prod.add_theme_font_size_override("font_size", 11)
	lbl_prod.add_theme_color_override("font_color", Color("#e74c3c"))
	add_child(lbl_prod)

	# Novo Dante CGI em Escala Real (1:1 no jogo = scale 0.38)
	var cgi_dante := DANTE_CGI.new()
	cgi_dante.position = Vector2(310, 220)
	cgi_dante.render_scale = Vector2(0.38, 0.38)
	cgi_dante.current_state = "idle"
	cgi_dante.facing_angle = PI
	add_child(cgi_dante)

	var lbl_cgi := Label.new()
	lbl_cgi.text = "NOVO DANTE CGI\n(Cabelo + Couro + Henley)\n[Escala Real 1:1]"
	lbl_cgi.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_cgi.position = Vector2(225, 275)
	lbl_cgi.add_theme_font_size_override("font_size", 11)
	lbl_cgi.add_theme_color_override("font_color", Color("#2ecc71"))
	add_child(lbl_cgi)

	# Comparação ampliada (2.5x) para detalhamento de texturas e silhueta
	var lbl_zoom := Label.new()
	lbl_zoom.text = "INSPEÇÃO AMPLIADA (2.5x PARA LEITURA DE MATERIAIS):"
	lbl_zoom.position = Vector2(60, 355)
	lbl_zoom.add_theme_font_size_override("font_size", 12)
	lbl_zoom.add_theme_color_override("font_color", Color("#f39c12"))
	add_child(lbl_zoom)

	for px in [170, 330]:
		var pad := ColorRect.new()
		pad.size = Vector2(130, 140)
		pad.position = Vector2(px - 65, 385)
		pad.color = Color("#232b33")
		add_child(pad)

	var prod_zoom := DANTE_PROD.new()
	prod_zoom.position = Vector2(170, 455)
	prod_zoom.render_scale = Vector2(0.95, 0.95)
	prod_zoom.facing_angle = PI
	add_child(prod_zoom)

	var cgi_zoom := DANTE_CGI.new()
	cgi_zoom.position = Vector2(330, 460)
	cgi_zoom.render_scale = Vector2(0.95, 0.95)
	cgi_zoom.current_state = "idle"
	cgi_zoom.facing_angle = PI
	add_child(cgi_zoom)

func _build_section_turnaround() -> void:
	var section_panel := PanelContainer.new()
	section_panel.position = Vector2(640, 95)
	section_panel.size = Vector2(720, 440)
	add_child(section_panel)

	var lbl := Label.new()
	lbl.text = "2. FOLHA DE VISTAS (TURNAROUND 360° DO PROTÓTIPO CGI)\nÂngulos Frontal, Perfis, Costas e Isométrico na Câmera do Jogo"
	lbl.position = Vector2(655, 108)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("#ffffff"))
	add_child(lbl)

	var angles = [
		{"name": "FRENTE", "angle": PI, "x": 710},
		{"name": "PERFIL ESQ", "angle": PI * 0.5, "x": 850},
		{"name": "COSTAS", "angle": 0.0, "x": 990},
		{"name": "PERFIL DIR", "angle": -PI * 0.5, "x": 1130},
		{"name": "ISOMÉTRICA (3/4)", "angle": PI * 0.82, "x": 1270}
	]

	for a in angles:
		# Pedestal
		var ped := ColorRect.new()
		ped.size = Vector2(110, 140)
		ped.position = Vector2(a.x - 55, 175)
		ped.color = Color("#1e242a")
		add_child(ped)

		var model := DANTE_CGI.new()
		model.position = Vector2(a.x, 240)
		model.render_scale = Vector2(0.92, 0.92)
		model.facing_angle = a.angle
		model.current_state = "idle"
		add_child(model)

		var name_lbl := Label.new()
		name_lbl.text = a.name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(a.x - 65, 325)
		name_lbl.size = Vector2(130, 20)
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", Color("#f1c40f"))
		add_child(name_lbl)

	# Notas de Detalhamento Arquitetônico dos Ângulos
	var notes := Label.new()
	notes.text = "• Frente: Gola de couro aberta, decote henley bordô visível, 3 botões, mechas de cabelo sobre a testa, alças da mochila com fivelas de latão.\n• Costas: Volume ondulado do cabelo na nuca, gola traseira da jaqueta, caída da jaqueta bomber e barra sobre as botas.\n• Perfis: Projeção nasal, queixo firme com textura de barba (stubble), dobras da manga e solado tratorado da bota.\n• Isométrica: Síntese de volume e leitura angular exatamente como visto no gameplay em movimento."
	notes.position = Vector2(655, 365)
	notes.size = Vector2(690, 80)
	notes.add_theme_font_size_override("font_size", 11)
	notes.add_theme_color_override("font_color", Color("#b2bec3"))
	add_child(notes)

func _build_section_animations() -> void:
	var section_panel := PanelContainer.new()
	section_panel.position = Vector2(40, 560)
	section_panel.size = Vector2(1320, 480)
	add_child(section_panel)

	var lbl := Label.new()
	lbl.text = "3. ESTADOS DE ANIMAÇÃO PROCEDURAL EM TEMPO REAL (CGI RIG)"
	lbl.position = Vector2(55, 575)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color("#ffffff"))
	add_child(lbl)

	var anim_demos = [
		{
			"title": "ESTADO 1: PARADO (IDLE)",
			"desc": "Respiração torácica sutil, micro-elevação dos ombros,\npostura atlética relaxada, peso nos pés.",
			"state": "idle",
			"x": 240
		},
		{
			"title": "ESTADO 2: CAMINHADA (WALK)",
			"desc": "Ciclo bípedal natural (115 bpm), flexão de joelho,\ncontra-pêndulo de braços, bob vertical de tronco.",
			"state": "walk",
			"x": 680
		},
		{
			"title": "ESTADO 3: CORRIDA (RUN)",
			"desc": "Inclinação anterior de 14°, passada expandida,\ncotovelos flexionados a 65° bombeando com vigor.",
			"state": "run",
			"x": 1120
		}
	]

	for demo in anim_demos:
		# Piso de demonstração
		var floor_d := ColorRect.new()
		floor_d.size = Vector2(360, 240)
		floor_d.position = Vector2(demo.x - 180, 620)
		floor_d.color = Color("#181d22")
		add_child(floor_d)

		var model := DANTE_CGI.new()
		model.position = Vector2(demo.x, 730)
		model.render_scale = Vector2(1.10, 1.10)
		model.current_state = demo.state
		model.animation_speed = 1.0
		model.facing_angle = PI * 0.82
		add_child(model)

		var d_title := Label.new()
		d_title.text = demo.title
		d_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_title.position = Vector2(demo.x - 170, 875)
		d_title.size = Vector2(340, 24)
		d_title.add_theme_font_size_override("font_size", 13)
		d_title.add_theme_color_override("font_color", Color("#f1c40f"))
		add_child(d_title)

		var d_desc := Label.new()
		d_desc.text = demo.desc
		d_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d_desc.position = Vector2(demo.x - 170, 905)
		d_desc.size = Vector2(340, 50)
		d_desc.add_theme_font_size_override("font_size", 11)
		d_desc.add_theme_color_override("font_color", Color("#dfe6e9"))
		add_child(d_desc)

func _build_tech_specs_panel() -> void:
	# Painel Lateral Direito: Ficha Técnica Completa
	var panel := PanelContainer.new()
	panel.position = Vector2(1380, 95)
	panel.size = Vector2(500, 945)
	add_child(panel)

	var title := Label.new()
	title.text = "FICHA TÉCNICA & AUDITORIA VISUAL"
	title.position = Vector2(1400, 115)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#f1c40f"))
	add_child(title)

	var content := Label.new()
	content.position = Vector2(1400, 150)
	content.size = Vector2(460, 870)
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_size_override("font_size", 11)
	content.add_theme_color_override("font_color", Color("#ecf0f1"))
	content.text = """
ORÇAMENTO GEOMÉTRICO:
• Triângulos totais do rig: ~1.872 tris
• Malhas ativas: 36 nós MeshInstance3D articulados
• Tipo de primitivas: CapsuleMesh (membros), BoxMesh (mechas, botas, jaqueta), CylinderMesh (gola, pescoço), SphereMesh (cabeça).

MATERIAIS E TEXTURAS:
• Total de Materiais: 12 materiais PBR StandardMaterial3D compartilhados.
  - Couro Bomber (mat_leather_jacket): Albedo #2e211a, Roughness 0.42, Metallic 0.08.
  - Henley Vinho (mat_henley_shirt): Albedo #541923, Roughness 0.80.
  - Denim Índigo (mat_jeans): Albedo #233549, Roughness 0.75.
  - Botas & Sola (mat_boots / mat_sole): Albedo #1e1713 / #0d0e10, Roughness 0.45 / 0.90.
  - Cabelo Wavy (mat_hair): Albedo #111214, Roughness 0.85.
  - Stubble / Barba (mat_stubble): Albedo #221c18, Roughness 0.90.
  - Fivelas Latão (mat_brass_buckle): Albedo #c89f46, Metallic 0.85, Roughness 0.25.
  - Pele Morena (mat_skin): Albedo #cf9e78, Roughness 0.55.
• Método de Texturização: PBR Procedural em código (zero overhead de arquivos de imagem no VRAM).

MÉTODO DE RENDERIZAÇÃO:
• Pipeline Híbrido 3D/2.5D:
  - SubViewport 3D isolado (128x128) com own_world_3d = true.
  - Câmera 3D em Y=3.2, Z=1.4 inclinada a 30° mirando em Y=0.65 (visão idêntica ao jogo).
  - Projeção em Sprite2D na camada 2D do jogo com scale = Vector2(0.38, 0.38).
  - Preserva compatibilidade total com o sistema de física 2D (CharacterBody2D) e sombras no piso.

STATUS DE ENTREGA:
[X] Cabelo ondulado volumoso (Bangs sobre a testa e nuca): COMPLETO
[X] Rosto viril com barba sombreada (Stubble) e queixo quadrado: COMPLETO
[X] Jaqueta de couro aberta com gola dobrada (Bomber): COMPLETO
[X] Camisa Henley cor de vinho bordô com botões: COMPLETO
[X] Alças de couro da mochila com fivelas de latão: COMPLETO
[X] Calça jeans índigo escuro e botas tratoradas: COMPLETO
[X] Animações de Parado (Idle), Caminhada (Walk) e Corrida (Run): COMPLETO
[X] Comparação em escala real de jogo (1:1) com Dante Atual: COMPLETO
[ ] PENDENTE: Animações de Combate & Armas (intencionalmente não integradas neste protótipo para respeitar a diretriz de não alterar Player.gd e combates compartilhados).
"""
	add_child(content)
