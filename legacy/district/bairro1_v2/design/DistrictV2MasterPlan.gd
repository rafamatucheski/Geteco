class_name DistrictV2MasterPlan
extends RefCounted

## Contrato espacial do Bairro 1 V2.
## Dono: Codex. Claude constrói ruas/lotes a partir destes dados; Antigravity
## só pode posicionar landmarks dentro dos `buildable_lots` correspondentes.

const PLAN_VERSION := 1
const DISTRICT_BOUNDS := Rect2(0, 0, 2000, 1600)
const PORT_ACCESS := Vector2(1800, 90)
const PLAYER_SPAWN := Vector2(250, 1080)

const BUILDABLE_LOTS: Array[Dictionary] = [
	{"id": "park_west", "kind": "park", "rect": Rect2(80, 790, 360, 510), "entrance": Vector2(440, 1010)},
	{"id": "market_north", "kind": "market", "rect": Rect2(760, 270, 230, 250), "entrance": Vector2(875, 560)},
	{"id": "terminal_north", "kind": "terminal", "rect": Rect2(1140, 250, 260, 270), "entrance": Vector2(1270, 560)},
	{"id": "civic_block", "kind": "community_school", "rect": Rect2(770, 770, 200, 250), "entrance": Vector2(870, 740)},
	{"id": "residential_north", "kind": "residential", "rect": Rect2(1130, 770, 230, 250), "entrance": Vector2(1245, 740)},
	{"id": "garage_east", "kind": "garage", "rect": Rect2(1540, 800, 270, 220), "entrance": Vector2(1510, 910)},
	{"id": "residential_south_west", "kind": "residential", "rect": Rect2(770, 1220, 200, 210), "entrance": Vector2(870, 1180)},
	{"id": "residential_south_east", "kind": "residential", "rect": Rect2(1130, 1220, 230, 210), "entrance": Vector2(1245, 1180)},
	{"id": "warehouse_south_east", "kind": "warehouse", "rect": Rect2(1540, 1210, 330, 220), "entrance": Vector2(1510, 1320)},
	{"id": "bar_spawn", "kind": "bar_laundromat", "rect": Rect2(420, 930, 200, 180), "entrance": Vector2(510, 890)},
]

## Eixos de rua, em ordem de prioridade. Claude pode suavizar curvas, mas não
## pode mover cruzamentos ou entradas sem atualizar este contrato.
static func get_road_spines() -> Array[Dictionary]:
	return [
		{"id": "avenida_entrada", "width": 164.0, "points": PackedVector2Array([Vector2(-60, 1220), Vector2(160, 1120), Vector2(420, 900), Vector2(610, 700), Vector2(700, 640)])},
		{"id": "eixo_comercial", "width": 164.0, "points": PackedVector2Array([Vector2(700, 640), Vector2(1050, 640), Vector2(1450, 650), Vector2(1650, 680)])},
		{"id": "acesso_porto", "width": 112.0, "points": PackedVector2Array([Vector2(1650, 680), Vector2(1730, 440), Vector2(1780, 220), PORT_ACCESS])},
		{"id": "rua_civica", "width": 112.0, "points": PackedVector2Array([Vector2(700, 640), Vector2(700, 1120), Vector2(700, 1450)])},
		{"id": "rua_central", "width": 112.0, "points": PackedVector2Array([Vector2(1050, 640), Vector2(1050, 1450)])},
		{"id": "rua_industrial", "width": 112.0, "points": PackedVector2Array([Vector2(1450, 650), Vector2(1450, 1450)])},
		{"id": "travessa_sul", "width": 112.0, "points": PackedVector2Array([Vector2(700, 1150), Vector2(1450, 1150)])},
		{"id": "beco_mercado", "width": 56.0, "points": PackedVector2Array([Vector2(760, 730), Vector2(990, 730)])},
		{"id": "beco_residencial", "width": 56.0, "points": PackedVector2Array([Vector2(1108, 850), Vector2(1392, 850)])},
		{"id": "beco_galpao", "width": 56.0, "points": PackedVector2Array([Vector2(1505, 1120), Vector2(1870, 1120)])},
	]

## Zonas que jamais podem receber prédios/props sólidos. O layout calcula
## faixas reais a partir de ROAD_SPINES; estas zonas são limites adicionais.
const NON_BUILDABLE_ZONES: Array[Dictionary] = [
	{"id": "north_canal_port", "rect": Rect2(0, 0, 2000, 220)},
	{"id": "south_rail_corridor", "rect": Rect2(0, 1460, 2000, 140)},
	{"id": "west_entry_clearance", "rect": Rect2(0, 1010, 150, 300)},
	{"id": "port_gate_clearance", "rect": Rect2(1710, 0, 290, 260)},
]

const REQUIRED_MARKERS := {
	&"PlayerSpawn": PLAYER_SPAWN,
	&"PortApproach": PORT_ACCESS,
	&"MarketEntrance": Vector2(875, 560),
	&"TerminalStop": Vector2(1270, 560),
	&"ParkEntrance": Vector2(440, 1010),
	&"GarageEntrance": Vector2(1510, 910),
	&"WarehouseEntrance": Vector2(1510, 1320),
	&"RailUnderpass": Vector2(1050, 1450),
	&"ExitDistrict2": Vector2(2000, 680),
	&"ExitDistrict3": Vector2(1900, 1450),
}

const INITIAL_ROUTE := [
	&"PlayerSpawn", &"MarketEntrance", &"GarageEntrance", &"WarehouseEntrance", &"PortApproach",
]


static func get_buildable_lot(lot_id: StringName) -> Dictionary:
	for lot in BUILDABLE_LOTS:
		if StringName(lot["id"]) == lot_id:
			return lot.duplicate(true)
	return {}
