class_name AchievementCatalog
extends RefCounted

## Conquistas estilo "achievement" (World of Warcraft / Xbox) — desbloqueadas
## automaticamente por Player._check_achievements() conforme o jogador
## acumula progresso. Cada critério é "chave_da_stat>=valor"; ver o
## dicionário `stats` montado em Player._achievement_stats().

const ACHIEVEMENTS := {
	"first_lead": {
		"name": "PRIMEIRO ACHADO", "check": "collectibles>=1",
		"desc": "Encontre seu primeiro achado escondido pelo mapa.",
	},
	"secret_lead": {
		"name": "NA TRILHA", "check": "collectibles>=3",
		"desc": "Encontre 3 achados escondidos pelo mapa.",
	},
	"lead_hunter": {
		"name": "CAÇADOR DE PISTAS", "check": "collectibles>=5",
		"desc": "Encontre 5 achados escondidos.",
	},
	"map_explorer": {
		"name": "EXPLORADOR COMPLETO", "check": "collectibles>=10",
		"desc": "Encontre os 10 achados conhecidos do mapa atual.",
	},
	"first_race": {
		"name": "PÉ NA TÁBUA", "check": "races>=1",
		"desc": "Termine sua primeira corrida clandestina noturna.",
	},
	"street_racer": {
		"name": "PILOTO DAS SOMBRAS", "check": "races>=5",
		"desc": "Termine 5 corridas clandestinas.",
	},
	"personal_best": {
		"name": "RECORDE PESSOAL", "check": "bests>=1",
		"desc": "Bata seu próprio recorde numa corrida clandestina.",
	},
	"first_ski_descent": {
		"name": "PRIMEIRA DESCIDA", "check": "ski_races>=1",
		"desc": "Conclua sua primeira prova de ski no Cume Branco.",
	},
	"ski_mountain_champion": {
		"name": "REI DA MONTANHA", "check": "ski_races>=3",
		"desc": "Conclua três provas de ski na face norte.",
	},
	"mountain_legend": {
		"name": "A SOMBRA NA NEVE", "check": "mountain_clues>=3",
		"desc": "Reúna todas as evidências da expedição desaparecida.",
	},
	"first_grand": {
		"name": "GRANA SUJA", "check": "money>=2000",
		"desc": "Acumule $2.000 no bolso.",
	},
	"shark": {
		"name": "TUBARÃO", "check": "money>=10000",
		"desc": "Acumule $10.000 no bolso.",
	},
	"armed_up": {
		"name": "ARSENAL PESSOAL", "check": "weapons>=3",
		"desc": "Tenha 3 armas diferentes no inventário.",
	},
	"armored": {
		"name": "BLINDADO", "check": "armor>=100",
		"desc": "Encha o colete até 100%.",
	},
	"most_wanted": {
		"name": "PROCURADO", "check": "wanted_stars>=3",
		"desc": "Alcance 3 estrelas de procurado.",
	},
	"drift_apprentice": {
		"name": "PÉ QUENTE", "check": "best_drift_score>=2000",
		"desc": "Faça 2.000 pontos numa zona de drift.",
	},
	"drift_master": {
		"name": "REI DA FUMAÇA", "check": "best_drift_score>=6000",
		"desc": "Faça 6.000 pontos numa zona de drift.",
	},
	"first_scrap": {
		"name": "PRIMEIRA SUCATA", "check": "chop_shop_deliveries>=1",
		"desc": "Desmanche seu primeiro carro no desmanche dos Cobras.",
	},
	"junkyard_king": {
		"name": "REI DO FERRO-VELHO", "check": "chop_shop_deliveries>=10",
		"desc": "Desmanche 10 carros no desmanche dos Cobras.",
	},
}

## One-time rewards. Stored unlocked IDs also act as receipts; old saves
## retain earned badges without receiving the same payout after restoration.
const CASH_REWARDS := {
	"first_lead": 50, "secret_lead": 100, "lead_hunter": 150, "map_explorer": 400,
	"first_race": 100, "street_racer": 250, "personal_best": 100,
	"first_ski_descent": 100, "ski_mountain_champion": 250, "mountain_legend": 200,
	"first_grand": 50, "shark": 200, "armed_up": 100, "armored": 50,
	"most_wanted": 100, "drift_apprentice": 100, "drift_master": 250,
	"first_scrap": 100, "junkyard_king": 250,
}

static func cash_reward(id: String) -> int:
	return int(CASH_REWARDS.get(id, 0))

## Avalia "chave>=valor" contra o dicionário de stats atual do jogador.
static func evaluate(stats: Dictionary, achievement_id: String) -> bool:
	var entry: Dictionary = ACHIEVEMENTS.get(achievement_id, {})
	if entry.is_empty():
		return false
	var parts := String(entry.get("check", "")).split(">=")
	if parts.size() != 2:
		return false
	var stat_value: float = float(stats.get(parts[0].strip_edges(), 0))
	var threshold: float = float(parts[1].strip_edges())
	return stat_value >= threshold
