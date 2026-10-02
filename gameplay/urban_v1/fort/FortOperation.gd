extends Node3D
## Operação do forte: esquadrões, alarme, câmeras de vigilância, navegação interna e
## câmera de acompanhamento. Vive como filho do lugar `mountain_fort` e só existe
## enquanto o jogador está lá dentro.
##
## Fluxo: o terminal do posto de guarda abre a porta blindada; a sala de operações tem
## 5 soldados (2 sentinelas, 2 patrulheiros, 1 líder). Ser visto, ouvido ou flagrado
## pelas câmeras vira combate; o alarme chama o segundo esquadrão (4 soldados) pelas
## portas do fundo. O saque no fundo da sala é o prêmio (persistido como recompensa).
const SOLDIER := preload("res://gameplay/urban_v1/fort/FortSoldier.gd")
const ACTION_PREFIX := "truckers_village_secret_"
const STASH_ID := "mountain_fort_stash_cash"
const CELL := .5
const NAV_ORIGIN := Vector2(-10.5,-25.5)
const NAV_SIZE := Vector2(21.0,33.0)
const CAMERA_SIGHT := 24.0
const CAMERA_COS := .84
const CAMERA_DETECT_TIME := 1.2

var place: Node3D
var model: Node3D
var session
var gameplay: Node
var player: Node3D
var soldiers: Array = []
var alarm_active := false
var reinforcement_delay := 5.0
var reinforced := false
var covers: Array[Dictionary] = []
var claims: Dictionary = {}
var known_player := Vector3.INF
var known_time := 0.0
var camera_progress: Array[float] = [0.0,0.0]
var cleared_announced := false
var _grid: AStarGrid2D
var _clock := 0.0
var _reinforce_timer := -1.0
var _camera_yaw := [0.0,0.0]
var _follow_z := -.4
var _doors_opened := false

func configure(owner_place: Node3D,owner_session) -> void:
	place = owner_place
	model = place.model
	session = owner_session
	gameplay = session.world.gameplay
	player = session.world.player
	name = "FortOperation"
	_build_covers()
	rebuild_navigation()
	if gameplay.has_signal("weapon_fired") and not gameplay.weapon_fired.is_connected(_on_weapon_fired):
		gameplay.weapon_fired.connect(_on_weapon_fired)
	if _stash_taken():
		model.set_blast_open(true)
		rebuild_navigation()
	else:
		_spawn_first_squad()

func _stash_taken() -> bool:
	return session != null and session.state.world_state.rewards.has(STASH_ID)

# --- Porta e terminal ----------------------------------------------------------

func nearest_action() -> Dictionary:
	if not is_instance_valid(player): return {}
	var local := place.to_local(player.global_position)
	if not model.blast_open and local.distance_to(model.DOOR_TERMINAL) <= 1.5:
		return {"id":"urban_v1","target":ACTION_PREFIX+"fort_open_door","label":"Abrir porta blindada"}
	if local.distance_to(model.LIFT_POINT) <= 1.7:
		return {"id":"urban_v1","target":ACTION_PREFIX+"fort_ascend","label":"Subir pelo elevador"}
	return {}

## O elevador só parte com a sala calma: sob fogo as portas não fecham.
func can_ascend() -> bool:
	return not alive_soldiers().any(func(soldier): return soldier.state == "combat")

func perform(target: String) -> bool:
	if target != ACTION_PREFIX+"fort_open_door" or model.blast_open: return false
	model.set_blast_open(true,true)
	# A porta é barulhenta: quem estiver perto do vão ouve.
	_on_weapon_fired("door",place.to_global(Vector3(0,1,-8)),12.0)
	get_tree().create_timer(2.0).timeout.connect(rebuild_navigation)
	return true

# --- Esquadrões ----------------------------------------------------------------

func _spawn_first_squad() -> void:
	for spec in [
		{"id":"fort_a1","role":"sentry","pos":Vector3(-4.5,.04,-22.0),"facing":Vector3(0,0,1)},
		{"id":"fort_a2","role":"sentry","pos":Vector3(6.0,.04,-21.6),"facing":Vector3(-.4,0,1)},
		{"id":"fort_a3","role":"patrol","pos":Vector3(-8.0,.04,-13.0),"route":[Vector3(-8,0,-13),Vector3(-8,0,-21),Vector3(-4,0,-16)]},
		{"id":"fort_a4","role":"patrol","pos":Vector3(8.0,.04,-13.0),"route":[Vector3(8,0,-13),Vector3(4,0,-18),Vector3(8.5,0,-20)]},
		{"id":"fort_a5","role":"leader","pos":Vector3(0,.04,-21.8),"facing":Vector3(0,0,1)},
	]:
		spawn_soldier(spec)

func spawn_soldier(spec: Dictionary) -> Node:
	var soldier = SOLDIER.new()
	soldier.gameplay = gameplay
	soldier.player = player
	soldier.configure(self,spec)
	soldier.position = spec.pos
	add_child(soldier)
	soldier.died.connect(_on_soldier_died)
	soldiers.append(soldier)
	return soldier

