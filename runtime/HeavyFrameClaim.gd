extends RefCounted
## Um trabalho pesado por quadro entre donos independentes. Quem tem trabalho adiável pede o quadro
## antes de começar; se outro dono já levou este quadro, deixa para o próximo.
## Motivo (27/10): no deserto, aos 3 s, a desmontagem da região anterior (~5,5 ms) caía no mesmo quadro
## da etapa de estradas do chão (~7 ms) e do desenho das peças novas, num quadro de ~58 ms.
## GETECO_HEAVY_FRAME_CLAIM=0 desliga (todo pedido é aceito, como antes).
static var enabled := OS.get_environment("GETECO_HEAVY_FRAME_CLAIM") != "0"
static var _frame := -1
static var _owner := ""

## true se o quadro atual está livre ou já é deste dono (e o reserva para ele).
static func claim(owner: String) -> bool:
	if not enabled: return true
	var frame := Engine.get_process_frames()
	if _frame == frame and _owner != owner: return false
	_frame = frame
	_owner = owner
	return true

## Dono do quadro atual, ou "" se ninguém pediu.
static func owner() -> String:
	return _owner if _frame == Engine.get_process_frames() else ""
