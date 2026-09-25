extends CanvasLayer
## Tela de carregamento da partida: arte da região com vida (living_art), dica, etapa
## atual e barra de progresso com as etapas reais do ProductionWorld.build.
##
## Nasce no menu (MainMenu._start), na raiz da árvore, para aparecer antes do
## carregamento bloqueante da cena Main; o ProductionWorld a adota como filha do mundo
## (os testes procuram a cortina ali) e a retira com `lift` quando o mundo está assentado.
## Início direto (--no-save, testes) cria a cortina no próprio build.
##
## Histórico: na promoção da V2 as três telas de loading da V1 (barra, arte, dicas)
## viraram um retângulo escuro com "Carregando…" (feedback de 25/09/2026). A cortina
## continua cobrindo a janela em que o Dante ainda não está no ponto salvo e o terreno
## está cru: encurtar essa janela já foi tentado mais de uma vez.

const NODE_NAME := "LoadingCurtain"
const DISPLAY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const BODY_FONT: FontFile = preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const LIVING_ART: Shader = preload("res://ui/art/living_art.gdshader")
const ACCENT := Color("ff914d")
const TEXT := Color("eee9df")
const MUTED := Color("a9b4bc")
const VARIANTS := [
	{"art": "res://ui/art/loading/harbor_arrival.png", "place": "PORTO CENTRAL", "title": "Chegada ao porto"},
	{"art": "res://ui/art/loading/mountain_pass.png", "place": "PASSAGEM DA SERRA", "title": "Atravessando a serra"},
	{"art": "res://ui/art/loading/garage_district.png", "place": "DISTRITO DA OFICINA", "title": "De volta à oficina"},
]
const TIPS := [
	"O marcador laranja indica seu próximo destino. Procure a entrada sinalizada.",
	"Maciota tem serviços novos no quadro da oficina. Volte depois de cada entrega.",
	"Entre nos lugares caminhando até a porta; não precisa apertar nada.",
	"Viatura parada no meio da rua? O trânsito agora contorna, mas a polícia não esquece.",
	"Hidrante quebrado vira jato d'água: serve até para apagar carro pegando fogo.",
	"Na montanha, procure abrigo quando o frio apertar. E respeite os ursos.",
	"Noites de lua cheia são mais claras. Na lua nova, ligue os faróis.",
	"Ajuste brilho, sombras e controles em Configurações para jogar do seu jeito.",
]
const TIP_SECONDS := 6.0

var variant := 0
var _root: Control
var _art: TextureRect
var _stage: Label
var _percent: Label
var _tip: Label
var _fill: ColorRect
var _track: ColorRect
var _elapsed := 0.0
var _tip_index := 0
var _shown := 0.0
var _target := 0.0

## Arte por região: Harbor alterna porto e oficina, Mountain usa a serra.
static func variant_for(region_id: String) -> int:
	if region_id == "mountain": return 1
	return 0 if randf() < 0.6 else 2

## A cortina que o menu deixou na raiz, se houver.
static func existing(tree: SceneTree) -> CanvasLayer:
	return tree.root.get_node_or_null(NODE_NAME) as CanvasLayer

func _ready() -> void:
	name = NODE_NAME
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip_index = randi() % TIPS.size()
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var ink := ColorRect.new()
	ink.color = Color("0a0e12")
	ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(ink)
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var living := ShaderMaterial.new()
	living.shader = LIVING_ART
	living.set_shader_parameter("zoom", 1.05)
	_art.material = living
	_root.add_child(_art)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ float a=clamp(0.18+pow(UV.y,2.2)*0.78+(1.0-UV.x)*0.12,0.0,0.97); COLOR=vec4(0.02,0.035,0.05,a); }"
	var shade_material := ShaderMaterial.new()
	shade_material.shader = shader
	shade.material = shade_material
	_root.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 64)
	# Topo abaixo da marca d'água do build (canto superior esquerdo).
	margin.add_theme_constant_override("margin_top", 58)
	margin.add_theme_constant_override("margin_bottom", 44)
	_root.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	margin.add_child(stack)
	var brand := _label("GETECO", 22, TEXT, DISPLAY_FONT)
	brand.name = "Brand"
	stack.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(spacer)
	var place := _label("", 15, ACCENT, DISPLAY_FONT)
	place.name = "Place"
	stack.add_child(place)
	var title := _label("", 44, TEXT, DISPLAY_FONT)
	title.name = "Title"
	stack.add_child(title)
	_tip = _label("", 18, MUTED, BODY_FONT)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(0, 52)
	_tip.size_flags_horizontal = Control.SIZE_FILL
	stack.add_child(_tip)
	var status := HBoxContainer.new()
	stack.add_child(status)
	_stage = _label("", 16, TEXT, DISPLAY_FONT)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_stage)
	_percent = _label("0%", 16, ACCENT, DISPLAY_FONT)
	status.add_child(_percent)
	_track = ColorRect.new()
	_track.color = Color(1, 1, 1, 0.12)
	_track.custom_minimum_size.y = 5
	stack.add_child(_track)
	_fill = ColorRect.new()
	_fill.color = ACCENT
	_fill.size = Vector2(0, 5)
	_track.add_child(_fill)
	set_variant(variant)
	set_stage(0.0, "Preparando sua partida…")

func _label(text: String, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func set_variant(index: int) -> void:
	variant = clampi(index, 0, VARIANTS.size() - 1)
	if _art == null: return
	var data: Dictionary = VARIANTS[variant]
	_art.texture = load(data.art)
	(_root.find_child("Place", true, false) as Label).text = data.place
	(_root.find_child("Title", true, false) as Label).text = data.title
	(_root.find_child("Brand", true, false) as Label).text = "GETECO   /   %02d" % (variant + 1)

## Progresso (0–1, nunca volta) e texto da etapa. A barra alcança o alvo suavemente.
func set_stage(value: float, message: String) -> void:
	_target = maxf(_target, clampf(value, 0.0, 1.0))
	if _stage != null: _stage.text = message

func _process(delta: float) -> void:
	_elapsed += delta
	# Etapa longa sem notícia: a barra anda devagar até perto do próximo marco,
	# para não parecer travada (nunca passa do alvo + 6%).
	if _shown < _target: _shown = move_toward(_shown, _target, delta * 0.9)
	else: _shown = minf(_shown + delta * 0.004, minf(_target + 0.06, 0.99))
	if _fill != null and _track != null:
		_fill.size = Vector2(_track.size.x * clampf(_shown, 0.0, 1.0), _track.size.y)
		_percent.text = "%d%%" % roundi(clampf(_shown, 0.0, 1.0) * 100.0)
	var tip := int(_elapsed / TIP_SECONDS)
	if _tip != null: _tip.text = TIPS[(_tip_index + tip) % TIPS.size()]

## Espera alguns quadros para sombras, clima e streaming assentarem e sai.
func lift(settle_frames := 8) -> void:
	set_stage(1.0, "Pronto")
	for i in settle_frames: await get_tree().process_frame
	# Barra cheia por um instante antes do fade: o jogador vê que terminou.
	_shown = 1.0
	if _fill != null: _fill.size.x = _track.size.x
	if _percent != null: _percent.text = "100%"
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, .45)
	await tween.finished
	queue_free()
