extends RefCounted
## Só estes contratos recorrentes determinísticos usam faixas compactas e contíguas.
## Recibos opacos existentes ficam exatos; lacunas/IDs não canônicos continuam opacos.
const VERSION := 2
const RACES := preload("res://systems/economy/RaceReceipts.gd")
## Estes valores são contratos de recibo V2 persistidos, não preços atuais do catálogo.
## Nunca os mude quando um preço da loja mudar: outro preço fica opaco ou
## exige uma nova versão explícita de domínio/livro com migração compatível.
const DOMAINS := {
	"motocross_rental":{"kind":"spend","prefix":"motocross_rental:","amount":35,"max":10000000},
	"ski_rental":{"kind":"spend","prefix":"ski_rental:","amount":250,"max":1000000},
	"northgate_auto":{"kind":"spend","prefix":"northgate_auto:","amount":100,"max":10000000},
	"tonico_drink":{"kind":"spend","prefix":"tonico_drink_","amount":20,"max":1000000},
	"tonico_register":{"kind":"reward","prefix":"tonico_register_","amount":180,"max":1000000},
	"drag_night_finish":{"kind":"reward","prefix":"drag_night_finish:","amount":600,"max":1000000},
	"drag_night_win":{"kind":"reward","prefix":"drag_night_win:","amount":300,"max":1000000},
}

static func _classify(kind: String, receipt_id: String) -> Dictionary:
	for domain in DOMAINS:
		var spec: Dictionary = DOMAINS[domain]
		if kind!=spec.kind or not receipt_id.begins_with(spec.prefix): continue
		var suffix := receipt_id.trim_prefix(spec.prefix)
		if not suffix.is_valid_int(): return {}
		var serial := suffix.to_int()
		if serial<1 or serial>int(spec.max) or suffix!=str(serial): return {}
		return {"domain":domain,"serial":serial,"amount":int(spec.amount)}
	return {}

static func _stream(data: Dictionary, domain: String) -> Dictionary:
	return data.get("receipt_ledger",{}).get("streams",{}).get(domain,{})

## A consulta reconstrói no máximo o registro pedido, nunca o histórico.
static func lookup(data: Dictionary, kind: String, receipt_id: String) -> Dictionary:
	var key := kind+":"+receipt_id
	var existing: Dictionary = data.get("transactions",{}).get(key,{})
	if not existing.is_empty(): return existing
	var identity := _classify(kind,receipt_id)
	if identity.is_empty(): return RACES.lookup(data,kind,receipt_id)
	var stream := _stream(data,identity.domain)
	if stream.is_empty() or int(identity.serial)<int(stream.first) or int(identity.serial)>int(stream.through): return {}
	return {"kind":kind,"item":receipt_id,"amount":int(identity.amount)}

## True significa que o recibo foi anexado à faixa compacta. False instrui
## a Economy a preservar o registro comum, com a semântica original da API.
static func record(data: Dictionary, kind: String, receipt_id: String, amount: int) -> bool:
	if RACES.record(data,kind,receipt_id,amount): return true
	var identity := _classify(kind,receipt_id)
	if identity.is_empty() or amount!=int(identity.amount): return false
	var domain: String = identity.domain
	var serial := int(identity.serial)
	var stream := _stream(data,domain)
	if stream.is_empty():
		# Esta varredura só acontece antes de um domínio virar compacto pela primeira vez. Registros
		# antigos não são removidos, e até uma lacuna existente continua sendo lacuna real.
		if serial!=highest_serial(data,domain)+1: return false
		if not data.has("receipt_ledger"):
			data.receipt_ledger={"version":VERSION,"streams":{}}
			# O validador antigo da Economy aceita chaves desconhecidas. Sobe o envelope
			# também, para que um build antigo não ignore em silêncio o histórico compacto.
			data.version=2
		data.receipt_ledger.streams[domain]={"first":serial,"through":serial}
		return true
	if serial!=int(stream.through)+1: return false
	stream.through=serial
	return true

static func compact_count(data: Dictionary, domain: String) -> int:
	var stream := _stream(data,domain)
	return 0 if stream.is_empty() else int(stream.through)-int(stream.first)+1

static func compact_highest(data: Dictionary, domain: String) -> int:
	return int(_stream(data,domain).get("through",0))

static func highest_serial(data: Dictionary, domain: String) -> int:
	if not DOMAINS.has(domain): return 0
	var spec: Dictionary = DOMAINS[domain]
	var prefix: String = str(spec.kind)+":"+str(spec.prefix)
	var result := compact_highest(data,domain)
	for key in data.get("transactions",{}):
		# Preserva a antiga reconciliação do Tonico com sufixos legados, incluindo
		# grafias numéricas não canônicas. Elas nunca são compactadas por _classify.
		if str(key).begins_with(prefix): result=maxi(result,str(key).trim_prefix(prefix).to_int())
	return result

static func validate(data: Dictionary) -> bool:
	if not data.has("receipt_ledger"): return data.get("version",1)==1
	if data.get("version")!=2 and data.get("version")!=3: return false
	var ledger: Variant = data.receipt_ledger
	if not ledger is Dictionary or ledger.get("version")!=data.version or not ledger.get("streams") is Dictionary: return false
	if data.version==2:
		if ledger.size()!=2: return false
	else:
		if ledger.size()!=3 or not RACES.validate(data): return false
	if ledger.streams.size()>DOMAINS.size(): return false
	for domain in ledger.streams:
		if not DOMAINS.has(domain): return false
		var stream: Variant = ledger.streams[domain]
		if not stream is Dictionary or stream.size()!=2: return false
		for key in ["first","through"]:
			var value: Variant = stream.get(key)
			if typeof(value) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or float(value)!=floorf(float(value)) or float(value)<1 or float(value)>float(DOMAINS[domain].max): return false
		if int(stream.first)>int(stream.through): return false
	# Recusa posse duplicada de um recibo pelo armazenamento opaco e pelo compacto.
	for key_value in data.get("transactions",{}):
		var key := str(key_value)
		var separator := key.find(":")
		if separator<0: continue
		var identity := _classify(key.substr(0,separator),key.substr(separator+1))
		if identity.is_empty(): continue
		var stream := _stream(data,identity.domain)
		if not stream.is_empty() and int(identity.serial)>=int(stream.first) and int(identity.serial)<=int(stream.through): return false
	return true
