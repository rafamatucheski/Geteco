class_name DistrictV2RafaelPlan
extends RefCounted

## Fonte espacial V3 do Bairro 1. Transcrição da planta desenhada por Rafael.
## Esta substitui a proposta anterior do Codex para qualquer trabalho novo.

const PLAN_VERSION := 3
const DISTRICT_BOUNDS := Rect2(0, 0, 2400, 1600)
const PLAYER_SPAWN := Vector2(1160, 640) # Terminal rodoviário: início do jogo.
const PORT_ACCESS := Vector2(1260, 370)

const ZONES: Array[Dictionary] = [
	{"id": &"canal_porto", "kind": "water", "rect": Rect2(0, 0, 2400, 270), "buildable": false},
	{"id": &"port_area", "kind": "port", "rect": Rect2(1240, 15, 430, 245), "buildable": true, "entrance": PORT_ACCESS},
	{"id": &"cargo_ship", "kind": "scenic_ship", "rect": Rect2(1860, 55, 470, 80), "buildable": false},
	{"id": &"market", "kind": "market", "rect": Rect2(380, 185, 180, 160), "buildable": true, "entrance": Vector2(470, 380)},
	{"id": &"park", "kind": "park", "rect": Rect2(10, 400, 230, 430), "buildable": false, "entrance": Vector2(250, 600)},
	{"id": &"central_services", "kind": "center", "rect": Rect2(575, 470, 185, 220), "buildable": true, "entrance": Vector2(665, 720)},
	{"id": &"homes_north", "kind": "homes", "rect": Rect2(890, 465, 150, 225), "buildable": true, "entrance": Vector2(965, 720)},
	{"id": &"terminal", "kind": "bus_terminal", "rect": Rect2(1090, 500, 185, 190), "buildable": true, "entrance": PLAYER_SPAWN},
	{"id": &"terminal_parking", "kind": "parking", "rect": Rect2(1280, 500, 190, 190), "buildable": false, "entrance": Vector2(1280, 640)},
	{"id": &"cemetery_iml", "kind": "cemetery_iml", "rect": Rect2(1595, 445, 245, 560), "buildable": true, "entrance": Vector2(1555, 720)},
	{"id": &"garage_missions", "kind": "mission_garage", "rect": Rect2(20, 850, 220, 245), "buildable": true, "entrance": Vector2(265, 970)},
	{"id": &"police", "kind": "police", "rect": Rect2(20, 1120, 205, 150), "buildable": true, "entrance": Vector2(245, 1195)},
	{"id": &"fire_station", "kind": "fire_station", "rect": Rect2(20, 1370, 210, 210), "buildable": true, "entrance": Vector2(250, 1465)},
	{"id": &"homes_center", "kind": "homes", "rect": Rect2(575, 790, 865, 215), "buildable": true, "entrance": Vector2(1000, 760)},
	{"id": &"cobra_territory", "kind": "first_gang", "rect": Rect2(590, 1040, 670, 170), "buildable": true, "entrance": Vector2(930, 1010)},
	{"id": &"paint_spray", "kind": "car_repair_customization", "rect": Rect2(610, 1330, 220, 240), "buildable": true, "entrance": Vector2(850, 1440)},
	{"id": &"favela", "kind": "favela", "rect": Rect2(1370, 1300, 250, 190), "buildable": true, "entrance": Vector2(1340, 1400)},
	{"id": &"map2_highway_exit", "kind": "map_exit", "rect": Rect2(2080, 620, 320, 600), "buildable": false, "entrance": Vector2(2380, 900)},
]

static func get_road_spines() -> Array[Dictionary]:
	return [
		{"id": "canal_front", "width": 164.0, "points": PackedVector2Array([Vector2(240, 400), Vector2(560, 400), Vector2(920, 400), Vector2(1260, 370)])},
		{"id": "terminal_avenue", "width": 164.0, "points": PackedVector2Array([Vector2(250, 740), Vector2(650, 740), Vector2(1050, 740), Vector2(1555, 740)])},
		{"id": "west_services", "width": 112.0, "points": PackedVector2Array([Vector2(260, 740), Vector2(260, 1560)])},
		{"id": "central_grid", "width": 112.0, "points": PackedVector2Array([Vector2(520, 740), Vector2(520, 1260), Vector2(850, 1260), Vector2(850, 1580)])},
		{"id": "residential_grid", "width": 112.0, "points": PackedVector2Array([Vector2(1050, 740), Vector2(1050, 1010), Vector2(1320, 1010), Vector2(1320, 1540)])},
		{"id": "cemetery_access", "width": 112.0, "points": PackedVector2Array([Vector2(1555, 740), Vector2(1555, 1050), Vector2(1870, 1050)])},
		{"id": "map2_highway", "width": 180.0, "points": PackedVector2Array([Vector2(1840, 460), Vector2(1980, 720), Vector2(2160, 900), Vector2(2400, 900)])},
]

## Verde significa vegetação, pedras, árvores, pátio natural ou barreira visual;
## não é lote vazio para receber casas.
const GREEN_ZONES: Array[Rect2] = [
	Rect2(10, 300, 280, 100), Rect2(570, 300, 520, 95), Rect2(245, 500, 180, 250),
	Rect2(300, 830, 160, 610), Rect2(1840, 450, 220, 550), Rect2(1900, 900, 300, 660),
	Rect2(900, 1280, 350, 190),
]

## Só cenário: entra em túnel atrás de Bombeiros/Paint & Spray, emerge num
## viaduto curvo junto ao cemitério e cruza a saída do Mapa 2 por cima.
static func get_scenic_rail_segments() -> Array[Dictionary]:
	return [
		{"id": "tunnel_south", "mode": "underground", "points": PackedVector2Array([Vector2(0, 1590), Vector2(180, 1360), Vector2(620, 1300), Vector2(1100, 1240)])},
		{"id": "cemetery_viaduct", "mode": "elevated", "points": PackedVector2Array([Vector2(1100, 1240), Vector2(1320, 1110), Vector2(1330, 760), Vector2(1510, 360), Vector2(1740, 700)])},
		{"id": "east_overpass", "mode": "elevated", "points": PackedVector2Array([Vector2(1740, 700), Vector2(1930, 810), Vector2(2180, 810)])},
	]

## Contrato de becos: coordenadas finais só serão criadas entre os lotes e ruas
## correspondentes; eles são sempre pedestrian-only e ocultam linha de visão.
const PEDESTRIAN_ALLEY_IDS := [&"beco_mercado", &"beco_residencial", &"beco_cobra", &"beco_cemiterio", &"beco_favela"]

const REQUIRED_MARKERS := {
	&"PlayerSpawn": PLAYER_SPAWN, &"TerminalStop": PLAYER_SPAWN,
	&"PortApproach": PORT_ACCESS, &"MarketEntrance": Vector2(470, 380),
	&"ParkEntrance": Vector2(250, 600), &"GarageEntrance": Vector2(265, 970),
	&"PaintSprayEntrance": Vector2(850, 1440), &"CobraEntrance": Vector2(930, 1010),
	&"CemeteryIMLEntrance": Vector2(1555, 720), &"RailUnderpass": Vector2(1100, 1240),
	&"ExitDistrict2": Vector2(2380, 900),
}
