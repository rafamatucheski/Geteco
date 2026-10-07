extends RefCounted
## Vitórias em provas diferentes que liberam peças na oficina. Cada prova conta uma
## vez, onde quer que seja: os cinco rivais da arrancada do deserto e as duas
## corridas dos Cobras. Motocross é de moto e a descida da montanha ainda não está
## ligada ao jogo, então não entram. O máximo atual é 7.
const DRAG := preload("res://activities/desert_drag/DesertDragProgress.gd")
const CAMPAIGN_RACES := ["cobra_race", "cobra_finale"]

static func maximum() -> int:
	return DRAG.RIVALS.size()+CAMPAIGN_RACES.size()

## `campaign` é o snapshot de CampaignRuntime (campo `completed`). Missão pulada do
## roteiro antigo não conta como vitória.
static func count(world: Dictionary, campaign: Dictionary) -> int:
	var total: int = DRAG.data(world).get("wins",[]).size()
	var completed: Array = campaign.get("completed",[])
	for id in CAMPAIGN_RACES:
		if id in completed: total += 1
	return mini(total,maximum())
