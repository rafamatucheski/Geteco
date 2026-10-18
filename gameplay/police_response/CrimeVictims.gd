extends RefCounted
## Como a polícia lê uma vítima ferida ou morta pelo jogador, venha o dano de arma ou de
## atropelamento. Antes a regra ficava espalhada no Gameplay: a tiro só "civilian" e
## "emergency" valiam homicídio, e moradores de prédio, trabalhadores do V1, moradores do
## esgoto, contatos do deserto e o público dos eventos viravam no máximo uma agressão de 12
## pontos; atropelar a mesma pessoa valia homicídio sempre, até um Cobra ou um segurança
## cuja ocorrência é do próprio comboio (revisão cruzada de 18/10/2026).
##
## Papel novo de pessoa entra em PERSON_ROLES; papel desconhecido fica em OTHER, que mantém
## o comportamento antigo (agressão a tiro, nunca homicídio) para não transformar alvo,
## veículo ou objeto destrutível em vítima de homicídio.
const POLICE := "police"
const PERSON := "person"
const HOSTILE := "hostile"
const OWNER_HANDLED := "owner_handled"
const OTHER := "other"
const PERSON_ROLES := ["civilian", "emergency", "ambient_worker", "urban_routine", "sewer_resident",
	"desert_contact", "desert_digo_mechanic", "digo_instructor", "jessica", "vicente_crew", "motocross_spectator"]
## Gangue em combate: ferir um Cobra (ou um fora-da-lei, que herda o papel) não é denúncia.
const HOSTILE_ROLES := ["cobra"]

static func classify(actor: Object) -> String:
	if not is_instance_valid(actor) or not actor is Node: return OTHER
	# Seguranças do comboio e da garagem: quem os contrata atribui o crime (ArmoredTransport, Guard).
	if actor.get_meta("local_security", false): return OWNER_HANDLED
	var role := String(actor.get_meta("gameplay_role", ""))
	if role == "police": return POLICE
	if role in HOSTILE_ROLES: return HOSTILE
	if role in PERSON_ROLES: return PERSON
	return OTHER

## Matar esta vítima a tiro é homicídio (30 pontos), não agressão.
static func killing_is_murder(victim_class: String) -> bool:
	return victim_class == PERSON

## O jogador comete crime ao ferir esta vítima.
static func reports_crime(victim_class: String) -> bool:
	return victim_class not in [HOSTILE, OWNER_HANDLED]
