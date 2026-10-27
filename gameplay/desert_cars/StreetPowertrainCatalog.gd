extends RefCounted
## Perfil mecânico dos carros do jogo base que usam o motor completo (marchas, turbo,
## resistência do ar). A ficha antiga continua valendo: massa, curva, dano e visual
## vêm de FleetCatalog; aqui entra só o que o motor precisa. O torque de cada carro é
## calibrado por tests/measure/calibrate_street_powertrain.gd para largar e acelerar
## como o carro já fazia (aceleração linear de Vehicle.gd), e o teto de rua é a
## velocidade final antiga. Assim a migração não muda o ritmo fora das provas.
const FLEET := preload("res://runtime/FleetCatalog.gd")
## Modelos por tipo de carro; cada carro escolhe um e ajusta o que for diferente.
## A tração padrão é derivada da aceleração antiga (precisa segurar `a` sem patinar).
const KINDS := {
	"compact": {"redline":6800.0, "gears":[3.45,2.10,1.45,1.10,.88], "final_drive":4.10, "wheel_radius":.29, "traction":.85, "drag_area":.66, "engine_family":"street"},
	"sedan": {"redline":6300.0, "gears":[3.40,2.05,1.40,1.05,.85], "final_drive":3.90, "wheel_radius":.31, "traction":.82, "drag_area":.70, "engine_family":"street"},
	"wagon": {"redline":6000.0, "gears":[3.40,2.05,1.40,1.05,.84], "final_drive":3.90, "wheel_radius":.32, "traction":.80, "drag_area":.85, "engine_family":"street"},
	"utility": {"redline":5400.0, "gears":[3.60,2.10,1.40,1.00,.78], "final_drive":3.80, "wheel_radius":.37, "traction":.85, "drag_area":.95, "engine_family":"diesel"},
	"sport": {"redline":7600.0, "gears":[3.20,2.15,1.60,1.25,1.00,.82], "final_drive":3.45, "wheel_radius":.33, "traction":1.0, "drag_area":.62, "engine_family":"sport"},
	"muscle": {"redline":6000.0, "gears":[2.90,1.90,1.40,1.00,.78], "final_drive":3.30, "wheel_radius":.34, "traction":.72, "drag_area":.75, "engine_family":"muscle"},
	"buggy": {"redline":7000.0, "gears":[3.20,1.90,1.30,1.00,.80], "final_drive":4.20, "wheel_radius":.33, "traction":.80, "drag_area":.75, "engine_family":"sport"}
}
## `torque_nm` vem de calibrate_street_powertrain.gd. Os quatro primeiros têm ficha completa.
## `axle_grip` vem de calibrate_street_powertrain.gd -- --axle: reforço do pneu que só vale com a
## tração por eixo ligada (AxleTraction), para a largada não piorar além da faixa da tração.
const PROFILES := {
	"porto_rosso": {"torque_nm":612.0, "redline":8200.0, "gears":[3.20,2.15,1.60,1.25,1.00,.82], "final_drive":3.40, "wheel_radius":.34, "traction":1.16, "drag_area":.62, "engine_family":"v12", "axle_grip":1.10},
	"metro_hatch": {"torque_nm":260.0, "redline":6800.0, "gears":[3.45,2.10,1.45,1.10,.88], "final_drive":4.10, "wheel_radius":.29, "traction":.85, "drag_area":.66, "engine_family":"street", "axle_grip":1.12},
	"ranch_pickup": {"torque_nm":398.0, "redline":5200.0, "gears":[3.60,2.10,1.40,1.00,.78], "final_drive":3.70, "wheel_radius":.37, "traction":.78, "drag_area":.95, "engine_family":"diesel"},
	"muscle_classic": {"torque_nm":534.0, "redline":6000.0, "gears":[2.90,1.90,1.40,1.00,.78], "final_drive":3.30, "wheel_radius":.34, "traction":.72, "drag_area":.75, "engine_family":"muscle", "axle_grip":1.18},
	"orbita_micro": {"kind":"compact","torque_nm":174.0,"drag_area":.62, "axle_grip":1.06},
	"sedan_classic": {"kind":"sedan","torque_nm":255.0, "axle_grip":1.02},
	"union_sedan": {"kind":"sedan","torque_nm":273.0, "axle_grip":1.06},
	"taxi_yellow": {"kind":"sedan","torque_nm":265.0, "axle_grip":1.06},
	"aurora_executive": {"kind":"sedan","torque_nm":481.0,"redline":6000.0,"drag_area":.72, "axle_grip":1.06},
	"nimbus_minivan": {"kind":"wagon","torque_nm":332.0},
	"station_wagon": {"kind":"wagon","torque_nm":246.0},
	"nordic_estate": {"kind":"wagon","torque_nm":262.0,"drag_area":.78},
	"surf_woody_wagon": {"kind":"wagon","torque_nm":253.0},
	"sport_estate": {"kind":"sport","torque_nm":691.0,"drag_area":.72},
	"vale_crossover": {"kind":"utility","torque_nm":416.0,"engine_family":"street","drag_area":.80},
	"sertao_trail_pickup": {"kind":"utility","torque_nm":533.0},
	"desert_jeep_4x4": {"kind":"utility","torque_nm":372.0},
	"arctic_jeep": {"kind":"utility","torque_nm":260.0},
	"summit_suv": {"kind":"utility","torque_nm":260.0},
	"atlas_crew_pickup": {"kind":"utility","torque_nm":471.0},
	"bravio_crew": {"kind":"utility","torque_nm":493.0},
	"ranch_single": {"kind":"utility","torque_nm":418.0, "axle_grip":1.01},
	"lumber_pickup_4x4": {"kind":"utility","torque_nm":382.0},
	"winter_suv_heavy": {"kind":"utility","torque_nm":431.0},
	"beach_buggy": {"kind":"buggy","torque_nm":201.0},
	"dune_buggy": {"kind":"buggy","torque_nm":225.0, "axle_grip":1.01},
	"beach_cabriolet": {"kind":"sport","torque_nm":284.0,"redline":7000.0,"drag_area":.70},
	"cobra_v8": {"kind":"muscle","torque_nm":517.0, "axle_grip":1.16},
	"monaliza": {"kind":"sport","torque_nm":387.0,"drag_area":.66},
	"sport_coupe": {"kind":"sport","torque_nm":279.0, "axle_grip":1.01},
	"vertice_midengine": {"kind":"sport","torque_nm":340.0,"redline":8000.0,"drag_area":.60},
	# Esportivos 2.0 (runtime/SportFleet.gd). A aderência na largada acompanha a tração:
	# AWD segura mais que RWD, que segura mais que FWD; os 4x4 pesados ficam no meio.
	"tauro_v10": {"torque_nm":586.0, "redline":8700.0, "gears":[3.13,2.33,1.79,1.42,1.15,.94,.78], "final_drive":3.65, "wheel_radius":.35, "traction":1.25, "drag_area":.66, "engine_family":"rosso_v12"},
	"raijin_gt": {"torque_nm":721.0, "redline":7100.0, "gears":[4.06,2.30,1.59,1.25,1.00,.80], "final_drive":3.70, "wheel_radius":.345, "traction":1.22, "drag_area":.68, "engine_family":"vq35", "factory_turbo":true},
	"kite_type_s": {"torque_nm":311.0, "redline":8400.0, "gears":[3.23,2.11,1.46,1.10,.85], "final_drive":4.40, "wheel_radius":.30, "traction":.95, "drag_area":.62, "engine_family":"sport", "axle_grip":1.11},
	"lince_rs": {"torque_nm":454.0, "redline":6800.0, "gears":[3.54,2.06,1.38,1.03,.85,.69], "final_drive":4.10, "wheel_radius":.33, "traction":.98, "drag_area":.66, "engine_family":"sport", "factory_turbo":true, "axle_grip":1.12},
	"brisa_s": {"torque_nm":300.0, "redline":7500.0, "gears":[3.76,2.27,1.65,1.26,1.00,.84], "final_drive":4.10, "wheel_radius":.31, "traction":1.0, "drag_area":.64, "engine_family":"sport", "axle_grip":1.02},
	"sakura_s15": {"torque_nm":362.0, "redline":7200.0, "gears":[3.32,1.90,1.31,1.00,.76], "final_drive":4.08, "wheel_radius":.32, "traction":.98, "drag_area":.62, "engine_family":"sport", "factory_turbo":true, "axle_grip":1.07},
	"rapina_r": {"torque_nm":805.0, "redline":6000.0, "gears":[4.17,2.34,1.52,1.14,.87,.69], "final_drive":3.73, "wheel_radius":.43, "traction":1.05, "drag_area":1.05, "engine_family":"m8_v8", "factory_turbo":true},
	"bastiao_63": {"torque_nm":763.0, "redline":6500.0, "gears":[4.38,2.86,1.92,1.37,1.00,.82,.73], "final_drive":3.27, "wheel_radius":.40, "traction":1.08, "drag_area":1.05, "engine_family":"m8_v8", "factory_turbo":true},
	# Muscle cars e lowriders (runtime/MuscleFleet.gd), todos RWD. Os lowriders têm câmbio de três
	# marchas, roda pequena e aderência de pneu fino de faixa branca.
	"potro_68": {"kind":"muscle", "torque_nm":720.0, "redline":6200.0, "traction":.95, "drag_area":.74},
	"jararaca_v10": {"kind":"muscle", "torque_nm":790.0, "redline":6200.0, "gears":[2.66,1.78,1.30,1.00,.74,.50], "final_drive":3.07, "wheel_radius":.345, "traction":1.0, "drag_area":.66},
	"carcara_ss": {"kind":"muscle", "torque_nm":750.0, "traction":.95, "drag_area":.74},
	"trovao_440": {"kind":"muscle", "torque_nm":850.0, "traction":.95, "drag_area":.80},
	"caiman_454": {"kind":"muscle", "torque_nm":820.0, "traction":.95, "drag_area":.78},
	"brasa_hc": {"kind":"muscle", "torque_nm":1000.0, "redline":6200.0, "gears":[4.71,3.14,2.10,1.67,1.29,1.00,.84,.67], "final_drive":2.62, "wheel_radius":.36, "traction":1.0, "drag_area":.72, "factory_turbo":true},
	"imperador_64": {"kind":"muscle", "torque_nm":700.0, "redline":5200.0, "gears":[2.52,1.52,1.00], "final_drive":3.08, "wheel_radius":.295, "traction":.80, "drag_area":.84},
	"imperador_64_conv": {"kind":"muscle", "torque_nm":710.0, "redline":5200.0, "gears":[2.52,1.52,1.00], "final_drive":3.08, "wheel_radius":.295, "traction":.80, "drag_area":.86},
	"monte_rei_84": {"kind":"muscle", "torque_nm":650.0, "redline":5200.0, "gears":[2.74,1.57,1.00], "final_drive":3.08, "wheel_radius":.30, "traction":.80, "drag_area":.82},
	"duque_76": {"kind":"muscle", "torque_nm":790.0, "redline":4800.0, "gears":[2.48,1.48,1.00], "final_drive":2.73, "wheel_radius":.31, "traction":.80, "drag_area":.90}
}

