extends RefCounted
## Morrer ou ser preso custa alguma coisa. Antes os dois eram de graça e ainda zeravam a
## procura, então morrer era o melhor jeito de perder seis estrelas, e o hospital ficava fora
## do ciclo (revisão cruzada de 18/10/2026).
##   morte: Dante acorda na porta do Bay Medical (Harbor) e paga a conta;
##   prisão: sai pela delegacia (Harbor), paga a multa e perde a munição que carregava.
## Serra e deserto não têm hospital nem delegacia no catálogo: o resgate continua no ponto da
## região, com a mesma conta.
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")
const RATE: float = BALANCE.RECOVERY_RATE
const CAP: int = BALANCE.RECOVERY_CAP
const HOSPITAL := "harbor_hospital"
const PRECINCT := "harbor_police"

## 10% do dinheiro na mão, no máximo R$ 2.000: quem está quebrado não fica negativo.
static func fee(balance: int) -> int:
	return clampi(int(floor(float(balance) * RATE)), 0, CAP)

## Lugar de retorno no Harbor; vazio fora dele (usa o ponto de resgate da região).
static func place_for(region_id: String, arrested: bool) -> String:
	if region_id != "harbor": return ""
	return PRECINCT if arrested else HOSPITAL

## Cobra e confisca. Modo desenvolvedor com dinheiro infinito não paga nada.
static func apply(economy, arrested: bool) -> Dictionary:
	var amount := 0 if economy.cheat_infinite_money else fee(int(economy.balance))
	if amount > 0 and not economy.charge_fee(amount): amount = 0
	var ammo: int = economy.confiscate_carried_ammo() if arrested else 0
	return {"amount": amount, "ammo": ammo}

## Uma linha para o aviso do fim do resgate (as partes são traduzidas separadamente).
static func message(result: Dictionary, arrested: bool) -> String:
	var parts: Array[String] = []
	if int(result.get("amount", 0)) > 0:
		var label := "Multa da prisão: − R$ %d" if arrested else "Conta do hospital: − R$ %d"
		parts.append(String(TranslationServer.translate(label)) % int(result.amount))
	if int(result.get("ammo", 0)) > 0:
		parts.append(String(TranslationServer.translate("Munição apreendida: %d tiros")) % int(result.ammo))
	return " · ".join(parts)
