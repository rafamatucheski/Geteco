extends CanvasLayer
## Cortina opaca da abertura. `ProductionWorld.build` monta região, jogador e
## câmera e só depois (12 quadros de física + `restore_location`) põe o Dante no
## ponto salvo. Nessa janela a câmera mostrava o terreno cru — neve/gelo da
## região ainda sem chunks e o boneco abaixo do chão — por alguns quadros.
## Encurtar a janela já foi tentado mais de uma vez; a cortina esconde a janela
## inteira e sai com um fade quando o mundo está assentado.

var _rect: ColorRect
var _label: Label

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color("0d1014")
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_rect)
	_label = Label.new()
	_label.text = "Carregando…"
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.modulate = Color(1, 1, 1, .7)
	_rect.add_child(_label)

## Espera alguns quadros para sombras, clima e streaming assentarem e sai.
func lift(settle_frames := 8) -> void:
	for i in settle_frames: await get_tree().process_frame
	var tween := create_tween()
	tween.tween_property(_rect, "modulate:a", 0.0, .35)
	await tween.finished
	queue_free()
