extends "res://ui/hud/NotificationUI.gd"
## Aviso central "+R$ ..." quando entra dinheiro na carteira. Montado uma vez pelo
## ContextualHUDManager e reaproveitado: cada crédito só troca texto e reinicia o fade.
## Créditos que chegam em sequência (frete pago em partes, rajada de loot) somam no mesmo
## aviso em vez de piscar um cartão por parcela.
const GROUP_MSEC := 1000
const DURATION := 2.0
var total := 0
var source := ""
var _last_msec := -100000

func _ready() -> void:
	super()
	name = "MoneyReceived"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", 20)
	message.add_theme_color_override("font_color", STYLE.MONEY)

## Devolve true quando abriu um aviso novo (quem chama toca o som uma vez por aviso);
## false quando só somou no aviso que já estava na tela, ou quando o valor não é ganho.
func receive(amount: int, origin := "", now_msec := -1) -> bool:
	if amount <= 0: return false
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var grouped := visible and now - _last_msec < GROUP_MSEC
	_last_msec = now
	if grouped:
		total += amount
		if source.is_empty(): source = origin
		elif not origin.is_empty() and origin != source: source = ""
	else:
		total = amount
		source = origin
	present("+R$ " + STYLE.amount(total), "RECEBIDO" if source.is_empty() else "RECEBIDO · " + source, DURATION)
	return not grouped
