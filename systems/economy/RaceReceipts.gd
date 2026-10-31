extends RefCounted
## Contratos race_symbols_v1 persistidos. São preços históricos, não o
## catálogo atual. Valores futuros diferentes ficam opacos, a não ser que migrados por
## uma versão explícita do codec. Os símbolos preservam cada lado de forma independente.
const CODEC := "race_symbols_v1"
const PAGE_SIZE := 256
const MAX_SERIAL := 10000000
const MOTO_FEES := [100,200,350,500]
const MOTO_PRIZES := [140,280,490,700]
const SKI := {
	"ski_primeira_descida":[260,120],
	"ski_slalom_pinhal":[480,220],
	"ski_pista_da_sombra":[900,400],
}

static func _serial(suffix: String) -> int:
	if not suffix.is_valid_int(): return 0
	var value := suffix.to_int()
	return value if value>=1 and value<=MAX_SERIAL and suffix==str(value) else 0

static func _identity(kind: String, receipt_id: String) -> Dictionary:
	for side in 2:
		var prefix := "motocross_entry:" if side==0 else "motocross_prize:"
		if kind!=("spend" if side==0 else "reward") or not receipt_id.begins_with(prefix): continue
		var serial := _serial(receipt_id.trim_prefix(prefix))
		return {} if serial==0 else {"domain":"motocross","side":side,"serial":serial}
	if kind!="reward": return {}
	for course in SKI:
		for side in 2:
			var prefix := ("ski_finish:" if side==0 else "ski_record:")+str(course)+":"
			if not receipt_id.begins_with(prefix): continue
			var serial := _serial(receipt_id.trim_prefix(prefix))
			return {} if serial==0 else {"domain":course,"side":side,"serial":serial}
	return {}

static func _pages(data: Dictionary, domain: String) -> Dictionary:
	return data.get("receipt_ledger",{}).get("events",{}).get("pages",{}).get(domain,{})

static func _code(data: Dictionary, domain: String, serial: int) -> int:
	var page: String = _pages(data,domain).get(str(int(float(serial-1)/PAGE_SIZE)),"")
	return 0 if page.is_empty() else page.unicode_at((serial-1)%PAGE_SIZE)-65

static func _part(code: int, domain: String, side: int) -> int:
	if domain=="motocross": return code%5 if side==0 else int(float(code)/5)
	return (code>>side)&1

static func _amount(domain: String, side: int, part: int) -> int:
	if domain=="motocross": return int(MOTO_FEES[part-1] if side==0 else MOTO_PRIZES[part-1])
	return int(SKI[domain][side])

## Só o recibo consultado é reconstruído. Nunca exporta histórico sintético.
static func lookup(data: Dictionary, kind: String, receipt_id: String) -> Dictionary:
	var identity := _identity(kind,receipt_id)
	if identity.is_empty(): return {}
	var part := _part(_code(data,identity.domain,int(identity.serial)),identity.domain,int(identity.side))
	if part==0: return {}
	return {"kind":kind,"item":receipt_id,"amount":_amount(identity.domain,int(identity.side),part)}

static func record(data: Dictionary, kind: String, receipt_id: String, amount: int) -> bool:
	var identity := _identity(kind,receipt_id)
	if identity.is_empty(): return false
	var domain: String = identity.domain
	var side := int(identity.side)
	var part := 1
	if domain=="motocross":
		part=(MOTO_FEES if side==0 else MOTO_PRIZES).find(amount)+1
		if part==0: return false
	elif amount!=int(SKI[domain][side]): return false
	var serial := int(identity.serial)
	var previous := _code(data,domain,serial)
	if _part(previous,domain,side)!=0: return false
	var next := previous+part*(1 if side==0 else 5) if domain=="motocross" else previous|(1<<side)
	if not data.has("receipt_ledger"): data.receipt_ledger={"version":3,"streams":{}}
	var ledger: Dictionary = data.receipt_ledger
	ledger.version=3
	data.version=3
	if not ledger.has("events"): ledger.events={"codec":CODEC,"pages":{}}
	if not ledger.events.pages.has(domain): ledger.events.pages[domain]={}
	var pages: Dictionary = ledger.events.pages[domain]
	var page_key := str(int(float(serial-1)/PAGE_SIZE))
	var offset := (serial-1)%PAGE_SIZE
	var page: String = pages.get(page_key,"A".repeat(PAGE_SIZE))
	# Strings são valores imutáveis. Só esta página limitada é trocada; cópias
	# de uma carteira mantêm a string antiga e todas as outras páginas intactas.
	pages[page_key]=page.substr(0,offset)+String.chr(65+next)+page.substr(offset+1)
	return true

