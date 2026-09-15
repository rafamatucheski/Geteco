class_name RaceCatalog
extends RefCounted

## Catálogo de corridas clandestinas noturnas. Cada entrada vira uma
## NightRaceController própria, instanciada por CityDemo._spawn_world_extras().
## Adicionar uma corrida nova = adicionar uma entrada aqui, nada mais.

const RACES := {
	"sprint_doca": {
		"id": "sprint_doca",
		"name": "SPRINT DA DOCA",
		"length_label": "CURTA",
		"start": Vector2(1850, 160),
		"checkpoints": [Vector2(2140, 250)],
		"reward": 200,
		"best_time_bonus": 100,
	},
	"volta_centro": {
		"id": "volta_centro",
		"name": "VOLTA DO CENTRO",
		"length_label": "MÉDIA",
		"start": Vector2(300, 300),
		"checkpoints": [Vector2(1400, 300), Vector2(1400, 950), Vector2(300, 950)],
		"reward": 400,
		"best_time_bonus": 200,
	},
	"circuito_oeste_leste": {
		"id": "circuito_oeste_leste",
		"name": "CIRCUITO OESTE-LESTE",
		"length_label": "LONGA",
		"start": Vector2(-150, 150),
		"checkpoints": [Vector2(600, 1080), Vector2(1400, 950), Vector2(1850, 160), Vector2(850, 210)],
		"reward": 750,
		"best_time_bonus": 350,
	},
	"rota_cobras": {
		"id": "rota_cobras",
		"name": "ROTA DOS COBRAS",
		"length_label": "MÉDIA — ARRISCADA",
		"start": Vector2(480, 350),
		"checkpoints": [Vector2(610, 205), Vector2(850, 210), Vector2(850, 1080)],
		"reward": 500,
		"best_time_bonus": 250,
	},
	"contorno_oeste": {
		"id": "contorno_oeste",
		"name": "CONTORNO OESTE",
		"length_label": "CURTA",
		"start": Vector2(-100, 200),
		"checkpoints": [Vector2(300, 300), Vector2(300, 950)],
		"reward": 250,
		"best_time_bonus": 120,
	},
}

static func get_all() -> Array:
	return RACES.values()
