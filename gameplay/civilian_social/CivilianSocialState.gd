extends RefCounted
## Social memory is separate from crime evidence; calming never erases a report.
const PERSONALITIES := ["friendly", "reserved", "nervous"]
const MOODS := {"calm":"Tranquilo", "happy":"Contente", "talking":"Conversando", "annoyed":"Irritado",
	"scared":"Assustado", "calling_police":"Chamando a polícia", "recovering":"Se acalmando"}
const ACTIONS := [{"id":"greet", "label":"Cumprimentar"}, {"id":"chat", "label":"Conversar"},
	{"id":"joke", "label":"Brincar"}, {"id":"reassure", "label":"Acalmar"}, {"id":"intimidate", "label":"Intimidar"}]
var personality := "friendly"
var display_name := "Morador"
var activity := "read"
var state := "calm"
var trust := 0
var cooldown := 0.0
var fear_left := 0.0
var state_left := 0.0
var threat_cooldown := 0.0
var conversation := false
var dangerous := false
var calling := false
var last_action := ""
var repeated := 0
var routine_clock := 0.0
var routine_phase := "work"
var _line_index := 0

func configure(specification: Dictionary) -> void:
	var identity := absi(int(specification.get("identity", 0)))
	personality = str(specification.get("personality", PERSONALITIES[identity % PERSONALITIES.size()]))
	if personality not in PERSONALITIES: personality = "reserved"
	display_name = str(specification.get("name", "Morador"))
	activity = str(specification.get("activity", "read"))
	routine_clock = float(identity % 11)

func advance(delta: float, threat_active := false, report_active := false) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	cooldown = maxf(0.0, cooldown - delta)
	threat_cooldown = maxf(0.0, threat_cooldown - delta)
	state_left = maxf(0.0, state_left - delta)
	dangerous = threat_active
	calling = report_active
	if calling:
		conversation = false
		state = "calling_police"
		fear_left = maxf(fear_left, 6.0)
	elif dangerous:
		conversation = false
		state = "scared"
		fear_left = maxf(fear_left, 5.0)
	else:
		fear_left = maxf(0.0, fear_left - delta)
		if fear_left > 3.0: state = "scared"
		elif fear_left > 0.0: state = "recovering"
		elif state_left <= 0.0: state = "talking" if conversation else "calm"
	if not conversation and state == "calm":
		routine_clock = fposmod(routine_clock + delta, 19.0)
		routine_phase = "pause" if routine_clock >= 15.5 else "work"
	else: routine_phase = "attention"

func frightened(seconds := 7.0) -> void:
	fear_left = maxf(fear_left, seconds * (1.25 if personality == "nervous" else 1.0))
	state = "scared"
	conversation = false

func can_interact() -> bool:
	return not dangerous and not calling

func begin() -> bool:
	if not can_interact(): return false
	conversation = true
	if fear_left <= 0.0 and state_left <= 0.0: state = "talking"
	return true

func finish() -> void:
	conversation = false
	if state == "talking":
		state = "calm"
		state_left = 0.0

func options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in ACTIONS:
		result.append({"id":action.id, "label":action.label, "enabled":can_interact() and cooldown <= 0.0})
	return result

func interact(action: String, armed := false) -> Dictionary:
	if action not in ["greet", "chat", "joke", "reassure", "intimidate"]:
		return {"ok":false, "line":"", "state":state}
	if not can_interact(): return {"ok":false, "line":"Agora não. Preciso me proteger!", "state":state, "close":true}
	if cooldown > 0.0: return {"ok":false, "line":"Só um instante.", "state":state}
	if armed and action != "intimidate":
		frightened(5.0)
		cooldown = 1.0
		return {"ok":false, "line":"Guarda essa arma primeiro, por favor.", "state":state}
	cooldown = 1.4
	repeated = repeated + 1 if action == last_action else 0
	last_action = action
	_line_index += 1
	var line := ""
	var report := false
	match action:
		"intimidate":
			trust = maxi(-4, trust - 2)
			frightened(10.0)
			report = threat_cooldown <= 0.0
			threat_cooldown = 22.0
			line = "Fica longe de mim! Vou pedir ajuda!"
		"reassure":
			if fear_left > 0.0:
				fear_left = minf(fear_left, 2.0)
				state = "recovering"
				line = "Tá... vou respirar um pouco. Me dá espaço."
			else:
				state = "talking"
				line = "Tá tudo bem por aqui. Obrigado por perguntar."
		_:
			if fear_left > 0.0:
				line = "Depois a gente conversa. Ainda estou tremendo."
			elif repeated >= 2:
				state = "annoyed"
				trust = maxi(-4, trust - 1)
				line = "Já entendi. Preciso voltar ao que estava fazendo."
			elif action == "greet":
				trust = mini(4, trust + 1)
				state = "happy" if personality != "reserved" else "talking"
				line = "Opa, tudo certo? Bom te ver por aqui." if personality == "friendly" else "Oi. Tudo bem?"
			elif action == "joke":
				if personality == "reserved" and trust < 1:
					state = "annoyed"
					line = "Hoje estou sem cabeça pra brincadeira."
				else:
					trust = mini(4, trust + 1)
					state = "happy"
					line = "Ha! Essa foi boa. Eu precisava rir um pouco."
			else:
				state = "talking"
				line = _work_line()
	state_left = 5.0
	return {"ok":true, "line":line, "state":state, "report":report, "close":action == "intimidate"}

func _work_line() -> String:
	if trust < 0: return "Depois do susto que você me deu, prefiro ficar na minha."
	if _line_index % 2 == 0:
		return "Dia corrido, mas uma conversa boa sempre ajuda." if personality == "friendly" else "Só quero terminar o dia em paz."
	match activity:
		"repair": return "Essa peça está me dando trabalho. Vai ser bom ver tudo funcionando."
		"cook": return "Estou cuidando da comida. O segredo é não ter pressa."
		"write": return "Papelada não acaba nunca. E você, como está levando o dia?"
		"phone": return "Estava falando com o pessoal de casa. É bom saber que está tudo bem."
		"check": return "Estou conferindo as coisas. Se eu me perder na conta, começo de novo."
		"sit_write": return "Sentado aqui desde cedo. Essas contas não fecham sozinhas."
		"sit_phone": return "Tava só vendo umas mensagens. O grupo da família não para."
		"sit_read", "read": return "Achei uma leitura boa. Só falta um pouco de sossego pra terminar."
		"tv": return "Tá passando o jogo. Senta aí se quiser, mas não fala do resultado."
		"sit_doze": return "Eu? Dormindo? Só estava descansando os olhos."
		"stretch": return "Acabei de acordar. Ainda estou me achando por aqui."
		"coffee": return "Terceiro café do dia. Ou quarto, já perdi a conta."
		"clean": return "Se eu não varrer, ninguém varre. Cuidado onde pisa."
		"wander": return "Tô só andando um pouco pra esticar as pernas."
		"chat": return "A gente estava colocando o papo em dia. Tudo certo?"
		_: return "Achei uma leitura boa. Só falta um pouco de sossego pra terminar."

func snapshot() -> Dictionary:
	return {"name":display_name, "state":state, "mood_label":MOODS.get(state, "Tranquilo"),
		"personality":personality, "trust":trust, "cooldown":cooldown,
		"can_interact":can_interact(), "routine":routine_phase, "conversation":conversation}
