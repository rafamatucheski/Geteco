extends RefCounted
## Classes de cabine, arquétipo -> classe e ajustes por arquétipo do VehicleInterior, separados do
## código em 01/11 (Onda 2 do plano de divisão). O dono reexporta cada tabela com o mesmo nome
## (`VehicleInterior.KINDS`, `KIND_OF`, `OVERRIDES`), então quem lê pelo dono não muda. Mudar um
## valor muda a medida da cabine (`_derive`) e a pose do motorista de todos os veículos da classe.

# hip / hip_min: altura preferida e mínima da junta do quadril sobre o piso; rec: reclinação do
# tronco (rad); dy: quanto o centro do volante fica abaixo do ombro; r/tilt: raio e inclinação
# do aro (0 = vertical, 1,57 = deitado); foot: quanto o tornozelo fica à frente do quadril;
# clear: folga entre o centro do volante e a base do para-brisa; floor: piso da cabine sobre o
# chão quando o modelo não diz outra coisa; rows: banco traseiro; grip: posição da mão no aro
# (graus, 180 = nove horas).
# O Dante mede ~1,65 m e o teto do sedã fica a 1,32 m: o banco desce até `hip_min` e, se ainda
# não couber, o corpo diminui (até 82 %, ver `_fit`) em vez de a cabeça vazar pelo teto.
const KINDS := {
	"car": {"hip": .34, "hip_min": .22, "rec": .34, "dy": -.05, "r": .19, "tilt": .45, "foot": .60, "clear": .26, "floor": .12, "rows": true, "grip": 150.0},
	"sport": {"hip": .30, "hip_min": .20, "rec": .48, "dy": -.05, "r": .17, "tilt": .50, "foot": .64, "clear": .22, "floor": .08, "rows": false, "grip": 155.0},
	"suv": {"hip": .44, "hip_min": .28, "rec": .28, "dy": -.06, "r": .21, "tilt": .62, "foot": .56, "clear": .30, "floor": .28, "rows": true, "grip": 150.0},
	"pickup": {"hip": .44, "hip_min": .28, "rec": .28, "dy": -.06, "r": .21, "tilt": .62, "foot": .56, "clear": .30, "floor": .26, "rows": true, "grip": 150.0},
	"van": {"hip": .50, "hip_min": .34, "rec": .16, "dy": -.08, "r": .23, "tilt": .90, "foot": .52, "clear": .36, "floor": .32, "rows": false, "grip": 160.0},
	"truck": {"hip": .56, "hip_min": .40, "rec": .14, "dy": -.10, "r": .27, "tilt": .85, "foot": .50, "clear": .40, "floor": .85, "rows": false, "grip": 160.0},
	"bus": {"hip": .50, "hip_min": .36, "rec": .10, "dy": -.10, "r": .25, "tilt": 1.15, "foot": .50, "clear": .40, "floor": .50, "rows": false, "grip": 165.0},
	"buggy": {"hip": .30, "hip_min": .30, "rec": .30, "dy": -.10, "r": .17, "tilt": .70, "foot": .56, "clear": .20, "floor": .66, "rows": false, "grip": 150.0},
	"forklift": {"hip": .28, "hip_min": .28, "rec": .08, "dy": -.16, "r": .16, "tilt": .90, "foot": .56, "clear": .20, "floor": .64, "rows": false, "grip": 160.0},
}

