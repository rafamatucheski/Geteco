extends RefCounted
## Perfil mecânico dos carros do jogo base que usam o motor completo (marchas, turbo,
## resistência do ar). A ficha antiga continua valendo: massa, curva, dano e visual
## vêm de FleetCatalog; aqui entra só o que o motor precisa. O torque de cada carro é
## calibrado por tests/measure/calibrate_street_powertrain.gd para largar e acelerar
## como o carro já fazia (aceleração linear de Vehicle.gd), e o teto de rua é a
## velocidade final antiga. Assim a migração não muda o ritmo fora das provas.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PROFILES := {
	"porto_rosso": {"torque_nm":612.0, "redline":8200.0, "gears":[3.20,2.15,1.60,1.25,1.00,.82], "final_drive":3.40, "wheel_radius":.34, "traction":1.16, "drag_area":.62, "engine_family":"v12"},
	"metro_hatch": {"torque_nm":260.0, "redline":6800.0, "gears":[3.45,2.10,1.45,1.10,.88], "final_drive":4.10, "wheel_radius":.29, "traction":.85, "drag_area":.66, "engine_family":"street"},
	"ranch_pickup": {"torque_nm":398.0, "redline":5200.0, "gears":[3.60,2.10,1.40,1.00,.78], "final_drive":3.70, "wheel_radius":.37, "traction":.78, "drag_area":.95, "engine_family":"diesel"},
	"muscle_classic": {"torque_nm":534.0, "redline":6000.0, "gears":[2.90,1.90,1.40,1.00,.78], "final_drive":3.30, "wheel_radius":.34, "traction":.72, "drag_area":.75, "engine_family":"muscle"}
}

static func ids() -> Array:
	return PROFILES.keys()

static func has(id: String) -> bool:
	return PROFILES.has(id)

## Ficha antiga + mecânica. `street_cap_mps` repete a velocidade final antiga
## (max_speed/16 limitada como em Vehicle.gd).
static func spec(id: String) -> Dictionary:
	if not PROFILES.has(id): return {}
	var s: Dictionary = FLEET.all().get(id,{}).duplicate(true)
	if s.is_empty(): return {}
	s.merge(PROFILES[id].duplicate(true),true)
	s.merge({"full_powertrain":true, "street_cap_mps":clampf(float(s.max_speed)/16.0,5.0,45.0)},true)
	return s
