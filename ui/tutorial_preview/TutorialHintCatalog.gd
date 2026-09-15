class_name TutorialHintCatalog
extends RefCounted
## Catálogo estático (PT/EN) de dicas contextuais discretas para a prévia de
## tutorial isolada em ui/tutorial_preview/.
##
## Não depende de Localization.gd nem se registra nele -- é um catálogo
## próprio, autocontido, para este apresentador isolado. Quando a Astra
## integrar de verdade (save real, HUD real), ela decide se migra estes
## textos para o sistema de i18n oficial ou mantém este catálogo.
##
## 7 contextos cobertos (conforme pedido): primeiro porta-malas, capacidade
## do loadout, abrigo do frio, loja térmica, túnel, item raro e busca
## policial fora de uma casa. Textos curtos de propósito.

const ORDER: Array[String] = [
	"first_trunk",
	"loadout_capacity",
	"cold_shelter",
	"thermal_shop",
	"tunnel",
	"rare_item",
	"police_search",
]

const HINTS := {
	"first_trunk": {
		"pt": {
			"eyebrow": "PORTA-MALAS",
			"title": "A Monaliza tem um baú",
			"body": "Compre armas ou pegue as que sobrarem depois de uma confusão e guarde aqui. Seu loadout acompanha você: a Monaliza é sua, só sua, durante toda esta jornada.",
		},
		"en": {
			"eyebrow": "TRUNK",
			"title": "Monaliza has a stash",
			"body": "Buy weapons or pick up what is left after a fight and store them here. Your loadout travels with you: Monaliza is yours, and yours alone, throughout this journey.",
		},
	},
	"loadout_capacity": {
		"pt": {
			"eyebrow": "CAPACIDADE",
			"title": "Seu equipamento, sempre com você",
			"body": "Curta, longa, corpo a corpo e granada. Trocar uma arma devolve a anterior ao porta-malas.",
		},
		"en": {
			"eyebrow": "CAPACITY",
			"title": "Your gear, always with you",
			"body": "Sidearm, long gun, melee and grenade. Swapping one returns the old weapon to the trunk.",
		},
	},
	"cold_shelter": {
		"pt": {
			"eyebrow": "FRIO",
			"title": "Sua temperatura está caindo",
			"body": "Procure abrigo ou uma lareira. Quando a temperatura zera, o frio tira sua vida aos poucos.",
		},
		"en": {
			"eyebrow": "COLD",
			"title": "Your temperature is dropping",
			"body": "Find shelter or a fireplace. At zero temperature, cold gradually drains your health.",
		},
	},
	"thermal_shop": {
		"pt": {
			"eyebrow": "LOJA TÉRMICA",
			"title": "Antes de subir, prepare um casaco",
			"body": "Compre ou equipe uma parka no Último Abrigo ou na Union, no porto. Procure a camiseta no mapa. Carros e lareiras recuperam calor.",
		},
		"en": {
			"eyebrow": "THERMAL SHOP",
			"title": "Before the climb, pack a warm coat",
			"body": "Buy or equip a parka at Último Abrigo or Union in the harbor. Look for the shirt on the map. Cars and fireplaces restore warmth.",
		},
	},
	"tunnel": {
		"pt": {
			"eyebrow": "TÚNEL",
			"title": "Visibilidade reduzida à frente",
			"body": "Diminua a velocidade e acenda os faróis antes de entrar.",
		},
		"en": {
			"eyebrow": "TUNNEL",
			"title": "Low visibility ahead",
			"body": "Slow down and turn on your headlights before you go in.",
		},
	},
	"rare_item": {
		"pt": {
			"eyebrow": "ITEM RARO",
			"title": "Encontrou algo especial",
			"body": "Arma rara recolhida e preservada. Se o espaço estiver ocupado, organize seu equipamento no porta-malas da Monaliza.",
		},
		"en": {
			"eyebrow": "RARE ITEM",
			"title": "You found something special",
			"body": "Rare weapon collected and kept safe. If its slot is occupied, organize your equipment in Monaliza's trunk.",
		},
	},
	"police_search": {
		"pt": {
			"eyebrow": "BUSCA POLICIAL",
			"title": "Viram você entrar",
			"body": "A polícia revista a entrada da casa. Espere a busca esfriar antes de sair.",
		},
		"en": {
			"eyebrow": "POLICE SEARCH",
			"title": "They saw you go in",
			"body": "Police are searching outside the house. Wait it out before you leave.",
		},
	},
}

const DEFAULT_LOCALE := "pt"

static func ids() -> Array[String]:
	return ORDER.duplicate()

static func has_hint(id: String) -> bool:
	return HINTS.has(id)

## Retorna {eyebrow, title, body} no idioma pedido ("pt" ou "en"). Cai para
## DEFAULT_LOCALE se o idioma pedido não existir para o id, e retorna um
## Dictionary vazio se o id não existir no catálogo.
static func get_hint(id: String, locale: String = DEFAULT_LOCALE) -> Dictionary:
	if not HINTS.has(id):
		return {}
	var by_locale: Dictionary = HINTS[id]
	if by_locale.has(locale):
		return by_locale[locale]
	return by_locale.get(DEFAULT_LOCALE, {})