func alive_soldiers() -> Array:
	return soldiers.filter(func(soldier): return is_instance_valid(soldier) and not soldier.dead)

func _on_soldier_died(_soldier) -> void:
	if not alive_soldiers().is_empty() or cleared_announced: return
	if alarm_active and not reinforced and _reinforce_timer >= 0: return
	cleared_announced = true
	if session != null: session.show_message("Sala de operações neutralizada. O saque está no fundo.")

# --- Alarme --------------------------------------------------------------------

func trigger_alarm(point: Vector3) -> void:
	if alarm_active: return
	alarm_active = true
	_reinforce_timer = reinforcement_delay
	model.set_alarm_visual(true)
	if session != null: session.show_message("ALARME! Reforços a caminho.")
	report_sighting(null,point)

func _process(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(player): return
	known_time += delta
	_update_cameras(delta)
	if alarm_active:
		for index in model.beacons.size():
			model.beacons[index].light_energy = 1.4+1.6*absf(sin(_clock*5.0+float(index)*PI))
	if _reinforce_timer >= 0:
		_reinforce_timer -= delta
		if _reinforce_timer <= 1.0 and not reinforced and not _doors_opened:
			_doors_opened = true
			model.open_reinforcement_doors(true)
		if _reinforce_timer <= 0 and not reinforced:
			reinforced = true
			_spawn_reinforcements()
	_follow_camera(delta)

func _spawn_reinforcements() -> void:
	var roles := ["flanker","rifleman","flanker","rifleman"]
	for index in 4:
		var door: Vector3 = model.REINFORCEMENT_DOORS[index%2]
		# Whole-number grouping/index; preserve integer truncation and precision.
		@warning_ignore("integer_division")
		var spec := {"id":"fort_b%d"%(index+1),"role":roles[index],"pos":Vector3(door.x+(-.6 if index<2 else .6),.04,door.z+1.0+float(index/2)*.9),
			"facing":Vector3(0,0,1),"alerted":true}
		var soldier = spawn_soldier(spec)
		soldier.last_known = player.global_position
	cleared_announced = false
	get_tree().create_timer(3.0).timeout.connect(func(): if is_instance_valid(model): model.open_reinforcement_doors(false))

func _update_cameras(delta: float) -> void:
	for index in model.camera_heads.size():
		var head: Node3D = model.camera_heads[index]
		_camera_yaw[index] = sin(_clock*.5+float(index)*2.0)*.95
		head.rotation.y = _camera_yaw[index]
		if alarm_active or not is_instance_valid(player):
			continue
		var to := player.global_position+Vector3.UP*1.1-head.global_position
		var sees := to.length() <= CAMERA_SIGHT and to.normalized().dot(head.global_basis.z) >= CAMERA_COS \
			and not blocked(head.global_position,player.global_position+Vector3.UP*1.1)
		camera_progress[index] = clampf(camera_progress[index]+(delta if sees else -delta*.6),0.0,CAMERA_DETECT_TIME)
		if camera_progress[index] >= CAMERA_DETECT_TIME:
			trigger_alarm(player.global_position)

# --- Percepção compartilhada ---------------------------------------------------

func blocked(from: Vector3,to: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from,to,1)
	return not place.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func report_sighting(source,point: Vector3) -> void:
	known_player = point
	known_time = 0.0
	for soldier in alive_soldiers():
		if soldier != source: soldier.alert(point)
	if source != null and is_instance_valid(source) and source.state != "combat": source.alert(point)

func player_point() -> Vector3:
	# O esquadrão comunica por rádio: enquanto alguém viu o jogador há pouco, todos
	# miram na posição real; depois disso vale o último ponto conhecido.
	if known_player.is_finite() and (known_time < 3.0 or alarm_active) and is_instance_valid(player):
		return player.global_position
	return known_player if known_player.is_finite() else (player.global_position if is_instance_valid(player) else Vector3.ZERO)

func _on_weapon_fired(_weapon: String,origin: Vector3,radius := 45.0) -> void:
	for soldier in alive_soldiers():
		if soldier.global_position.distance_to(origin) <= radius: soldier.on_noise(origin,true)

# --- Abrigos -------------------------------------------------------------------

func _build_covers() -> void:
	covers.clear()
	for spec in model.HALL_COVERS:
		var center := Vector3(spec.pos.x,0,spec.pos.y)
		var half_x: float = spec.size.x*.5
		var half_z: float = spec.size.y*.5
		for side in [-1.0,1.0]:
			var local_hide := center+Vector3(0,0,side*(half_z+.65))
			var peeks: Array[Vector3] = []
			for end in [-1.0,1.0]:
				peeks.append(place.to_global(center+Vector3(end*(half_x+.7),0,side*(half_z+.65))))
			covers.append({"key":"%s:%d"%[spec.id,int(side)],"id":spec.id,"hide":place.to_global(local_hide),"peeks":peeks,"x":center.x,"z":center.z})

func pick_cover(soldier,mode: String) -> Dictionary:
	var target := player_point()
	var best := {}
	var best_score := -INF
	var fallback := {}
	var fallback_score := -INF
	for cover in covers:
		var owner_soldier = claims.get(cover.key)
		if owner_soldier != null and owner_soldier != soldier and is_instance_valid(owner_soldier) and not owner_soldier.dead: continue
		var local_hide: Vector3 = cover.hide
		var to_player := local_hide.distance_to(target)
		var distance: float = soldier.global_position.distance_to(local_hide)
		var score := 0.0
		match mode:
			"retreat": score = to_player*1.0-distance*.4
			"advance": score = -distance*.6-to_player*.8
			"flank": score = absf(local_hide.x-target.x)*1.0-distance*.25-absf(to_player-9.0)*.3
			_: score = -distance*1.0-absf(to_player-10.0)*.5
		var hidden := blocked(target+Vector3.UP*1.6,local_hide+Vector3.UP*1.45)
		var too_near: bool = to_player < (6.0 if mode == "retreat" else 3.5)
		if score > fallback_score:
			fallback_score = score
			fallback = cover
		if not hidden or too_near or to_player > 28.0: continue
		if score > best_score:
			best_score = score
			best = cover
	var chosen := best if not best.is_empty() else fallback
	return chosen.duplicate() if not chosen.is_empty() else {}

func claim_cover(cover: Dictionary,soldier) -> void:
	claims[cover.key] = soldier

func release_cover(cover: Dictionary,soldier) -> void:
	if claims.get(cover.key) == soldier: claims.erase(cover.key)

func separation(soldier) -> Vector3:
	var push := Vector3.ZERO
	for other in soldiers:
		if other == soldier or not is_instance_valid(other) or other.dead: continue
		var offset: Vector3 = soldier.global_position-other.global_position
		offset.y = 0
		var distance := offset.length()
		if distance < .9 and distance > .01: push += offset.normalized()*(.9-distance)*2.2
	return push

# --- Navegação -----------------------------------------------------------------

func rebuild_navigation() -> void:
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(0,0,int(NAV_SIZE.x/CELL),int(NAV_SIZE.y/CELL))
	_grid.cell_size = Vector2(CELL,CELL)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	var room: Rect2 = model.ROOM_BOUNDS
	for x in _grid.region.size.x:
		for y in _grid.region.size.y:
			var point := NAV_ORIGIN+Vector2(float(x)+.5,float(y)+.5)*CELL
			if not room.grow(-.55).has_point(point): _grid.set_point_solid(Vector2i(x,y),true)
	for body in model.solids:
		if body.collision_layer == 0 or not body.has_meta("bounds"): continue
		var bounds: AABB = body.get_meta("bounds")
		if bounds.position.y > 1.4 or bounds.end.y < .15: continue
		var rect := Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).grow(.42)
		var from := _cell(rect.position)
		var to := _cell(rect.end)
		for x in range(maxi(from.x,0),mini(to.x,_grid.region.size.x-1)+1):
			for y in range(maxi(from.y,0),mini(to.y,_grid.region.size.y-1)+1):
				_grid.set_point_solid(Vector2i(x,y),true)

