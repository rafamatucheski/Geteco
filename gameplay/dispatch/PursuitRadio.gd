extends RefCounted
## Rádio da central durante a perseguição: uma linha curta no HUD e a mesma fala em voz, montada por
## pedaços como o scanner do GTA (frase-base, rua, sentido; ver PursuitRadioAudio.gd e
## tools/police_radio_voice.py). A rua e o sentido vêm do grafo de ruas.

## Intervalo mínimo entre falas e quanto tempo cada uma fica na tela.
const MIN_INTERVAL := 4.0
const SHOW_SECONDS := 5.5
## Com o suspeito em fuga, a central repete a posição a cada tanto.
const UPDATE_INTERVAL := 14.0

## Nomes de exibição para ids que não viram nome de rua só com maiúsculas. Os nomes são as chaves
## dos pedaços gravados (tools/police_radio_voice.py, STREETS).
const NAMES := {
	"map2_highway_inbound": "rodovia da ponte",
	"map2_highway_outbound": "rodovia da ponte",
	"map2_temporary_return": "retorno da rodovia",
	"mountain_bridge_inbound": "ponte da serra",
	"mountain_bridge_outbound": "ponte da serra",
	"vertice_rural_access": "estrada rural",
	"salvage_access": "acesso do ferro-velho",
	"westgate_service_lane": "via de serviço do Westgate",
	"cobra_approach": "Cobra Court",
	"mountain_pass": "passagem da serra",
	"desert_route_66": "Rota 66",
	"desert_salt_highway": "Estrada do Sal",
	"desert_west_highway": "rodovia oeste",
	"desert_main_street": "rua principal",
	"desert_digo_street": "rua do Digo",
	"desert_bank_approach": "acesso do banco",
	"desert_truck_stop_entry": "posto de caminhoneiros",
}
const PREFIXES := {
	"south_port_": "porto sul",
	"cobra_court_": "Cobra Court",
	"memorial_": "praça do Memorial",
	"mountain_track_": "estrada da serra",
	"continuous_bridge_": "ponte",
	"desert_drag_": "pista de arrancada",
}
## Nomes que pedem "no" em português.
const MASCULINE := ["Quay Boulevard", "retorno da rodovia", "porto sul", "Cobra Court", "acesso do ferro-velho", "acesso do banco", "posto de caminhoneiros"]
## Nomes em inglês (com a preposição) dos lugares que não são nome de rua em inglês.
const ENGLISH := {
	"estrada rural": "on the rural road", "praça do Memorial": "at Memorial Square", "rodovia da ponte": "on the bridge highway",
	"retorno da rodovia": "at the highway turnaround", "via de serviço do Westgate": "on the Westgate service lane",
	"porto sul": "in the south port", "ponte da serra": "on the mountain bridge", "Cobra Court": "at Cobra Court",
	"acesso do ferro-velho": "at the salvage yard access", "estrada da serra": "on the mountain road",
	"passagem da serra": "on the mountain pass", "ponte": "on the bridge", "Rota 66": "on Route 66",
	"Estrada do Sal": "on the Salt Road", "rodovia oeste": "on the west highway", "rua principal": "on Main Street",
	"pista de arrancada": "at the drag strip", "rua do Digo": "on Digo Street", "acesso do banco": "at the bank approach",
	"posto de caminhoneiros": "at the truck stop",
}
const HEADINGS_EN := {"norte": "north", "nordeste": "northeast", "leste": "east", "sudeste": "southeast",
	"sul": "south", "sudoeste": "southwest", "oeste": "west", "noroeste": "northwest"}

var line := ""
var shown_at := -INF
## Pedaços de voz da última fala (PursuitRadioAudio), entregues junto com o texto.
var clips: Array[String] = []
var english := false
var _last_any := -INF
var _last_update := -INF

static func street_name(id: String) -> String:
	if id.is_empty(): return ""
	if NAMES.has(id): return NAMES[id]
	for prefix: String in PREFIXES:
		if id.begins_with(prefix): return PREFIXES[prefix]
	var words := PackedStringArray()
	for word in id.split("_", false):
		words.append(word.capitalize())
	return " ".join(words)

## Sentido cardeal no mapa (o minimapa tem o norte em -Z).
static func heading_name(velocity: Vector3) -> String:
	var planar := Vector2(velocity.x, velocity.z)
	if planar.length() < 1.0: return ""
	var angle := fposmod(rad_to_deg(atan2(planar.x, -planar.y)), 360.0)
	var names := ["norte", "nordeste", "leste", "sudeste", "sul", "sudoeste", "oeste", "noroeste"]
	return names[int(round(angle / 45.0)) % 8]