static func ids() -> Array:
	return PROFILES.keys()

## `-- --no-street-powertrain` desliga a migração para comparar antes/depois sem
## trocar arquivos de lugar (medições A/B).
static var _disabled := OS.get_cmdline_user_args().has("--no-street-powertrain")

static func has(id: String) -> bool:
	return not _disabled and PROFILES.has(id)

## Ficha antiga + mecânica. `street_cap_mps` repete a velocidade final antiga
## (max_speed/16 limitada como em Vehicle.gd).
static func spec(id: String) -> Dictionary:
	if not PROFILES.has(id): return {}
	var s: Dictionary = FLEET.all().get(id,{}).duplicate(true)
	if s.is_empty(): return {}
	var profile: Dictionary = PROFILES[id].duplicate(true)
	if profile.has("kind"):
		var base: Dictionary = KINDS[profile.kind].duplicate(true)
		# Sem tração própria, usa a mínima para o carro segurar a aceleração antiga.
		var a := clampf(float(s.acceleration)/160.0,2.0,10.0)
		if not profile.has("traction"): base["traction"] = maxf(float(base.traction),a/9.81*1.15)
		base.merge(profile,true)
		base.erase("kind")
		profile = base
	s.merge(profile,true)
	s.merge({"full_powertrain":true, "street_cap_mps":clampf(float(s.max_speed)/16.0,5.0,45.0)},true)
	return s
