extends Control
const STYLE = preload("res://ui/GameStyle.gd")
const ART := [
	"res://cutscenes/opening/frames/frame_10_bus_terminal_arrival.png",
	"res://cutscenes/opening/frames/frame_08_bus_highway.png",
	"res://cutscenes/opening/frames/frame_v2_decision.png",
]
var variant := 0
var progress: ProgressBar
var stage: Label
var tip: Label
var title: Label
var recovery: Button
var elapsed := 0.0
var shown_progress := 0.0
var target_progress := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := TextureRect.new()
	background.texture = load(ART[variant])
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ float a=clamp(0.25+pow(UV.y,2.4)*0.73+(1.0-UV.x)*0.15,0.0,0.98); COLOR=vec4(0.025,0.04,0.055,a); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	shade.material = material
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]: margin.add_theme_constant_override("margin_"+side, 56)
	for side in ["top","bottom"]: margin.add_theme_constant_override("margin_"+side, 40)
	add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)
	var brand := Label.new()
	brand.text = "GETECO   /   " + str(variant+1).pad_zeros(2)
	brand.add_theme_font_size_override("font_size", 22)
	brand.add_theme_color_override("font_color", STYLE.TEXT)
	stack.add_child(brand)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(spacer)
	var eyebrow := Label.new()
	eyebrow.text = _text("UMA CIDADE. NOVOS CAMINHOS.", "ONE CITY. NEW ROADS.")
	eyebrow.add_theme_color_override("font_color", STYLE.ACCENT)
	eyebrow.add_theme_font_size_override("font_size", 14)
	stack.add_child(eyebrow)
	title = Label.new()
	title.text = [_text("De volta às ruas", "Back on the streets"),_text("O caminho continua", "The road continues"),_text("Cada escolha deixa marcas", "Every choice leaves a mark")][variant]
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", STYLE.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(title)
	tip = Label.new()
	tip.add_theme_font_size_override("font_size", 17)
	tip.add_theme_color_override("font_color", STYLE.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.y = 48
	stack.add_child(tip)
	stage = Label.new()
	stage.add_theme_font_size_override("font_size", 15)
	stage.add_theme_color_override("font_color", STYLE.TEXT)
	stack.add_child(stage)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 6
	progress.show_percentage = false
	var track := StyleBoxFlat.new()
	track.bg_color = Color("34414a")
	var fill := StyleBoxFlat.new()
	fill.bg_color = STYLE.ACCENT
	progress.add_theme_stylebox_override("background",track)
	progress.add_theme_stylebox_override("fill",fill)
	stack.add_child(progress)
	recovery = Button.new()
	recovery.text = _text("Voltar", "Back")
	recovery.visible = false
	stack.add_child(recovery)
	STYLE.apply(stack,get_node("/root/SettingsManager").text_scale)
	set_stage(0.0,_text("Preparando sua partida…", "Preparing your game…"))
	_update_tip()

func _text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt

func set_stage(value: float, message: String) -> void:
	target_progress = maxf(target_progress,value)
	stage.text = message

func _process(delta: float) -> void:
	elapsed += delta
	shown_progress = move_toward(shown_progress,target_progress,delta*0.75)
	progress.value = shown_progress*100
	_update_tip()

func _update_tip() -> void:
	var tips := [
		_text("O marcador laranja indica seu próximo destino. Procure a entrada sinalizada.","The orange marker points to your next destination. Look for the marked entrance."),
		_text("Maciota tem novos serviços no quadro da oficina. Volte depois de cada entrega.","Maciota has new jobs on the workshop board. Return after each delivery."),
		_text("Ajuste o texto e os controles nas configurações para jogar do seu jeito.","Adjust text size and controls in Settings to play your way."),
		_text("Na montanha, procure abrigo quando o frio apertar.","In the mountains, look for shelter when the cold sets in."),
	]
	tip.text = tips[(variant+int(elapsed/7.0))%tips.size()]
