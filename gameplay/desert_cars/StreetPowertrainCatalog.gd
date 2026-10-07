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
const PROFILES := {
	"porto_rosso": {"torque_nm":612.0, "redline":8200.0, "gears":[3.20,2.15,1.60,1.25,1.00,.82], "final_drive":3.40, "wheel_radius":.34, "traction":1.16, "drag_area":.62, "engine_family":"v12"},
	"metro_hatch": {"torque_nm":260.0, "redline":6800.0, "gears":[3.45,2.10,1.45,1.10,.88], "final_drive":4.10, "wheel_radius":.29, "traction":.85, "drag_area":.66, "engine_family":"street"},
	"ranch_pickup": {"torque_nm":398.0, "redline":5200.0, "gears":[3.60,2.10,1.40,1.00,.78], "final_drive":3.70, "wheel_radius":.37, "traction":.78, "drag_area":.95, "engine_family":"diesel"},
	"muscle_classic": {"torque_nm":534.0, "redline":6000.0, "gears":[2.90,1.90,1.40,1.00,.78], "final_drive":3.30, "wheel_radius":.34, "traction":.72, "drag_area":.75, "engine_family":"muscle"},
	"orbita_micro": {"kind":"compact","torque_nm":174.0,"drag_area":.62},
	"sedan_classic": {"kind":"sedan","torque_nm":255.0},
	"union_sedan": {"kind":"sedan","torque_nm":273.0},
	"taxi_yellow": {"kind":"sedan","torque_nm":265.0},
	"aurora_executive": {"kind":"sedan","torque_nm":481.0,"redline":6000.0,"drag_area":.72},
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
	"ranch_single": {"kind":"utility","torque_nm":418.0},
	"lumber_pickup_4x4": {"kind":"utility","torque_nm":382.0},
	"winter_suv_heavy": {"kind":"utility","torque_nm":431.0},
	"beach_buggy": {"kind":"buggy","torque_nm":201.0},
	"dune_buggy": {"kind":"buggy","torque_nm":225.0},
	"beach_cabriolet": {"kind":"sport","torque_nm":284.0,"redline":7000.0,"drag_area":.70},
	"cobra_v8": {"kind":"muscle","torque_nm":517.0},
	"monaliza": {"kind":"sport","torque_nm":387.0,"drag_area":.66},
	"sport_coupe": {"kind":"sport","torque_nm":279.0},
	"vertice_midengine": {"kind":"sport","torque_nm":340.0,"redline":8000.0,"drag_area":.60}
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
