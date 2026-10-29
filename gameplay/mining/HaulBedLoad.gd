extends Node
## Carga a granel na caçamba do caminhão da mina (28/10). Antes a caçamba só inclinava no visual: ela não tem
## colisão própria, então a rocha largada pela pá caía no casco cinemático e ficava para trás quando o caminhão
## andava. Aqui a rocha que cai dentro do volume da caçamba assenta numa vaga do piso e acompanha a caçamba
## (inclusive a inclinação); ao inclinar, as rochas escorregam para a tampa traseira e, passada a borda, voltam
## a ser corpos físicos soltos no chão. Sem varredura do mapa: só o grupo "mining_cargo" (poucas rochas).
const FLOOR_Y := .44
const TAIL_Z := .51
const FRONT_Z := -4.3
const HALF_WIDTH := 2.0
const SLOTS := [Vector2(-.95,-3.45),Vector2(.95,-3.45),Vector2(-.95,-1.95),Vector2(.95,-1.95),Vector2(-.95,-.45),Vector2(.95,-.45)]
const SETTLE_SPEED := 6.0
## Abaixo disso a caçamba ainda segura; acima as rochas descem para a tampa.
const SLIDE_FROM := .3
const RELEASE_GRACE := .8

var vehicle: CharacterBody3D
var bed: Node3D
## rocha -> {"slot": índice, "local": Transform3D no espaço da caçamba}
var seated := {}
var _released: Array = []

func configure(car: CharacterBody3D, dump_bed: Node3D) -> void:
	vehicle = car
	bed = dump_bed
	name = "HaulBedLoad"
	vehicle.destroyed.connect(release_all)

func loaded() -> int:
	return seated.size()

func step(delta: float, dump: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(bed): return
	_expire_releases(delta)
	if vehicle.health > 0: _capture()
	var tail_out := TAIL_Z + .75
	for rock in seated.keys():
		if not is_instance_valid(rock) or rock.is_queued_for_deletion():
			seated.erase(rock)
			continue
		var entry: Dictionary = seated[rock]
		var local: Transform3D = entry.local
		var rest: float = FLOOR_Y + float(rock.get_meta("mining_origin_height",.58))
		local.origin.y = move_toward(local.origin.y, rest, SETTLE_SPEED*delta)
		if dump > SLIDE_FROM:
			# Escorrega pelo piso inclinado em direção à tampa; quanto mais inclinada, mais rápido.
			local.origin.z += (dump-SLIDE_FROM)*5.5*delta
			local.origin.y = rest
		entry.local = local
		rock.global_transform = bed.global_transform*local
		if local.origin.z > tail_out: _release(rock, dump)

## Rocha solta dentro do volume da caçamba (ou presa no casco logo abaixo dele) assenta numa vaga livre.
func _capture() -> void:
	if seated.size() >= SLOTS.size(): return
	for node in get_tree().get_nodes_in_group("mining_cargo"):
		var rock := node as RigidBody3D
		if rock == null or seated.has(rock) or rock.freeze or rock.has_meta("mining_carried_by") or _released.any(func(item): return item.rock == rock): continue
		var local := bed.global_transform.affine_inverse()*rock.global_position
		if absf(local.x) > HALF_WIDTH or local.z < FRONT_Z-.2 or local.z > TAIL_Z or local.y < -1.2 or local.y > 3.2: continue
		var slot := _free_slot(Vector2(local.x,local.z))
		if slot < 0: return
		_seat(rock, slot, local)

func _free_slot(near: Vector2) -> int:
	var taken := {}
	for entry in seated.values(): taken[int(entry.slot)] = true
	var best := -1
	var gap := INF
	for index in SLOTS.size():
		if taken.has(index): continue
		var distance: float = near.distance_to(SLOTS[index])
		if distance < gap:
			gap = distance
			best = index
	return best

func _seat(rock: RigidBody3D, slot: int, local_point: Vector3) -> void:
	rock.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	rock.freeze = true
	rock.linear_velocity = Vector3.ZERO
	rock.angular_velocity = Vector3.ZERO
	rock.set_meta("mining_carried_by", vehicle.get_instance_id())
	rock.add_collision_exception_with(vehicle)
	vehicle.add_collision_exception_with(rock)
	var basis := bed.global_basis.inverse()*rock.global_basis
	# Cai na vaga a partir de onde estava (sem teleporte para baixo): só x/z vão direto para a vaga.
	var origin := Vector3(SLOTS[slot].x, maxf(local_point.y, FLOOR_Y), SLOTS[slot].y)
	seated[rock] = {"slot": slot, "local": Transform3D(basis.orthonormalized(), origin)}

func _release(rock: RigidBody3D, dump := 0.0) -> void:
	seated.erase(rock)
	if not is_instance_valid(rock): return
	rock.remove_meta("mining_carried_by")
	rock.freeze = false
	rock.sleeping = false
	var tail := bed.global_basis.z.normalized()
	rock.linear_velocity = vehicle.velocity + tail*(1.0+dump*1.5)
	# Ainda encostada na traseira: a exceção com o casco sai só depois que ela cai.
	_released.append({"rock": rock, "left": RELEASE_GRACE})

func _expire_releases(delta: float) -> void:
	for index in range(_released.size()-1, -1, -1):
		var item: Dictionary = _released[index]
		item.left = float(item.left)-delta
		if float(item.left) > 0.0 and is_instance_valid(item.rock): continue
		if is_instance_valid(item.rock) and is_instance_valid(vehicle):
			item.rock.remove_collision_exception_with(vehicle)
			vehicle.remove_collision_exception_with(item.rock)
		_released.remove_at(index)

func release_all() -> void:
	for rock in seated.keys(): _release(rock)
	seated.clear()

func _exit_tree() -> void:
	for rock in seated.keys():
		if is_instance_valid(rock):
			rock.remove_meta("mining_carried_by")
			rock.freeze = false
	seated.clear()
