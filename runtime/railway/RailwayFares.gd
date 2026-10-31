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
	return {"ok": true, "charged": price, "fare": price, "reason": ""}
