extends RefCounted
## Marcas fictícias de Harbor para outdoors de telhado.
##
## São paródias originais (não usar marca real nem marca de outro jogo). A
## regra de UrbanSignage — fachada leva só o nome próprio do estabelecimento —
## continua valendo: isto aqui é anúncio em outdoor, não letreiro de fachada.

const MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const FONT_PATH := "res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf"

const BRANDS := [
	{"name": "BURGER BARÃO", "slogan": "Gordura com nobreza", "bg": "c8372d", "fg": "ffd23f", "accent": "3b1a12"},
	{"name": "ZUMBA COLA", "slogan": "Tem gás. Tem açúcar. Tem processo.", "bg": "1b1b1f", "fg": "ff3e7a", "accent": "38e0d0"},
	{"name": "PNEUS TORTO", "slogan": "Rodou? Serve.", "bg": "f2c230", "fg": "1b1b1f", "accent": "c8372d"},
	{"name": "MARÉ ALTA", "slogan": "A cerveja do porto", "bg": "123c69", "fg": "f4f1e8", "accent": "e8a33d"},
	{"name": "SEGUROS TALVEZ", "slogan": "Cobrimos quase tudo", "bg": "e9e4d4", "fg": "1d3557", "accent": "e63946"},
	{"name": "RÁDIO GETECO FM", "slogan": "98.7 · só toca o que presta", "bg": "6a2c91", "fg": "ffe066", "accent": "ff8fab"},
	{"name": "TÁXI RELÂMPAGO", "slogan": "Chegamos antes de você ligar", "bg": "ffd000", "fg": "111111", "accent": "111111"},
	{"name": "FARMÁCIA DUVIDOSA", "slogan": "Sem receita, sem pergunta", "bg": "2a9d8f", "fg": "ffffff", "accent": "e9c46a"},
	{"name": "PETROLÍQUIDO", "slogan": "Combustível de verdade (quase)", "bg": "0f4c3a", "fg": "f1fa3c", "accent": "ff6b35"},
	{"name": "PIZZA DO PORTO", "slogan": "Entrega em 30 min ou 45", "bg": "f4f1e8", "fg": "c1121f", "accent": "2b9348"},
]


static func pick(key: String) -> Dictionary:
	return BRANDS[(key + "|brand").hash() % BRANDS.size()]


## Painel do outdoor. `placement` é o mesmo transform do billboard_frame
## (origem na laje, frente +Z). O fundo acende de leve à noite (refletor) e
## a faixa de destaque usa neon.
static func billboard_panel(brand: Dictionary, placement: Transform3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Billboard_" + String(brand.name).replace(" ", "")
	root.transform = placement
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var quad := QuadMesh.new()
	quad.size = Vector2(5.9, 2.8)
	panel.mesh = quad
	panel.position = Vector3(0, 2.4, 0.07)
	panel.material_override = MATERIALS.billboard(Color(brand.bg))
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(panel)
	var stripe := MeshInstance3D.new()
	stripe.name = "Stripe"
	var stripe_quad := QuadMesh.new()
	stripe_quad.size = Vector2(5.9, 0.34)
	stripe.mesh = stripe_quad
	stripe.position = Vector3(0, 1.17, 0.075)
	stripe.material_override = MATERIALS.neon(Color(brand.accent))
	stripe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stripe)
	root.add_child(_label(brand.name, Color(brand.fg), 150, Vector3(0, 2.72, 0.09), 5.4))
	root.add_child(_label(brand.slogan, Color(brand.fg).lerp(Color(brand.bg), 0.15), 62, Vector3(0, 1.82, 0.09), 5.4))
	return root


static func _label(text: String, color: Color, font_size: int, position: Vector3, max_width: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = load(FONT_PATH)
	label.font_size = font_size
	label.pixel_size = 0.01
	label.modulate = color
	label.outline_size = 0
	label.position = position
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.render_priority = 1
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Encolhe texto longo para caber no painel em vez de vazar pela borda.
	var width := label.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * label.pixel_size
	if width > max_width: label.pixel_size *= max_width / width
	return label