func _cell(local: Vector2) -> Vector2i:
	return Vector2i(int(floor((local.x-NAV_ORIGIN.x)/CELL)),int(floor((local.y-NAV_ORIGIN.y)/CELL)))

func _nearest_free(cell: Vector2i) -> Vector2i:
	if _grid.region.has_point(cell) and not _grid.is_point_solid(cell): return cell
	for radius in range(1,8):
		for dx in range(-radius,radius+1):
			for dy in range(-radius,radius+1):
				var candidate := cell+Vector2i(dx,dy)
				if _grid.region.has_point(candidate) and not _grid.is_point_solid(candidate): return candidate
	return cell

func to_world(local: Vector3) -> Vector3:
	return place.to_global(local)

func find_path(from_world: Vector3,to_world_point: Vector3) -> PackedVector3Array:
	var from_local := place.to_local(from_world)
	var local_to_local := place.to_local(to_world_point)
	var start := _nearest_free(_cell(Vector2(from_local.x,from_local.z)))
	var goal := _nearest_free(_cell(Vector2(local_to_local.x,local_to_local.z)))
	var result := PackedVector3Array()
	for cell in _grid.get_id_path(start,goal):
		var point := NAV_ORIGIN+(Vector2(cell)+Vector2(.5,.5))*CELL
		result.append(place.to_global(Vector3(point.x,local_to_local.y,point.y)))
	if result.is_empty(): result.append(to_world_point)
	return result

# --- Câmera --------------------------------------------------------------------

func _follow_camera(delta: float) -> void:
	# Ante-sala usa o enquadramento fixo do lugar; ao entrar na sala de operações a
	# câmera acompanha o jogador para o combate ficar legível.
	var local := place.to_local(player.global_position)
	var wanted := clampf(local.z-2.5,-18.0,-.4)
	_follow_z = lerpf(_follow_z,wanted,1.0-exp(-4.0*delta))
	session.anchor.position = place.to_global(Vector3(0,.7,_follow_z))
	var size := lerpf(17.0,16.0,clampf((-local.z-4.0)/6.0,0.0,1.0))
	session.world.camera.target_size = size
	session.world.camera.size = size
