class_name AlleyStealthContract
extends RefCounted

## Contrato de gameplay para becos do Bairro 1 V2. Coordenadas só entram
## depois que a nova planta do Rafael for transcrita; estes IDs e regras já
## são estáveis para layout, arte e IA.

const PEDESTRIAN_ALLEYS: Array[Dictionary] = [
	{
		"id": &"beco_mercado",
		"connects": [&"market_north", &"central_services"],
		"exits": 2,
		"vehicle_access": false,
		"purpose": "primeiro atalho seguro entre mercado e centro",
	},
	{
		"id": &"beco_residencial",
		"connects": [&"homes_center", &"terminal_start", &"terminal_parking"],
		"exits": 3,
		"vehicle_access": false,
		"purpose": "quebra a visão de perseguidores e recompensa explorar",
	},
	{
		"id": &"beco_cobra",
		"connects": [&"cobra_territory", &"homes_center", &"paint_spray"],
		"exits": 2,
		"vehicle_access": false,
		"purpose": "rota curta da gangue; rápida, mas arriscada e vigiada",
	},
	{
		"id": &"beco_cemiterio",
		"connects": [&"cemetery_iml", &"east_map_exit"],
		"exits": 2,
		"vehicle_access": false,
		"purpose": "passagem silenciosa por muros, árvores e manutenção",
	},
	{
		"id": &"beco_favela",
		"connects": [&"favela_south", &"paint_spray", &"cobra_territory"],
		"exits": 3,
		"vehicle_access": false,
		"purpose": "labirinto de rotas a pé, esconderijos e encontros",
	},
]

## Condições mínimas para sair de perseguição direta. A polícia ou gangue
## muda para busca, não desaparece: ainda pode investigar saídas previsíveis.
const LOS_BREAK_SECONDS := 3.0
const LOS_BREAK_DISTANCE := 180.0
const SEARCH_DURATION_SECONDS := 12.0
const ALLEY_MIN_WIDTH := 52.0
const ALLEY_MAX_WIDTH := 76.0

static func get_alley(alley_id: StringName) -> Dictionary:
	for alley in PEDESTRIAN_ALLEYS:
		if alley["id"] == alley_id:
			return alley.duplicate(true)
	return {}
