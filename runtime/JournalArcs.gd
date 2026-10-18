extends RefCounted
## Histórias em andamento para o diário (J). Antes o diário só listava as missões do Harbor,
## as atividades da montanha e o arquivo de Vicente: o ato 2 do deserto, a Forja da Serra, a
## pista de Vicente na serra e o Tonico só apareciam como objetivo dentro da própria região, e
## sumiam assim que o jogador saía dela (revisão cruzada de 18/10/2026).
## Cada linha usa o mesmo texto do objetivo da região (função estática do próprio sistema).
const GATEWAY := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const DESERT := preload("res://runtime/desert/DesertCampaign.gd")
const MOUNTAIN := preload("res://activities/mountain_story/MountainStory.gd")
const VILLAGE := preload("res://gameplay/urban_v1/TruckersVillageQuest.gd")
const FORGE_LINES := {
	"met": "Forja da Serra · Pergunte a Seu Bento sobre o aço lendário.",
	"seek_hermit": "Forja da Serra · Encontre o Mestre Aurélio na cabana ao norte das pistas de esqui.",
	"seek_miner": "Forja da Serra · Procure o Tião no acampamento da Mineração do deserto.",
	"has_ore": "Forja da Serra · Leve o minério negro a Seu Bento.",
}

## Linhas já traduzidas, na ordem da história. `village` é o estado vivo do Tonico quando a
## sessão tem a vila montada (o world_state só recebe a cópia no próximo save).
static func lines(world_state: Dictionary, campaign_snapshot: Dictionary, village: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	var mountain := MOUNTAIN.journal_line(world_state)
	if not mountain.is_empty(): result.append(_t(mountain))
	# Lê direto do save: FORGE.quest() grava uma missão nova quando falta, e o diário só lê.
	var forge_state: Variant = world_state.get("blade_forge", {})
	var forge := str(FORGE_LINES.get(str(forge_state.get("stage", "unknown")) if forge_state is Dictionary else "unknown", ""))
	if not forge.is_empty(): result.append(_t(forge))
	var tonico := VILLAGE.journal_line(village if not village.is_empty() else world_state.get("urban_operations", {}).get("truckers_village", {}))
	if not tonico.is_empty(): result.append(_t(tonico))
	# O deserto só abre depois do fim do Harbor (a ponte usa a mesma regra).
	if GATEWAY.campaign_completed(campaign_snapshot) and not DESERT.act_complete(world_state):
		result.append(_t("Deserto") + " · " + _t(DESERT.objective_for(world_state)))
	return result

static func _t(text: String) -> String:
	return String(TranslationServer.translate(text))