static func place(router: RefCounted, point: Vector3) -> String:
	if router == null or not router.has_graph(): return ""
	var hit: Dictionary = router.nearest_edge(point)
	if hit.is_empty() or float(hit.distance) > 25.0: return ""
	return street_name(str(hit.edge.get("id", "")))

## "na Union Avenue" / "on Union Avenue" ("" sem rua).
static func at_street(street: String, in_english: bool) -> String:
	if street.is_empty(): return ""
	if in_english: return ENGLISH.get(street, "on " + street)
	return ("no " if MASCULINE.has(street) else "na ") + street

## Fala montada: {"text": String, "clips": Array[String]} para um evento da perseguição.
## Eventos: wanted, escalated, spotted, fleeing, lost, roadblock, evaded.
static func compose(event: String, street := "", heading := "", in_english := false) -> Dictionary:
	var where := at_street(street, in_english)
	var street_clip: Array[String] = []
	if not street.is_empty(): street_clip.append("street:" + street)
	var heading_clip: Array[String] = []
	if not heading.is_empty(): heading_clip.append("heading:" + heading)
	var text := ""
	var keys: Array[String] = []
	match event:
		"wanted":
			text = "Dispatch to all units: suspect wanted, units en route." if in_english else "Central para todas as unidades: suspeito procurado, unidades a caminho."
			keys = ["phrase:all_units", "phrase:wanted"]
		"escalated":
			text = "Dispatch to all units: situation escalating, backup authorized." if in_english else "Central para todas as unidades: situação agravada, reforço autorizado."
			keys = ["phrase:all_units", "phrase:escalated"]
		"spotted":
			text = ("Suspect spotted %s." % where if in_english else "Suspeito avistado %s." % where) if not where.is_empty() else ("Suspect spotted." if in_english else "Suspeito avistado.")
			keys = ["phrase:spotted"]
			keys.append_array(street_clip)
		"fleeing":
			var direction := ""
			if not heading.is_empty(): direction = (", heading " + str(HEADINGS_EN.get(heading, heading))) if in_english else (", sentido " + heading)
			text = ("Suspect fleeing" if in_english else "Suspeito em fuga") + ((" " + where) if not where.is_empty() else "") + direction + "."
			keys = ["phrase:fleeing"]
			keys.append_array(street_clip)
			keys.append_array(heading_clip)
		"lost":
			if in_english: text = "We lost visual%s. Search the area." % ((", last seen " + where) if not where.is_empty() else "")
			else: text = "Perdemos o contato%s. Vasculhem a área." % ((", última posição " + where) if not where.is_empty() else "")
			keys = ["phrase:lost"]
			keys.append_array(street_clip)
			keys.append("phrase:search")
		"roadblock":
			text = ("Roadblock in place" if in_english else "Bloqueio montado") + ((" " + where) if not where.is_empty() else "") + "."
			keys = ["phrase:roadblock"]
			keys.append_array(street_clip)
		"evaded":
			text = "Suspect evaded, call off the search." if in_english else "Suspeito despistou, encerrem a busca."
			keys = ["phrase:evaded"]
	return {"text": text, "clips": keys}

func say(text: String, now: float, urgent := false, voice: Array[String] = []) -> bool:
	if text.is_empty(): return false
	if not urgent and now - _last_any < MIN_INTERVAL: return false
	line = text
	clips = voice
	shown_at = now
	_last_any = now
	_last_update = now
	return true

## Fala de um evento (texto no idioma de texto; os pedaços seguem o idioma de voz no PursuitRadioAudio).
func announce(event: String, now: float, street := "", heading := "", urgent := false) -> bool:
	var composed := compose(event, street, heading, english)
	return say(composed.text, now, urgent, composed.clips)

## Linha visível agora ("" quando expirou).
func current(now: float) -> String:
	return line if now - shown_at <= SHOW_SECONDS else ""

func fleeing(router: RefCounted, point: Vector3, velocity: Vector3, now: float) -> bool:
	if now - _last_update < UPDATE_INTERVAL: return false
	var street := place(router, point)
	if street.is_empty(): return false
	return announce("fleeing", now, street, heading_name(velocity))

func reset() -> void:
	line = ""
	clips = []
	shown_at = -INF
	_last_any = -INF
	_last_update = -INF
