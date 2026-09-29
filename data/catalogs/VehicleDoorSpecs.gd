extends RefCounted
## Onde fica a porta do motorista em cada modelo da frota, medida sobre a grade métrica de
## `tests/capture/capture_vehicle_doors.gd -- grid` (2026-09-28). Os modelos são malhas
## assadas sem dobradiça, então o recorte da folha (VehicleDoorBuilder) precisa saber, por
## modelo, o vão da porta: z de frente (dobradiça) e de trás, e as alturas do rodapé, da
## linha da cintura (base do vidro) e do teto. Coordenadas no espaço do MODELO (antes da
## escala de variante do Vehicle); o eixo −Z é a frente.
##
## `x` é o x da lataria (meia largura do painel da porta), medido na malha pelo próprio
## VehicleDoorBuilder; o teste de portas confere que a tabela não envelheceu (±3 cm). Sem
## `x` o builder mede na hora, ao custo de uma varredura extra dos triângulos.
##
## `seat_z` é o centro do banco do motorista no mesmo espaço. Antes todo carro usava um
## banco derivado do comprimento do casco, e em vans e caminhões o motorista entrava no
## meio da carroceria em vez da cabine.

const DOORS := {
	# Sedãs da família "clássica": porta dianteira entre o capô e o pilar B.
	"sedan_classic": {"zf": -.70, "zr": .12, "sill": .42, "belt": .78, "top": 1.36, "x": 0.89},
	"union_sedan": {"alias": "sedan_classic"},
	"taxi_yellow": {"alias": "sedan_classic", "x": 0.91},
	"police_cruiser": {"alias": "sedan_classic"},
	"metro_hatch": {"zf": -.55, "zr": .24, "sill": .42, "belt": .76, "top": 1.36, "x": 0.84},
	"aurora_executive": {"zf": -.90, "zr": .25, "sill": .42, "belt": .82, "top": 1.38, "x": 0.98},
	"orbita_micro": {"zf": -.65, "zr": .24, "sill": .40, "belt": .78, "top": 1.38, "x": 0.83},
	"vale_crossover": {"class": "tall", "zf": -.80, "zr": -.05, "sill": .42, "belt": .90, "top": 1.56, "x": 0.99},
	"nimbus_minivan": {"class": "tall", "zf": -1.55, "zr": -.61, "sill": .42, "belt": .98, "top": 1.85, "x": 0.98},
	"sport_estate": {"zf": -.85, "zr": .21, "sill": .40, "belt": .86, "top": 1.42, "x": 0.94},
	"station_wagon": {"zf": -.95, "zr": .23, "sill": .42, "belt": .89, "top": 1.56, "x": 0.87},
	"nordic_estate": {"alias": "station_wagon"},
	"surf_woody_wagon": {"class": "tall", "zf": -.78, "zr": .30, "sill": .38, "belt": .86, "top": 1.50, "x": 0.96},
	# Cupês de duas portas: a porta vai até o começo da coluna traseira.
	"vertice_midengine": {"zf": -.70, "zr": .75, "sill": .35, "belt": .78, "top": 1.20, "x": 1.09},
	"cobra_v8": {"zf": -.55, "zr": .85, "sill": .33, "belt": .86, "top": 1.28, "x": 0.95},
	"muscle_classic": {"alias": "cobra_v8"},
	"cobra_boss_ironback": {"alias": "cobra_v8"},
	"monaliza": {"zf": -.62, "zr": .85, "sill": .34, "belt": .80, "top": 1.25, "x": 0.98},
	"sport_coupe": {"zf": -.725, "zr": .81, "sill": .24, "belt": .92, "top": 1.30, "x": .90},
	# Conversíveis: sem teto, a "porta" é o painel do cockpit.
	"beach_cabriolet": {"zf": -.69, "zr": .82, "sill": .30, "belt": .68, "top": .78, "x": 0.84},
	"porto_rosso": {"zf": -.70, "zr": .80, "sill": .30, "belt": .62, "top": .74, "x": 0.98},
	# Picapes e utilitários.
	"ranch_single": {"class": "tall", "zf": -.98, "zr": .10, "sill": .54, "belt": 1.00, "top": 1.46, "x": 0.97},
	"ranch_pickup": {"alias": "ranch_single"},
	"lumber_pickup_4x4": {"alias": "ranch_single"},
	"atlas_crew_pickup": {"class": "tall", "zf": -1.15, "zr": -.30, "sill": .40, "belt": 1.00, "top": 1.75, "x": 1.09},
	"bravio_crew": {"class": "tall", "zf": -1.20, "zr": -.20, "sill": .42, "belt": 1.05, "top": 1.75, "x": 1.07},
	"sertao_trail_pickup": {"class": "tall", "zf": -1.00, "zr": -.27, "sill": .45, "belt": .95, "top": 1.70, "x": 1.01},
	"police_suv": {"class": "tall", "zf": -.95, "zr": .08, "sill": .46, "belt": 1.12, "top": 1.72, "x": 1.05},
	"summit_suv": {"class": "tall", "zf": -.74, "zr": .25, "sill": .50, "belt": 1.05, "top": 1.62, "x": 1.02},
	"winter_suv_heavy": {"alias": "summit_suv"},
	"arctic_jeep": {"class": "tall", "zf": -.50, "zr": 1.05, "sill": .50, "belt": 1.15, "top": 1.78, "x": 0.94},
	"desert_jeep_4x4": {"alias": "arctic_jeep"},
	# Vans, ambulância e caminhões: a porta é a da cabine, bem à frente do chassi.
	"courier_van": {"class": "tall", "zf": -1.35, "zr": -.47, "sill": .46, "belt": .95, "top": 1.92, "x": 0.97},
	"polar_van": {"alias": "courier_van"},
	"police_transport": {"alias": "courier_van"},
	"dock_delivery_van": {"class": "tall", "zf": -2.05, "zr": -1.00, "sill": .50, "belt": .95, "top": 1.90, "x": 0.99},
	"medic_box": {"class": "tall", "zf": -1.55, "zr": -.70, "sill": .62, "belt": 1.07, "top": 1.85, "x": 0.97},
	"snow_plow_truck": {"class": "truck", "zf": -2.35, "zr": -1.00, "sill": .50, "belt": 1.15, "top": 2.15, "x": 1.12},
	"cargo_flatbed_truck": {"class": "truck", "zf": -1.95, "zr": -.72, "sill": .75, "belt": 1.72, "top": 2.62, "x": 1.04},
	"american_dump_truck": {"alias": "cargo_flatbed_truck"},
	"american_tanker_truck": {"alias": "cargo_flatbed_truck"},
	"boxrunner": {"class": "truck", "zf": -3.05, "zr": -1.85, "sill": .64, "belt": 1.19, "top": 2.00, "x": 1.08},
	"towmaster": {"class": "truck", "zf": -3.05, "zr": -1.70, "sill": .64, "belt": 1.19, "top": 2.00, "x": 1.10},
	"rescue_pumper": {"class": "truck", "zf": -3.95, "zr": -2.85, "sill": .64, "belt": 1.33, "top": 2.10, "x": 1.20},
}

