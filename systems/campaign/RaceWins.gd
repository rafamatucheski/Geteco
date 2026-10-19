extends RefCounted
## Vitórias em provas diferentes que liberam peças na oficina. Cada prova conta uma
## vez, onde quer que seja: os seis rivais da arrancada do deserto, as duas
## corridas dos Cobras e uma Noite de Acerto vencida. Motocross é de moto e a
## descida da montanha ainda não está ligada ao jogo, então não entram. A Noite
## existe para que quem só corre arrancada alcance as sete vitórias do nitro_pro
## sem depender de uma corrida da campanha.
const DRAG := preload("res://activities/desert_drag/DesertDragProgress.gd")
const NIGHT := preload("res://activities/desert_drag/DragNightProgress.gd")
const CAMPAIGN_RACES := ["cobra_race", "cobra_finale"]

static func maximum() -> int:
	return DRAG.RIVALS.size()+CAMPAIGN_RACES.size()+1

## `campaign` é o snapshot de CampaignRuntime (campo `completed`). Missão pulada do
## roteiro antigo não conta como vitória.
static func count(world: Dictionary, campaign: Dictionary) -> int:
	var total: int = DRAG.data(world).get("wins",[]).size()
	var completed: Array = campaign.get("completed",[])
	for id in CAMPAIGN_RACES:
		if id in completed: total += 1
	total += NIGHT.merit_count(world)
	return mini(total,maximum())