const KIND_OF := {
	"digo_gol_1993": "car", "digo_amarok_2014": "pickup",
	"union_sedan": "car", "sedan_classic": "car", "taxi_yellow": "car", "police_cruiser": "car", "aurora_executive": "car",
	"metro_hatch": "car", "orbita_micro": "car", "nordic_estate": "car", "station_wagon": "car", "sport_estate": "car",
	"sport_coupe": "sport", "cobra_v8": "sport", "muscle_classic": "sport", "monaliza": "sport", "vertice_midengine": "sport",
	"porto_rosso": "sport", "beach_cabriolet": "sport",
	"arctic_jeep": "suv", "desert_jeep_4x4": "suv", "vale_crossover": "suv", "summit_suv": "suv", "winter_suv_heavy": "suv",
	"police_suv": "suv", "surf_woody_wagon": "suv",
	"lumber_pickup_4x4": "pickup", "ranch_pickup": "pickup", "ranch_single": "pickup", "atlas_crew_pickup": "pickup",
	"bravio_crew": "pickup", "sertao_trail_pickup": "pickup",
	"courier_van": "van", "polar_van": "van", "police_transport": "van", "dock_delivery_van": "van", "nimbus_minivan": "van",
	"medic_box": "van",
	"american_dump_truck": "truck", "american_tanker_truck": "truck", "cargo_flatbed_truck": "truck", "boxrunner": "truck",
	"towmaster": "truck", "rescue_pumper": "truck", "snow_plow_truck": "truck",
	"route_city": "bus", "beach_buggy": "buggy", "dune_buggy": "buggy", "port_forklift": "forklift",
}

## Ajustes por arquétipo sobre o que se mede no modelo: piso da cabine, cabine aberta (sem
## teto: o piloto é visto de cima inteiro), e lugares onde o vidro não dá pista (buggy,
## empilhadeira). Valores em coordenadas do veículo (−Z é a frente, o motorista fica em −X).
const OVERRIDES := {
	# Authored cabins: mirror glass belongs outside the passenger compartment.
	"digo_gol_1993": {"floor": .20, "belt": .94, "roof": 1.43, "hw": .75, "wz0": -.62, "wz1": -.136, "rear": 1.55, "rear_top": .89, "roof_rear": .86, "sx": -.34, "sz": .04, "roof_liner": false},
	"digo_amarok_2014": {"floor": .49, "belt": 1.23, "roof": 1.86, "hw": .89, "wz0": -1.025, "wz1": -.51, "rear": 1.025, "rear_top": .96, "sx": -.40, "sz": -.36, "roof_liner": false},
	# O teto curvo estreita e termina antes do vidro traseiro. Forro e barras na
	# largura/altura da cintura atravessariam a pintura, parecendo um rack externo.
	"sport_coupe": {
		"roof_liner": false, "roof_rear": .60, "roof_trim_x": .55, "roof_trim_y": 1.215,
		# O para-brisa inclinado exige painel recuado e capelo baixo/raso.
		"dash_front_inset": .02, "dash_min_depth": .10,
		"cluster_z": -.75, "cluster_rise": .02, "cluster_depth": .12,
	},
	"beach_cabriolet": {"open_top": true},
	"porto_rosso": {"open_top": true},
	"american_dump_truck": {"floor": .95, "roof": 2.55},
	"american_tanker_truck": {"floor": .95, "roof": 2.55},
	"cargo_flatbed_truck": {"floor": .95, "roof": 2.55},
	"boxrunner": {"floor": .85, "roof": 1.98},
	"towmaster": {"floor": .78},
	"rescue_pumper": {"floor": .80},
	"snow_plow_truck": {"floor": .82},
	"beach_buggy": {"open_top": true, "body_scale": .88, "floor": .70, "sx": -.28, "sz": .18, "cush": .78, "belt": 1.13, "roof": 1.6, "wz0": -.62, "wz1": -.43, "rear": .7, "hw": .55},
	"dune_buggy": {"open_top": true, "body_scale": .88, "floor": .70, "sx": -.29, "sz": .18, "cush": .78, "belt": 1.02, "roof": 1.4, "wz0": -.58, "wz1": -.43, "rear": .7, "hw": .55},
	"port_forklift": {"open_top": true, "sx": 0.0, "sz": .50, "cush": .90, "belt": 1.1, "roof": 2.08, "wz0": -.2, "wz1": -.1, "rear": 1.1, "hw": .46},
}