## A escolha do serial combina só eventos pagos reais com o leitor opaco.
## Páginas validadas não vazias tornam a maior página a oficial; varre no máximo
## essa página de trás para frente, nunca deduz que buracos nela foram pagos.
static func ski_highest(data: Dictionary, course_id: String) -> int:
	if not SKI.has(course_id): return 0
	var pages := _pages(data,course_id)
	var highest_page := -1
	for key in pages: highest_page=maxi(highest_page,int(key))
	if highest_page<0: return 0
	var page: String = pages[str(highest_page)]
	for offset in range(PAGE_SIZE-1,-1,-1):
		if page.unicode_at(offset)!=65: return highest_page*PAGE_SIZE+offset+1
	return 0

## Resumo exato e limitado para o validador entre contratos do Motocross. As contagens mantêm
## todas as 25 combinações de conteúdo independentes, não só vitórias ou o maior serial.
static func motocross_summary(data: Dictionary) -> Dictionary:
	var counts: Array[int]=[]
	counts.resize(25); counts.fill(0)
	var highest_entry := 0
	var pages := _pages(data,"motocross")
	for key in pages:
		var page: String = pages[key]
		var first := int(key)*PAGE_SIZE+1
		for offset in PAGE_SIZE:
			var code := page.unicode_at(offset)-65
			if code%5!=0:
				counts[code]+=1
				highest_entry=maxi(highest_entry,first+offset)
	return {"counts":counts,"highest_entry":highest_entry}

static func validate(data: Dictionary) -> bool:
	var events: Variant = data.get("receipt_ledger",{}).get("events")
	if not events is Dictionary or events.size()!=2 or events.get("codec")!=CODEC or not events.get("pages") is Dictionary: return false
	if events.pages.is_empty() or events.pages.size()>1+SKI.size(): return false
	for domain in events.pages:
		if domain!="motocross" and not SKI.has(domain): return false
		var pages: Variant = events.pages[domain]
		if not pages is Dictionary or pages.is_empty() or pages.size()>ceili(float(MAX_SERIAL)/PAGE_SIZE): return false
		for key in pages:
			if not key is String or not key.is_valid_int(): return false
			var index: int = key.to_int()
			if index<0 or index>int(float(MAX_SERIAL-1)/PAGE_SIZE) or key!=str(index): return false
			var page: Variant = pages[key]
			if not page is String or page.length()!=PAGE_SIZE: return false
			var any := false
			for offset in PAGE_SIZE:
				var code: int = page.unicode_at(offset)-65
				if code<0 or code>(24 if domain=="motocross" else 3): return false
				if code!=0:
					if index*PAGE_SIZE+offset+1>MAX_SERIAL: return false
					any=true
			if not any: return false
	# Posse exata: um lado pode ser opaco enquanto o outro é compacto, mas
	# o mesmo recibo canônico nunca pode pertencer aos dois armazenamentos.
	for key_value in data.get("transactions",{}):
		var key := str(key_value)
		var separator := key.find(":")
		if separator>=0 and not lookup(data,key.substr(0,separator),key.substr(separator+1)).is_empty(): return false
	return true
