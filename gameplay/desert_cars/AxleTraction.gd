extends RefCounted
## Tração por eixo do motor completo (27/10). Antes a força nas rodas era limitada por
## massa × g × traction para qualquer carro, então um RWD e um AWD com o mesmo `traction`
## andavam igual. Aqui só o eixo que traciona conta: a carga dele vem do peso estático
## (motor na frente, no meio ou atrás) mais a transferência pela aceleração (h/L), que
## alivia a frente e carrega a traseira. FWD perde aderência ao acelerar forte, RWD ganha,
## AWD com central ativo usa quase tudo e o 4x4 bloqueado em 50/50 fica preso ao eixo mais
## leve. Em terra, areia, grama e neve o 4x4 e o AWD perdem bem menos que um 2WD.
##
## `REALISM` mistura o eixo real com a aderência inteira antiga: em 1,0 um RWD esportivo
## largaria ~40% pior que hoje, demais para fichas autoradas como aderência total; em 0,6 a
## ordem AWD > 4x4 > RWD > FWD aparece (~0,98 / 0,92 / 0,76 / 0,70 da força antiga na largada).
##
## GETECO_AXLE_TRACTION: "0" desliga (igual a antes, para comparar), "1" (padrão) na rua,
## "2" também nas arrancadas (o balanço dos rivais foi calibrado sem isto).
const REALISM := .6
const G := 9.81
## Peso na frente quando o motor não está à frente do eixo dianteiro.
const FRONT_WEIGHT := {"tauro_v10":.42, "vertice_midengine":.42, "beach_buggy":.40, "dune_buggy":.40, "porto_rosso":.50}
const DEFAULT_FRONT := {"fwd":.62, "rwd":.52, "awd":.56, "4x4":.56}
## Quanto da perda de aderência em piso solto (dirt_grip × 0,70) a tração recupera.
const LOOSE := {"4x4":1.30, "awd":1.15}
static var mode := _read_mode()

static func _read_mode() -> int:
	var value := OS.get_environment("GETECO_AXLE_TRACTION").strip_edges()
	if value == "0": return 0
	if value == "2": return 2
	return 1

static func applies(race_mode: bool) -> bool:
	return mode == 2 or (mode == 1 and not race_mode)

static func layout(id: String, spec: Dictionary) -> Dictionary:
	var drive := str(spec.get("drivetrain","rwd")).to_lower()
	var size: Array = spec.get("bounds_size",[1.8,1.4,4.4])
	var front := float(spec.get("front_weight",FRONT_WEIGHT.get(id,DEFAULT_FRONT.get(drive,.52))))
	# Centro de gravidade: picape e utilitário ficam bem mais altos que um carro de passeio.
	var h := float(spec.get("cg_height",.72 if float(size[1]) > 1.6 else .50))
	var wheelbase := float(spec.get("wheelbase",clampf(float(size[2])*.59,2.2,3.6)))
	return {"drive":drive, "front":front, "h":h, "wheelbase":wheelbase}

## Fração da aderência inteira que o eixo (ou eixos) tracionado oferece com esta aceleração.
static func share(axle: Dictionary, accel_mps2: float) -> float:
	if axle.is_empty(): return 1.0
	var transfer := clampf(accel_mps2,-12.0,12.0)*float(axle.h)/(G*float(axle.wheelbase))
	var front := clampf(float(axle.front)-transfer,.05,.95)
	var rear := 1.0-front
	var real := .97
	match str(axle.drive):
		"fwd": real = front
		"rwd": real = rear
		"4x4": real = minf(1.0,2.0*minf(front,rear))*.98
	return lerpf(1.0,real,REALISM)

static func loose_surface(drive: String) -> float:
	return float(LOOSE.get(drive.to_lower(),1.0))
