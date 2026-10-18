extends RefCounted
## Paga o bônus de conclusão (EconomyBalance.STORY_BONUS) de toda missão do Harbor cuja
## recompensa base já foi recebida e cujo bônus ainda não saiu. A mesma chamada serve na hora
## da conclusão e ao carregar um save antigo (pagamento retroativo); o recibo
## "campaign_bonus:<id>" garante que cada bônus sai uma vez só. A recompensa base continua no
## recibo "campaign:<id>", que o save valida contra HarborMissions e por isso não muda.
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")

static func receipt(id: String) -> String:
	return "campaign_bonus:" + id

static func settle(campaign_snapshot: Dictionary, economy) -> int:
	var paid := 0
	for id_value in campaign_snapshot.get("claimed_rewards", []):
		var id := str(id_value)
		var bonus := int(BALANCE.STORY_BONUS.get(id, 0))
		if bonus <= 0 or economy.has_reward_receipt(receipt(id)): continue
		if economy.grant_reward(receipt(id), bonus): paid += bonus
	return paid

## Total que a missão paga hoje (base + bônus), para o aviso de conclusão.
static func total(id: String) -> int:
	return int(MISSIONS.MISSIONS.get(id, {}).get("reward", 0)) + int(BALANCE.STORY_BONUS.get(id, 0))

static func completion_notice(id: String) -> String:
	var title := String(TranslationServer.translate(str(MISSIONS.MISSIONS.get(id, {}).get("title", id))))
	return String(TranslationServer.translate("%s concluída · + R$ %d")) % [title, total(id)]
