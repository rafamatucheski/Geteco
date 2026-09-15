extends RefCounted
## All jumps move forwards. A short arrival window avoids waiting another day
## when the player accepts just after the advertised meeting time.
const HOURS := {"primeiro_giro": 10.0, "cobra_contact": 15.0, "cobra_race": 21.0}
static func forward_days(current: float, id: String) -> float:
	if not HOURS.has(id) or not is_finite(current): return 0.0
	var target: float = HOURS[id] / 24.0
	var normalized := fposmod(current, 1.0)
	var since := fposmod(normalized - target, 1.0)
	if since <= 2.0 / 24.0: return 0.0
	return fposmod(target - normalized, 1.0)

static func description(id: String, english: bool) -> String:
	match id:
		"primeiro_giro": return "10:00 · Bank receipt, dock pickup and return to Maciota. No purchase required." if english else "10h · Comprovante no banco, peça no porto e retorno ao Maciota. Não exige compra."
		"cobra_contact": return "15:00 · Meet Ferrugem and recover a broken-down car with Neco's tow truck." if english else "15h · Conheça Ferrugem e recupere um carro avariado com o guincho do Neco."
		"cobra_race": return "21:00 · One lap in 100 seconds. Follow all four gates in order on the outside lane. Accepting advances to the meeting time." if english else "21h · Uma volta em 100 segundos. Passe pelos quatro portões em ordem na faixa externa. Aceitar avança até o horário do encontro."
	return ""
