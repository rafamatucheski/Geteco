class_name OutfitCatalog
extends RefCounted

const OUTFITS = {
	"dante_classic": {
		"id": "dante_classic",
		"name": "STREETWEAR URBANO",
		"district": "Centro Urbano",
		"price": 0,
		"description": "O clássico visual do Dante: jaqueta preta bomber com capuz, calça cargo, boné preto estruturado e tênis de cano alto.",
		"jacket_color": Color("121214"),
		"pants_color": Color("18181b"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "cap",
		"headwear_color": Color("1a1a1e"),
		"accessory_type": "shades",
		"shoes_color": Color(0.06, 0.06, 0.08),
		"shirt_style": "hoodie",
		"trim_color": Color(0.85, 0.88, 0.92)
	},
	"dante_suit": {
		"id": "dante_suit",
		"name": "TERNO MAFIOSO VIP",
		"district": "Centro Urbano",
		"price": 2500,
		"description": "Terno de corte italiano preto de alta costura, gravata vermelha de seda, relógio dourado e sapato de verniz.",
		"jacket_color": Color("1a1a20"),
		"pants_color": Color("1a1a20"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "hair_only",
		"headwear_color": Color(0.08, 0.08, 0.10),
		"accessory_type": "tie_red",
		"shoes_color": Color("0d0d10"),
		"shirt_style": "dress_shirt",
		"trim_color": Color("d63031")
	},
	"dante_arctic": {
		"id": "dante_arctic",
		"name": "PARKA ÁRTICA DA NEVE",
		"district": "Distrito do Gelo",
		"price": 1800,
		"description": "Casaco térmico pesado azul ártico com capuz acolchoado de pele polar, gorro de lã e luvas térmicas para nevascas.",
		"jacket_color": Color("2e86de"),
		"pants_color": Color("222f3e"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "beanie",
		"headwear_color": Color("0abde3"),
		"accessory_type": "fur_hood",
		"shoes_color": Color("10ac84"),
		"shirt_style": "heavy_parka",
		"trim_color": Color("f1f2f6")
	},
	"dante_trench": {
		"id": "dante_trench",
		"name": "SOBRETUDO DE LÃ & CACHECOL",
		"district": "Distrito do Gelo",
		"price": 2200,
		"description": "Sobretudo longo cinza chumbo de lã britânica, cachecol vermelho escarlate e luvas de couro nobre.",
		"jacket_color": Color("353b48"),
		"pants_color": Color("2f3640"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "hair_only",
		"headwear_color": Color(0.08, 0.08, 0.10),
		"accessory_type": "scarf_red",
		"shoes_color": Color("191919"),
		"shirt_style": "trenchcoat",
		"trim_color": Color("e84118")
	},
	"dante_cowboy": {
		"id": "dante_cowboy",
		"name": "PISTOLEIRO DO DESERTO",
		"district": "Terra Devastada / Deserto",
		"price": 1900,
		"description": "Chapéu Stetson marrom de abas largas, colete de couro cru, bandana vermelha de pistoleiro e botas com esporas.",
		"jacket_color": Color("8c532b"),
		"pants_color": Color("3e4b5b"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "cowboy_hat",
		"headwear_color": Color("5c381e"),
		"accessory_type": "bandana",
		"shoes_color": Color("4a2810"),
		"shirt_style": "vest",
		"trim_color": Color("c0392b")
	},
	"dante_madmax": {
		"id": "dante_madmax",
		"name": "SOBREVIVENTE DA ESTRADA",
		"district": "Terra Devastada / Deserto",
		"price": 2400,
		"description": "Colete tático de couro reforçado com ombreira de aço usinado, óculos anti-poeira e calça cargo desgastada.",
		"jacket_color": Color("2d3436"),
		"pants_color": Color("636e72"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "goggles",
		"headwear_color": Color("e17055"),
		"accessory_type": "shoulder_pad",
		"shoes_color": Color("2d3436"),
		"shirt_style": "tactical_vest",
		"trim_color": Color("b2bec3")
	},
	"dante_lumberjack": {
		"id": "dante_lumberjack",
		"name": "LENHADOR DA FLORESTA",
		"district": "Bosque dos Pinheiros",
		"price": 1500,
		"description": "Camisa xadrez flanela vermelha e preta, suspensórios rústicos de couro, gorro verde e botas de montanha reforçadas.",
		"jacket_color": Color("b71540"),
		"pants_color": Color("1e3799"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "beanie",
		"headwear_color": Color("079992"),
		"accessory_type": "suspenders",
		"shoes_color": Color("6a411f"),
		"shirt_style": "flannel",
		"trim_color": Color("0c2461")
	},
	"dante_ghillie": {
		"id": "dante_ghillie",
		"name": "INFILTRAÇÃO TÁTICA CAMO",
		"district": "Bosque dos Pinheiros",
		"price": 3000,
		"description": "Farda militar camuflada florestal em verde-oliva e marrom, colete molle tático com carregadores e pintura de combate.",
		"jacket_color": Color("3867d6"),
		"pants_color": Color("20bf6b"),
		"skin_color": Color(0.86, 0.70, 0.56),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "tactical_helmet",
		"headwear_color": Color("2b4c1f"),
		"accessory_type": "camo_vest",
		"shoes_color": Color("1b2a15"),
		"shirt_style": "camo_jacket",
		"trim_color": Color("4b6528")
	},
	"dante_hawaii": {
		"id": "dante_hawaii",
		"name": "SURFISTA TROPICAL VICE",
		"district": "Orla Costeira / Praia",
		"price": 1200,
		"description": "Camisa havaiana floral estampada aberta no peito, bermuda d'água turquesa, colar praiano e óculos espelhados.",
		"jacket_color": Color("eb4d4b"),
		"pants_color": Color("22a6b3"),
		"skin_color": Color(0.88, 0.72, 0.58),
		"hair_color": Color(0.12, 0.10, 0.08),
		"headwear_type": "hair_only",
		"headwear_color": Color(0.12, 0.10, 0.08),
		"accessory_type": "shades",
		"shoes_color": Color("f0932b"),
		"shirt_style": "hawaiian",
		"trim_color": Color("f9ca24")
	},
	"dante_badboy": {
		"id": "dante_badboy",
		"name": "REGATA FITNESS & BONÉ REVERSO",
		"district": "Orla Costeira / Praia",
		"price": 1400,
		"description": "Regata preta atlética cavada com corte moderno, bermuda esportiva, boné virado para trás e óculos de sol polarizados.",
		"jacket_color": Color("130f40"),
		"pants_color": Color("30336b"),
		"skin_color": Color(0.88, 0.72, 0.58),
		"hair_color": Color(0.08, 0.08, 0.10),
		"headwear_type": "cap_backwards",
		"headwear_color": Color("eb4d4b"),
		"accessory_type": "shades",
		"shoes_color": Color("ffffff"),
		"shirt_style": "tank_top",
		"trim_color": Color("ffffff")
	}
}

const ORDER = [
	"dante_classic",
	"dante_suit",
	"dante_arctic",
	"dante_trench",
	"dante_cowboy",
	"dante_madmax",
	"dante_lumberjack",
	"dante_ghillie",
	"dante_hawaii",
	"dante_badboy"
]

static func get_all_outfits() -> Array:
	var list := []
	for id in ORDER:
		list.append(OUTFITS[id])
	return list

static func get_outfit(id: String) -> Dictionary:
	return OUTFITS.get(id, OUTFITS["dante_classic"])

static func get_districts() -> Array[String]:
	return [
		"Todos",
		"Centro Urbano",
		"Distrito do Gelo",
		"Terra Devastada / Deserto",
		"Bosque dos Pinheiros",
		"Orla Costeira / Praia"
	]
