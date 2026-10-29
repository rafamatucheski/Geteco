extends RefCounted
## Escritório/guarita da Serra Bruta: identidade do lugar, porta pintada e sala.
##
## A fachada é o estilo pintado `escritorio-mina` (10 x 4 m), girado para a frente olhar a
## estrada (-X do mundo) em `LAYOUT.CENTER + AT`. A porta de empurrar é a folha pintada do vão
## da frente; WeaponShopEntrance cuida do empurrão e da travessia, como no Sede.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const ID := "mining_office"
const STYLE := "escritorio-mina"
## Centro do prédio no espaço da mina; o portão em z=134 fica livre.
const AT := Vector3(12, 0, 126)
const DEPTH := 5.0
## Frente (+Z do kit) virada para -X: a pista passa do lado oeste do escritório.
const YAW := -PI * .5
const ROOM_SIZE := Vector2(9.2, 6.4)

## Linha de base de medição (`mining_office_baseline`) ou fachada pintada desligada: volta a
## guarita só de fachada, sem lugar no catálogo.
static func available() -> bool:
	if Engine.get_meta("mining_office_baseline", false) or not LAYOUT.enabled(): return false
	return PaintedFacadeKit.enabled() and FileAccess.file_exists(PaintedFacadeKit.ROOT + STYLE + "/style.json")

## X local (no kit, antes do giro) do meio do vão com folha da frente.
static func door_x() -> float:
	var width := PaintedFacadeKit.natural_size(STYLE).x
	for opening in PaintedFacadeKit.openings(STYLE, "front"):
		if not opening.leaf: continue
		var rect: Array = opening.rect
		return -width * .5 + width * (float(rect[0]) + float(rect[2])) * .5
	return 0.0

static func basis() -> Basis:
	return Basis(Vector3.UP, YAW)

## Plano da folha pintada, no mundo.
static func door_position() -> Vector3:
	return LAYOUT.CENTER + AT + basis() * Vector3(door_x(), 0, DEPTH * .5)

static func definition_data() -> Dictionary:
	if not available(): return {}
	var outward := basis() * Vector3.BACK
	var door := door_position()
	var size := ROOM_SIZE
	var reward := {"id":"mining_office_cash_01", "kind":"cash", "amount":450, "local_position":Vector3(2.35, 0, -1.25)}
	return {"id":ID, "original_name":"Serra Bruta", "region":"desert", "model":"res://world/mining/MiningOfficeInterior.gd", "source_id":"res://world/mining/MiningOfficeInterior.gd",
		"exterior_position":LAYOUT.CENTER + AT, "exterior_rotation":YAW, "walkup_door_position":door,
		"entry_position":door + outward * 1.4, "return_position":door + outward * 2.4,
		"spawn":Vector3(0, .04, size.y * .5 - 1.4), "exit":Vector3(0, .04, size.y * .5 - .65), "size":size,
		"camera_target":Vector3(0, .65, -.1), "camera_size":maxf(size.x * 1.04, size.y * 1.32),
		"variant":0, "service":"mining_office", "integration_status":"native_geometry",
		"reward":reward, "rewards":[reward], "npcs":[], "npc_model":"", "npc_point":Vector3.ZERO}
