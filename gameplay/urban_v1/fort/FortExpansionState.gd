extends RefCounted
## Estado da expansão do forte (alojamento, arsenal, comando): fases, recibos únicos,
## pistas sobre Vicente e o corte dos reforços. Vive em
## `world_state["mountain_fort_expansion"]`, então o save leva junto sem contrato novo de
## sessão e o diário lê direto dele. Plano: docs/forte-expansao-20261031.md.
##
## As salas novas ainda não têm geometria (pendência de arte). Esta camada é a regra:
## quem montar as salas só chama `complete_area` no ponto certo. A mesa de comando da sala
## de operações já existe, então a primeira pista (`desk`) já é jogável.
##
## Cânone: as pistas avançam sobre Vicente (quem assinou, onde ele esteve, o que levou)
## mas NÃO confirmam o que há no setor lacrado. Todo texto aqui deve admitir leitura
## mundana (contaminação, obra militar, acidente) e outra estranha, sem escolher.

const KEY := "mountain_fort_expansion"
const VERSION := 1
## Ordem da operação. `desk` é a mesa já existente; as três salas vêm depois.
const STAGES := ["locked","desk","barracks","armory","command","complete"]
const AREAS := ["desk","barracks","armory","command"]
const RADIO_CALL_TIME := 6.0

## Recompensas por área. Dinheiro sai pelo Economy com rótulo (aviso central do HUD);
## o recibo do Economy é a prova durável e o recibo local evita reaplicar pistas.
const REWARDS := {
	"desk": {"cash":0,"label":"","clues":["fort_desk_memo"]},
	"barracks": {"cash":2500,"label":"Alojamento do forte","clues":["fort_roster"],
		"quiet_bonus":1500,"quiet_label":"Entrada silenciosa"},
	"armory": {"cash":0,"label":"","clues":["fort_armory_ledger"],
		"weapon":"hunting_rifle","weapon_ammo":40,"ammo":{"m4a1":120}},
	"command": {"cash":12000,"label":"Cofre do comando","clues":["fort_seal_order","fort_tape_reference","fort_vicente_badge"],
		"cut_reinforcements":true},
}

## Textos das pistas (diário e aviso). Nenhum confirma a origem do setor lacrado.
const CLUES := {
	"fort_desk_memo": {"title":"Memorando na mesa de comando",
		"text":"\"Acesso ao setor 7 suspenso até segunda ordem. Ninguém desce sem o V.\" A inicial está sublinhada duas vezes."},
	"fort_roster": {"title":"Escala do alojamento",
		"text":"Uma escala de 1998 com um nome riscado à caneta: Vicente. Ao lado, alguém escreveu \"transferido\" e depois apagou."},
	"fort_armory_ledger": {"title":"Livro do arsenal",
		"text":"Saída de material registrada para o setor 7: lanternas, cal, lacre de chumbo. Assinado por V., sem patente."},
	"fort_seal_order": {"title":"Ordem de lacre",
		"text":"Ordem de fechamento do setor 7, carimbada e assinada por Vicente. O motivo foi cortado com tesoura antes do arquivo."},
	"fort_tape_reference": {"title":"Fita citada",
		"text":"Uma etiqueta de fita cassete: \"Setor 7, última ronda, V.\" A fita não está aqui. A ficha diz só: \"enviada para a cidade\"."},
	"fort_vicente_badge": {"title":"Crachá de Vicente",
		"text":"O crachá de Vicente, com a foto arranhada. Atrás, um número de cofre que não pertence a este forte."},
}

## Tipos novos de soldado (FortSoldier lê por `role`). Mesma malha e IA; muda parâmetro.
const SQUADS := {
	"barracks": [
		{"id":"fort_c1","role":"sentry","sleeping":true},
		{"id":"fort_c2","role":"sentry","sleeping":true},
		{"id":"fort_c3","role":"radioman"},
	],
	"armory": [
		{"id":"fort_d1","role":"shield"},
		{"id":"fort_d2","role":"rifleman"},
		{"id":"fort_d3","role":"marksman"},
	],
	"command": [
		{"id":"fort_e1","role":"leader"},
		{"id":"fort_e2","role":"shield"},
		{"id":"fort_e3","role":"radioman"},
		{"id":"fort_e4","role":"marksman"},
	],
}

static func default_state() -> Dictionary:
	return {"version":VERSION,"stage":"locked","receipts":[],"clues":[],"reinforcements_cut":false}

## Leitura sem gravar: o diário e o validador não devem criar estado.
static func peek(world_state: Dictionary) -> Dictionary:
	var value: Variant = world_state.get(KEY)
	return value if value is Dictionary and validate(value) else default_state()

## Leitura para escrita: garante o dicionário dentro do world_state.
static func state(world_state: Dictionary) -> Dictionary:
	var value: Variant = world_state.get(KEY)
	if not value is Dictionary or not validate(value):
		value = default_state()
		world_state[KEY] = value
	return value