## Abertura da folha (rad). Carros baixos param antes: a folha comprida bateria no
## meio-fio e o corpo teria de contorná-la; cabines altas abrem mais para o degrau.
const OPEN_ANGLE := {"car": 1.05, "tall": 1.10, "truck": 1.20}

static func row(archetype: String) -> Dictionary:
	var entry: Dictionary = DOORS.get(archetype, {})
	if entry.has("alias"):
		var merged: Dictionary = DOORS.get(str(entry.alias), {}).duplicate()
		for key in entry:
			if key != "alias": merged[key] = entry[key]
		return merged
	return entry

static func has_row(archetype: String) -> bool:
	return not row(archetype).is_empty()

## Vão padrão para um arquétipo sem linha na tabela (modelo novo): a porta fica logo à
## frente do meio do casco, como o gerador antigo fazia. O teste de frota reprova o
## veículo novo que cair aqui, para ninguém esquecer de medir.
static func fallback(half_length: float, body_height: float) -> Dictionary:
	var length := clampf(half_length * .48, .72, 1.28)
	var front := -clampf(half_length * .42, .62, 1.05)
	return {"zf": front, "zr": front + length, "sill": .40, "belt": minf(.80, body_height * .55), "top": maxf(body_height - .05, 1.0)}

## Geometria de embarque de um lado, em coordenadas do MODELO (o Vehicle converte). `skin` é o x da lataria (medido na malha ou da tabela); tudo o mais deriva
## do vão e do ângulo, para o corpo nunca ficar dentro do arco de abertura da folha.
static func layout(spec: Dictionary, side: int, skin: float, angle: float, hull_half_width := 0.0) -> Dictionary:
	var s := float(side)
	var front: float = spec.zf
	var rear: float = spec.zr
	var length := rear - front
	var hinge_x := skin - .03
	var swing_x := sin(angle) * length
	var swing_z := cos(angle) * length
	var hinge := Vector3(s * hinge_x, 0.0, front)
	var tip := hinge + Vector3(s * swing_x, 0.0, swing_z)
	# Fora do arco da folha: a ponta traseira dela varre um círculo de raio `length`
	# em volta da dobradiça. Quem fica depois do vão traseiro nunca é atingido, nem ao
	# fechar a porta com a pessoa parada ali.
	# Fora também do casco de colisão (a lâmina do limpa-neve e as caixas largas passam da
	# lataria): o Driving recusa um ponto de saída dentro dele.
	var lateral := maxf(skin + .42, hull_half_width + .36)
	var reach := length + .34
	var stand_z := front + sqrt(maxf(reach * reach - pow(lateral - hinge_x, 2.0), 0.0))
	var stand := Vector3(s * lateral, 0.0, stand_z)
	# Onde o corpo cruza o plano da lataria: dentro do vão, longe dos dois montantes.
	var gate_z := rear - clampf(length * .34, .24, .42)
	var gate := Vector3(s * (skin - .10), 0.0, gate_z)
	var reach_point := Vector3(s * (skin + .36), 0.0, gate_z + .14)
	# Mão no montante traseiro da abertura (batente), na altura do ombro-cotovelo.
	var grip := Vector3(s * (skin - .03), minf(float(spec.belt) + .34, float(spec.top) - .12), rear - .04)
	return {"hinge": hinge, "tip": tip, "stand": stand, "gate": gate, "reach": reach_point, "grip": grip,
		"length": length, "angle": angle, "skin": skin}
