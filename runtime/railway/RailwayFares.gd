extends RefCounted
## Tarifa e cobrança do bilhete do trem. Lógica pura (sem nó, sem cena) para o teste cobrir
## preço, recusa sem saldo e a garantia de não cobrar duas vezes o mesmo embarque.
const NETWORK := preload("res://world/railway/RailwayNetwork.gd")
const BALANCE := preload("res://data/catalogs/EconomyBalance.gd")

## Zona tarifária = região da estação; Harbor Central e Northgate dividem a zona do porto.
static func zone(station_id: String) -> String:
	return str(NETWORK.get_station(station_id).get("region", ""))

## Preço do trecho em reais; -1 quando o trecho não existe (mesma estação ou id desconhecido).
static func fare(from_id: String, to_id: String) -> int:
	var a := zone(from_id)
	var b := zone(to_id)
	if a.is_empty() or b.is_empty() or from_id == to_id: return -1
	if a == b: return BALANCE.RAIL_FARE_SAME_ZONE
	var pair := [a, b]
	pair.sort()
	return int(BALANCE.RAIL_FARE_ZONES.get("%s|%s" % pair, -1))

static func ticket_key(from_id: String, to_id: String, trip_serial: int) -> String:
	return "%s>%s#%d" % [from_id, to_id, trip_serial]

## Cobra o bilhete na carteira (qualquer objeto com charge_fee, normalmente Economy).
## `ticket` guarda o último embarque pago; repetir o mesmo embarque (duplo clique, sinal duplicado)
## devolve ok sem novo débito. Sem saldo, nada muda e a razão vai para o painel da estação.
static func buy(wallet, from_id: String, to_id: String, trip_serial: int, ticket: Dictionary) -> Dictionary:
	var price := fare(from_id, to_id)
	if price <= 0: return {"ok": false, "charged": 0, "fare": price, "reason": "Trecho indisponível."}
	var key := ticket_key(from_id, to_id, trip_serial)
	if str(ticket.get("paid_key", "")) == key: return {"ok": true, "charged": 0, "fare": price, "reason": ""}
	if wallet == null or not wallet.charge_fee(price):
		return {"ok": false, "charged": 0, "fare": price,
			"reason": "Saldo insuficiente: o bilhete custa R$ %d." % price}
	ticket["paid_key"] = key
	ticket["amount"] = price
	ticket["settled"] = false
	return {"ok": true, "charged": price, "fare": price, "reason": ""}

## Chegada ao destino: o bilhete foi usado e não pode mais ser devolvido.
static func settle(ticket: Dictionary) -> void:
	if ticket.has("paid_key"): ticket["settled"] = true

## Viagem interrompida antes de chegar (morte, prisão): devolve o bilhete daquele embarque uma
## única vez. `settled` vira true antes do crédito, então um segundo evento no mesmo quadro (morte
## e prisão juntas, _exit_tree depois do cancelamento) encontra o bilhete já liquidado.
## Devolve o valor creditado (0 quando não havia o que devolver).
static func refund(wallet, ticket: Dictionary) -> int:
	if not ticket.has("paid_key") or bool(ticket.get("settled", true)): return 0
	var amount := int(ticket.get("amount", 0))
	ticket["settled"] = true
	if amount <= 0 or wallet == null or not wallet.refund_fee(amount): return 0
	return amount
