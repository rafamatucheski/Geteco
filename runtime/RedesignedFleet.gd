extends RefCounted
## Baked presentation only. Physics/handling remain in the existing catalogs.
## Lazy loading keeps the full roster out of startup memory.
static var enabled := true
static var _scenes: Dictionary = {}
const MESH_COUNTS := {
	"besouro_1300":10,
	"mare_microvan":10,
	"toco_minitruck":10,
	"american_dump_truck":7,
	"american_tanker_truck":7,
	"arctic_jeep":10,
	"armored_truck":18,
	"atlas_crew_pickup":10,
	"aurora_executive":7,
	"beach_buggy":8,
	"beach_cabriolet":5,
	"bike_cruiser":8,
	"bike_sport":8,
	"bike_urban":8,
	"boxrunner":5,
	"bravio_crew":10,
	"cargo_flatbed_truck":7,
	"cobra_boss_ironback":5,
	"cobra_v8":5,
	"courier_van":10,
	"desert_bison":5,
	"desert_coyote":5,
	"desert_coyote_drag":5,
	"desert_faisca":5,
	"desert_faisca_rally":5,
	"desert_jeep_4x4":10,
	"desert_mirage":5,
	"desert_mirage_gt":5,
	"desert_siroco":5,
	"digo_amarok_2014":5,
	"digo_gol_1993":5,
	"dock_delivery_van":10,
	"dune_buggy":8,
	"jessica_jetta_gli":5,
	"lumber_pickup_4x4":10,
	"medic_box":5,
	"metro_hatch":7,
	"monaliza":7,
	"muscle_classic":5,
	"nimbus_minivan":10,
	"nordic_estate":7,
	"orbita_micro":7,
	"polar_van":10,
	"police_cruiser":7,
	"police_suv":5,
	"police_transport":5,
	"porto_rosso":5,
	"ranch_pickup":7,
	"ranch_single":7,
	"rauhz_focus_mk1":5,
	"rescue_pumper":5,
	"sedan_classic":7,
	"sertao_trail_pickup":10,
	"snow_plow_truck":9,
	"sport_estate":7,
	"station_wagon":7,
	"summit_suv":10,
	"supra_a80":5,
	"surf_woody_wagon":7,
	"taxi_yellow":11,
	"towmaster":5,
	"union_sedan":7,
	"vale_crossover":7,
	"vertice_midengine":5,
	"winter_suv_heavy":10,
}

static func contains(id: String) -> bool:
	return enabled and MESH_COUNTS.has(id)

static func scene_path(id: String) -> String:
	return "res://assets/fleet/redesigned/"+id+".scn"

static func create(id: String) -> Node3D:
	if not contains(id): return null
	if not _scenes.has(id): _scenes[id]=load(scene_path(id)) as PackedScene
	var packed: PackedScene=_scenes[id]
	return packed.instantiate() as Node3D if packed!=null else null
