extends RefCounted
## Objetivo do ato 2 (o texto do diário e do mapa, etapa por etapa) e o ponto de destino no mapa, separados
## da VicenteReunion em 01/11 só para ela caber na leitura. A VicenteReunion mantém cada função antiga como
## delegação de uma linha: DesertCampaign (que o diário usa) e os testes chamam REUNION.chain_at/objective_for, e
## DesertCampaign lê target_position() no nó.
## `chain_at` e `objective_for` são estáticas (DesertCampaign pergunta sem nó montado), então chamam uma à outra
## direto; `objective` e `target_position` leem o estado do dono por `g.`. `g` fica como Node3D, sem preload
## do dono (evita preload cíclico).
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ROSTER := preload("res://runtime/desert/drag_meet/DragMeetRoster.gd")
const STATE := preload("res://runtime/desert/act2/VicenteAct2State.gd")
const STORY := preload("res://runtime/desert/DesertStoryState.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Etapa de uma missão da cadeia, ou "-" se a anterior ainda não acabou.
static func chain_at(world: Dictionary, id: String) -> String:
	return STATE.chain_stage(world, id) if STATE.chain_ready(world, id) else "-"

func objective() -> String:
	return g.objective_for(g._world())

static func objective_for(world: Dictionary) -> String:
	match STATE.stage(world):
		"motel": return "Vá ao Motel Oásis, na Estrada do Sal, e fale com Vicente."
		"chapel": return "Encontre Vicente na Capela da Estrada."
	if not STATE.complete(world): return ""
	match STATE.track_stage(world):
		"": return "Fale com Bia no pátio do Digo."
		"race": return "Corra contra Digo na reta: quadro da concentração."
		"grandstand": return "Encontre Vicente na Arquibancada da reta."
	match chain_at(world, "cargo"):
		"": return "Fale com Raul no encontro da arrancada."
		"crate": return "Abra o caixote dos Cobras no posto Miragem."
		"weigh": return "Leve o lacre à Fiscal Rosa, na Balança da Estrada do Sal."
		"raul": return "Volte ao Raul no encontro da arrancada."
	match chain_at(world, "order"):
		"": return "Leve o manifesto a Irene, no Cobre."
		"night": return "Vá à porta dos fundos do Cobre depois das 20h (descanse no Horizonte)."
		"call": return "Ligue para o Maciota do orelhão do Horizonte."
	match chain_at(world, "brothers"):
		"": return "Fale com Vicente no encontro da arrancada."
		"race": return "Corra contra Vicente: pare o carro na concentração."
		"won", "lost": return "Fale com Vicente no encontro da arrancada."
	if chain_at(world, "cave") == "": return "Encontre Vicente na caverna da mesa de pedra, ao sul do leito seco."
	match chain_at(world, "letters"):
		"": return "Pergunte à Dona Fátima, na Capela da Estrada."
		"tower": return "Suba na torre de rádio da Rua Principal e ligue para o Maciota."
		"coop": return "Peça o malote antigo pelo rádio da cooperativa de Santa Lua."
		"water": return "Encontre Helena na caixa-d'água de Santa Lua."
	match chain_at(world, "bet"):
		"": return "Fale com Jessica no encontro da arrancada." if bool(STORY.data(world).jessica_met) else "Corra contra Jessica pelo quadro da concentração."
		"cascavel": return "Fale com o Cascavel na concentração."
		"race": return "Chave na chave: corra contra o Cascavel (pare o carro na concentração)."
		"keys": return "Entregue a chave da Monaliza ao Cascavel."
	match chain_at(world, "trunk"):
		"": return "Arranje outro carro (o Nonato, no ferro-velho, tem um) e leve à Bia, no pátio do Digo."
		"car": return "Leve o carro do Nonato à Bia, no pátio do Digo."
	match chain_at(world, "convoy"):
		"": return "Roube a carga do comboio dos Cobras na Estrada do Sal, de madrugada (0h às 5h)."
		"motel": return "Leve o lacre a Vicente, no Motel Oásis."
	match chain_at(world, "salt"):
		"": return "Mostre o lacre ao Seu Bento, nas Salinas."
		"camp": return "Recupere o caderno no acampamento ao sul do leito seco."
		"home": return "Vá à casa da Helena em Santa Lua."
	match chain_at(world, "teodoro"):
		"": return "Dona Lurdes chamou: vá ao Motel Oásis."
		"fight": return "Vicente partiu pra cima. Derrube seu irmão."
		"chase": return "Alcance Teodoro na obra da passagem norte."
	match chain_at(world, "finale"):
		"": return "Encontre Vicente na Arquibancada da reta."
		"defend": return "Defenda o encontro da arrancada dos Cobras."
		"gate": return "Encontre Vicente na passagem norte."
	return ""

func target_position() -> Vector3:
	var spot: Dictionary = g._mission_point()
	if not spot.is_empty(): return spot.point
	var world: Dictionary = g._world()
	if not g.story_race().is_empty(): return g.STAGING
	if g.chain_at(world, "finale") == "defend": return g.RAID_CENTER
	if g.chain_at(world, "salt") == "camp": return g.ledger_point()
	if g.chain_at(world, "teodoro") == "chase" and not is_instance_valid(g.actor): return g.folder_point()
	if g.chain_at(world, "trunk") == "car" or (g.chain_at(world, "trunk") == "" and g._car_for_trunk() != null): return g.BIA_POINT
	var def: Dictionary = g.scene_def(world)
	if not def.is_empty():
		if is_instance_valid(g.actor): return g.actor.global_position
		return g._site_point(str(def.spot), g._points(str(def.spot))[0])
	if g.chain_at(world, "brothers") in ["", "won", "lost"]: return LAYOUT.DRAG_VICENTE
	if g.chain_at(world, "bet") == "": return ROSTER.LEADERS.jessica if bool(STORY.data(world).jessica_met) else g.STAGING
	return Vector3.INF