static func validate(snapshot: Variant) -> bool:
	if not snapshot is Dictionary: return false
	var data: Dictionary = snapshot
	for field in ["version","stage","receipts","clues","reinforcements_cut"]:
		if not data.has(field): return false
	# JSON devolve inteiro como float; aceita os dois.
	if typeof(data.version) not in [TYPE_INT,TYPE_FLOAT] or int(data.version) != VERSION: return false
	if not data.stage is String or str(data.stage) not in STAGES: return false
	if not data.receipts is Array or not data.clues is Array or not data.reinforcements_cut is bool: return false
	var stage_index := STAGES.find(str(data.stage))
	for receipt in data.receipts:
		if not receipt is String or str(receipt) not in AREAS: return false
		# Uma área concluída precisa estar atrás da fase atual: impede save forjado que
		# pula para o cofre.
		if AREAS.find(str(receipt)) + 2 > stage_index: return false
	for clue in data.clues:
		if not clue is String or not CLUES.has(clue): return false
	return data.receipts.size() <= AREAS.size() and data.clues.size() <= CLUES.size()

static func stage(world_state: Dictionary) -> String:
	return str(peek(world_state).stage)

static func is_done(world_state: Dictionary,area: String) -> bool:
	return area in peek(world_state).receipts

## A sala de operações limpa (saque pego) abre a mesa de comando.
static func unlock(world_state: Dictionary) -> bool:
	var data := state(world_state)
	if data.stage != "locked": return false
	data.stage = "desk"
	return true

## Só a área da fase atual conclui; repetir devolve `already_done` sem conceder nada.
## `quiet` = a área foi limpa sem alarme (bônus do alojamento).
static func complete_area(world_state: Dictionary,economy,area: String,quiet := false) -> Dictionary:
	if area not in AREAS: return {"ok":false,"reason":"invalid_area"}
	var data := state(world_state)
	if area in data.receipts: return {"ok":true,"reason":"already_done","granted":0,"clues":[]}
	if data.stage != area: return {"ok":false,"reason":"wrong_stage"}
	var reward: Dictionary = REWARDS[area]
	var granted := 0
	var receipt_base := "mountain_fort_%s" % area
	# Recibos do Economy primeiro: se o save cair entre os dois passos, a próxima tentativa
	# não paga de novo (o Economy recusa recibo repetido) e só marca o local.
	if economy != null:
		if int(reward.get("cash",0)) > 0 and not economy.has_reward_receipt(receipt_base+"_cash"):
			if economy.grant_reward(receipt_base+"_cash",int(reward.cash),str(reward.label)): granted += int(reward.cash)
		if quiet and int(reward.get("quiet_bonus",0)) > 0 and not economy.has_reward_receipt(receipt_base+"_quiet"):
			if economy.grant_reward(receipt_base+"_quiet",int(reward.quiet_bonus),str(reward.quiet_label)): granted += int(reward.quiet_bonus)
		if reward.has("weapon"):
			var weapon_id: String = reward.weapon
			var rifle: Dictionary = economy.grant_world_reward({"id":receipt_base+"_weapon","kind":"weapon","item":weapon_id,"amount":1,"ammo":int(reward.weapon_ammo)})
			# Quem já tem o fuzil leva a munição dele, uma vez, pelo mesmo tipo de recibo.
			if not rifle.ok and rifle.reason == "already_owned" and not economy.has_reward_receipt(receipt_base+"_weapon_ammo"):
				if economy.grant_reward(receipt_base+"_weapon_ammo",0): economy.add_ammo(weapon_id,int(reward.weapon_ammo))
		for ammo_id in reward.get("ammo",{}):
			var ammo_receipt := receipt_base+"_ammo_"+str(ammo_id)
			if not economy.has_reward_receipt(ammo_receipt) and economy.grant_reward(ammo_receipt,0):
				economy.add_ammo(str(ammo_id),int(reward.ammo[ammo_id]))
	var new_clues: Array = []
	for clue in reward.clues:
		if clue not in data.clues:
			data.clues.append(clue)
			new_clues.append(clue)
	if bool(reward.get("cut_reinforcements",false)): data.reinforcements_cut = true
	data.receipts.append(area)
	data.stage = STAGES[STAGES.find(area)+1]
	return {"ok":true,"reason":"completed","granted":granted,"clues":new_clues}

static func reinforcements_cut(world_state: Dictionary) -> bool:
	return bool(peek(world_state).reinforcements_cut)

static func clue_message(clue: String) -> String:
	var entry: Dictionary = CLUES.get(clue,{})
	return "" if entry.is_empty() else "%s: %s" % [entry.title,entry.text]

## Linha do diário (J). Sem texto antes de a expansão abrir e depois do fim.
static func journal_line(world_state: Dictionary) -> String:
	match stage(world_state):
		"desk": return "Forte da Serra · Revire a mesa de comando da sala de operações."
		"barracks": return "Forte da Serra · O memorando cita o alojamento. Entre sem disparar o alarme."
		"armory": return "Forte da Serra · O arsenal guarda o registro de saída para o setor 7."
		"command": return "Forte da Serra · O cofre do comando tem a ordem de lacre assinada por Vicente."
		"complete": return ""
	return ""

## Rádio do operador: se ele ficar em combate vivo por RADIO_CALL_TIME, chama reforço uma
## vez. Lógica pura para o teste não depender de física.
class RadioCall extends RefCounted:
	var call_time := RADIO_CALL_TIME
	var progress := 0.0
	var called := false

	func tick(delta: float,alive: bool,in_combat: bool,cut: bool) -> bool:
		if called or cut or not alive: return false
		# Fora de combate o rádio não esvazia de uma vez: ele já começou a chamar.
		progress = clampf(progress+(delta if in_combat else -delta*.5),0.0,call_time)
		if progress >= call_time:
			called = true
			return true
		return false

	func fraction() -> float:
		return progress/call_time
