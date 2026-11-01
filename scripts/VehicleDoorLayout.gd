extends RefCounted
## Embarque: classe de porte (open/car/tall/truck/bus), degrau, centro do vão e banco do motorista,
## e a porta articulada (VehicleDoorPresentation: preparo fatiado, ângulo, abrir/fechar com som).
## Separado de scripts/Vehicle.gd em 01/11 (Onda 3) só para o dono caber na leitura. O estado
## (door_presentation, archetype, casco...) e os comentários que documentam a API continuam no
## Vehicle, que mantém cada função antiga como delegação de uma linha com a mesma assinatura e os
## mesmos padrões. `g` fica como CharacterBody3D, e não como o script do dono, para não criar preload
## cíclico. BiarticulatedBus sobrescreve boarding_class, _cab_z e animate_driver_door, então essas
## passam por `g.`; as outras (sem sobrescrita no repositório) são chamadas aqui direto.

const DOOR_SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
const FIREFLY := preload("res://audio/FireflyBank.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host

func boarding_class() -> String:
	if g.archetype.begins_with("bike_") or g.archetype in ["port_forklift", "beach_buggy", "dune_buggy"]: return "open"
	if g.archetype == "route_city": return "bus"
	# A tabela de portas manda quando tem opinião: vans e picapes têm casco alto sem serem
	# caminhões, e a classe decide o degrau, o banco e o ritmo da entrada.
	var listed: Dictionary = DOOR_SPECS.row(g.archetype)
	if listed.has("class"): return str(listed["class"])
	if g.body_height >= 2.35: return "truck"
	if g.body_height >= 1.75: return "tall"
	return "car"

func boarding_step_height() -> float:
	match g.boarding_class():
		"truck": return clampf(g.body_height * .36, .85, 1.15)
		"bus": return .42
		"tall": return .32
	return 0.0

func _cab_z() -> float:
	var row := DOOR_SPECS.row(g.archetype)
	if not row.is_empty() and g.boarding_class() in ["car", "tall", "truck"] and is_instance_valid(g.visual):
		return (float(row.zf) + float(row.zr)) * .5 * g.visual.scale.z
	match g.boarding_class():
		"bus": return -(g.half_length - .8)
		"truck": return -(g.half_length - 1.3)
	return -clampf(g.half_length * .18, .30, .62)

func _door_seat_z() -> float:
	var row := DOOR_SPECS.row(g.archetype)
	if row.is_empty() or not is_instance_valid(g.visual): return g._cab_z() + .15
	return ((float(row.zf) + float(row.zr)) * .5 - .06) * g.visual.scale.z

func driver_seat_anchor() -> Vector3:
	if g.archetype.begins_with("bike_"): return g.visual.to_global(g._motorcycle_seat)
	# Buggy e empilhadeira não têm porta nem linha no VehicleDoorSpecs: o banco vem do interior.
	var open_seat: Vector3 = preload("res://gameplay/VehicleInterior.gd").open_seat_local(g)
	if open_seat.is_finite(): return g.to_global(open_seat)
	if g.boarding_class() == "bus":
		return g.to_global(Vector3(-minf(.55, g.half_width * .4), .08 + boarding_step_height(), g._cab_z() - .15))
	if g.boarding_class() in ["truck", "tall"]:
		return g.to_global(Vector3(-minf(.45, g.half_width * .3), .08 + boarding_step_height(), _door_seat_z()))
	var seat_z := _door_seat_z() if DOOR_SPECS.has_row(g.archetype) else -clampf(g.half_length * .16, .26, .55)
	var seat := Vector3(-minf(.28, g.half_width * .24), .08, seat_z)
	# O motorista sobe e pula junto com a carroceria do lowrider.
	if g.hydraulics != null: seat = g.hydraulics.body_transform() * seat
	return g.to_global(seat)

func door_layout(side: int) -> Dictionary:
	_ensure_door_presentation()
	if not is_instance_valid(g.door_presentation) or not g.door_presentation.ready_for_boarding: return {}
	return g.door_presentation.layouts.get(side, {})

func pose_driver_door(side: int, radians: float, limit := 0.0, sound := 0) -> void:
	_ensure_door_presentation()
	if not is_instance_valid(g.door_presentation): return
	g.door_presentation.set_angle(side, radians, limit)
	if sound != 0: FIREFLY.door(g, side, sound > 0)

func animate_driver_door(side: int, opened: bool, duration := .28) -> void:
	_ensure_door_presentation()
	if is_instance_valid(g.door_presentation):
		g.door_presentation.set_open(side, opened, duration)
		# Som da porta no mesmo instante da folha (abrir ao chegar, bater ao fechar).
		FIREFLY.door(g, side, opened)

func _ensure_door_presentation() -> void:
	if g.boarding_class() in ["open", "bus"]: return
	g.invalidate_shadow_proxy()
	var began := STALL_WORK.begin()
	if not is_instance_valid(g.door_presentation):
		g.door_presentation = preload("res://gameplay/VehicleDoorPresentation.gd").new()
		g.visual.add_child(g.door_presentation)
		g.door_presentation.configure(g)
	else:
		g.door_presentation.finish_now()
	STALL_WORK.finish_slow("vehicle.doors.prepare", began, 1000, g)

func warm_doors(budget_usec := 2500) -> bool:
	if g.boarding_class() in ["open", "bus"]: return true
	g.invalidate_shadow_proxy()
	if not is_instance_valid(g.door_presentation):
		g.door_presentation = preload("res://gameplay/VehicleDoorPresentation.gd").new()
		g.visual.add_child(g.door_presentation)
		g.door_presentation.configure(g, true)
	return g.door_presentation.advance(budget_usec)
