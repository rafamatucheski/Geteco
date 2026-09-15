class_name GangManager
extends Node

## Sistema Central de Gangues, Territórios e Respeito
## Gerencia as 5 facções da cidade e suporta missões de roubo de veículos e guerras de território.

signal respect_changed(gang_id: String, new_respect: int)
signal territory_entered(gang_id: String, gang_name: String)
signal territory_exited(gang_id: String)
signal gang_mission_completed(mission_id: String, reward_money: int, respect_gain: int)

const GANGS := {
	"iron_cobras": {
		"id": "iron_cobras",
		"name": "Os Cobras de Ferro",
		"tag": "COBRAS",
		"district": "city",
		"territory_name": "Mercado Velho & Becos Centrais",
		"bounds": Rect2(70, 70, 710, 440),
		"color": Color("#800000"), # Vinho escuro / Vermelho Sangue
		"gang_car": "cobra_v8",
		"leader": "Don Hector 'Cascavel'",
		"barks": [
			"AQUI É OS COBRAS DE FERRO!",
			"MEXEU COM O BONDE ERRADO!",
			"LARGA O V8 OU MORRE!",
			"DERRUBA ELE!"
		]
	},
	"frost_wolves": {
		"id": "frost_wolves",
		"name": "Lobos de Gelo",
		"tag": "FROST",
		"district": "winter",
		"territory_name": "Montanhas Congeladas & Refinaria",
		"bounds": Rect2(0, 0, 1800, 1200),
		"color": Color("#74b9ff"),
		"gang_car": "winter_suv_heavy",
		"leader": "Viktor Frost",
		"barks": [
			"O GELO NÃO PERDOA!",
			"FOGO NOS INVASORES!",
			"PEGUEM O CARRO DELES!"
		]
	},
	"dust_devils": {
		"id": "dust_devils",
		"name": "Os Cascaveis do Deserto",
		"tag": "DEVILS",
		"district": "desert",
		"territory_name": "Ferro-Velho & Badlands",
		"bounds": Rect2(0, 0, 1800, 1200),
		"color": Color("#e67e22"),
		"gang_car": "dune_buggy",
		"leader": "Tex 'Poeira' Slade",
		"barks": [
			"VAI VIRAR CARCAÇA NO DESERTO!",
			"ATIRA NAS RODAS!",
			"AQUI NINGUÉM PASSA!"
		]
	},
	"dock_syndicate": {
		"id": "dock_syndicate",
		"name": "Sindicato do Cais",
		"tag": "DOCKS",
		"district": "industrial",
		"territory_name": "Porto & Galpões Navais",
		"bounds": Rect2(70, 690, 710, 520),
		"color": Color("#00cec9"),
		"gang_car": "dock_delivery_van",
		"leader": "Capitão Malone",
		"barks": [
			"ISSO É PROPRIEDADE DO PORTO!",
			"CHAMA OS ESTIVADORES!",
			"QUEIMA TUDO!"
		]
	},
	"neon_vipers": {
		"id": "neon_vipers",
		"name": "Os Neon Vipers",
		"tag": "VIPERS",
		"district": "beach",
		"territory_name": "Orla dos Coqueiros & Mansões",
		"bounds": Rect2(0, 0, 1800, 1200),
		"color": Color("#e84393"),
		"gang_car": "sport_coupe",
		"leader": "Tony 'Neon' Valenti",
		"barks": [
			"NINGUÉM ESTRAGA MEU CONVERSÍVEL!",
			"SEGURANÇAS, FOGO NELE!",
			"PEGUEM O CARRO DE VOLTA!"
		]
	}
}

var respect_levels: Dictionary = {
	"iron_cobras": 0,
	"frost_wolves": 0,
	"dust_devils": 0,
	"dock_syndicate": 0,
	"neon_vipers": 0
}

var unlocked_gang_cars: Array[String] = []
var completed_missions: Array[String] = []
var active_territory: String = ""

func _ready() -> void:
	add_to_group("gang_manager")

func get_gang(gang_id: String) -> Dictionary:
	return GANGS.get(gang_id, {})

func get_all_gangs() -> Dictionary:
	return GANGS

func get_respect(gang_id: String) -> int:
	return int(respect_levels.get(gang_id, 0))

func modify_respect(gang_id: String, delta: int) -> void:
	var cur = get_respect(gang_id)
	var new_val = clampi(cur + delta, -100, 100)
	respect_levels[gang_id] = new_val
	respect_changed.emit(gang_id, new_val)

func is_hostile_towards_player(gang_id: String) -> bool:
	return get_respect(gang_id) <= -30

func unlock_gang_car(car_id: String) -> void:
	if not unlocked_gang_cars.has(car_id):
		unlocked_gang_cars.append(car_id)

func is_gang_car_unlocked(car_id: String) -> bool:
	return unlocked_gang_cars.has(car_id)

func check_player_territory(player_pos: Vector2) -> String:
	for gang_id in GANGS:
		var bounds: Rect2 = GANGS[gang_id].get("bounds", Rect2())
		if bounds.has_point(player_pos):
			if active_territory != gang_id:
				active_territory = gang_id
				territory_entered.emit(gang_id, String(GANGS[gang_id].get("name", "")))
			return gang_id
	if active_territory != "":
		territory_exited.emit(active_territory)
		active_territory = ""
	return ""
