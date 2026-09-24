extends RefCounted
## Caráter do farol de cada modelo da frota. Vista de cima, o que distingue um
## carro de outro à noite é a mancha de luz no asfalto: cor (temperatura),
## alcance, abertura e intensidade. As famílias seguem a idade e a categoria do
## modelo no catálogo — um sedã clássico não pode acender igual a um executivo.
##
## `energy`/`range`/`angle` valem para cada um dos dois projetores do carro do
## jogador; o NPC usa um único facho central (ver VehicleEquipment) derivado
## destes mesmos números.
const FAMILIES := {
	# Lâmpada incandescente/halógena velha: amarelada, curta e estreita.
	"classic": {"label":"Halógeno antigo", "color":Color(1.0, .80, .52), "energy":.95, "range":17.0, "angle":27.0},
	# Halógeno comum de carro popular e utilitário.
	"halogen": {"label":"Halógeno", "color":Color(1.0, .92, .78), "energy":1.3, "range":22.0, "angle":32.0},
	# Xenônio de executivo, esportivo e viatura: branco-azulado, forte e longo.
	"xenon": {"label":"Xenônio", "color":Color(.80, .89, 1.0), "energy":1.9, "range":29.0, "angle":30.0},
	# LED: branco neutro e bem aberto, corte nítido.
	"led": {"label":"LED", "color":Color(.96, .98, 1.0), "energy":1.7, "range":25.0, "angle":40.0},
	# Caminhão e ônibus: faróis altos do chassi, largos e fortes.
	"heavy": {"label":"Pesado", "color":Color(1.0, .90, .72), "energy":1.9, "range":27.0, "angle":42.0},
	# 4x4 de trilha: abertura larga para iluminar acostamento e mato.
	"offroad": {"label":"Off-road", "color":Color(1.0, .95, .84), "energy":1.7, "range":30.0, "angle":46.0},
}
const ARCHETYPES := {
	"classic": ["sedan_classic", "station_wagon", "surf_woody_wagon", "muscle_classic", "cobra_v8", "nordic_estate", "taxi_yellow", "orbita_micro", "ranch_single", "ranch_pickup", "lumber_pickup_4x4", "beach_buggy", "dune_buggy", "beach_cabriolet", "bike_cruiser", "port_forklift"],
	"halogen": ["union_sedan", "metro_hatch", "nimbus_minivan", "courier_van", "dock_delivery_van", "polar_van", "bravio_crew", "atlas_crew_pickup", "sertao_trail_pickup", "vale_crossover", "bike_urban"],
	"xenon": ["aurora_executive", "sport_estate", "sport_coupe", "monaliza", "porto_rosso", "police_cruiser", "police_suv", "summit_suv", "winter_suv_heavy"],
	"led": ["vertice_midengine", "bike_sport", "medic_box"],
	"heavy": ["route_city", "boxrunner", "cargo_flatbed_truck", "american_dump_truck", "american_tanker_truck", "towmaster", "snow_plow_truck", "rescue_pumper"],
	"offroad": ["arctic_jeep", "desert_jeep_4x4"],
}

static func family(archetype: String) -> String:
	for key in ARCHETYPES:
		if archetype in ARCHETYPES[key]: return key
	return "halogen"

static func for_archetype(archetype: String) -> Dictionary:
	var profile: Dictionary = FAMILIES[family(archetype)].duplicate()
	profile["family"] = family(archetype)
	# Moto tem um farol só, no centro do guidão.
	profile["single"] = archetype.begins_with("bike_")
	return profile
