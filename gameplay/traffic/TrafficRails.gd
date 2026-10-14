extends RefCounted
## Trânsito distante conserva sensores e prioridade; só dispensa o solver de rua.
static var enabled := OS.get_environment("GETECO_TRAFFIC_RAILS") != "0"
const OFFSCREEN_DISTANCE := 40.0
const VISIBLE_DISTANCE := 70.0
const ROUTE_END_MARGIN := 14.0
const MAX_ROUTE_ERROR := 0.75
const EXCLUDED_META := ["dispatch_unit", "mission_vehicle", "race_owned", "port_work_vehicle", "armored_transport", "residence_vehicle", "garage_reward", "secret_discovery_vehicle", "gang_hostile", "gang_damage_handler", "desert_drag_physics", "mining_released_load", "awaiting_ground", "crash_stun", "crash_slide", "crash_spin", "targeted", "rails_force_physics"]

var active := false
var force_physics := false
var _wake_pending := false
var steps := 0
var _cooldown := 0.0
var _route: Curve3D
var _offset := 0.0
var _error := Vector3.ZERO
var _last_sample := Vector3.ZERO
var _position := Vector3.ZERO
var _neighbors := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _sweep := PhysicsShapeQueryParameters3D.new()
var _ground := PhysicsRayQueryParameters3D.new()
static var _hazard_frame := -1
static var _hazard_world: Node
static var _hazards: Array[Dictionary] = []
static var _moving_neighbors: Array[Dictionary] = []
## Grade de 16 m dos vizinhos, montada uma vez por passo: cada carro só testa as células em volta,
## como as listas por setor do reVC. O laço sobre todos os carros era n² por passo.
const NEIGHBOR_CELL := 16.0
static var _neighbor_grid := {}
## Vizinho com extensão absurda (carro arremessado, velocidade infinita/NaN) não entra na grade: varrer as
## células dele não terminava. Fica numa lista testada por todos, como antes da grade.
const NEIGHBOR_MAX_CELLS := 3
static var _wide_neighbors: Array = []
static var _view_frame := -1
static var _camera: Camera3D
static var _planes: Array[Plane] = []

func wake(car: CharacterBody3D, cooldown := 0.5) -> void:
	active = false
	force_physics = true
	_wake_pending = true
	_cooldown = maxf(_cooldown,cooldown)
	car._lod_pending = 0.0
	car._lod_skipped = -1
	# Não corrigir posição nem projetar velocidade: o contato recebe o mesmo estado.
	car._invalidate_route_projection()

## Acordado por dano/contato: o próximo passo é físico e não espera a cadência do LOD.
func force_physics_pending() -> bool:
	return _wake_pending

func _eligible(car: CharacterBody3D) -> bool:
	if not enabled or not car.traffic or car.controlled or car.external_input or car.health <= 0 or car.engine_disabled or car.input_locked: return false
	if not car.get_meta("ambient_traffic",false) or car.route == null or car.is_queued_for_deletion(): return false
	if car.archetype.begins_with("police_") or car.vehicle_id in ["neco_tow_truck","story_tow_vehicle"]: return false
	for key in EXCLUDED_META:
		if car.has_meta(key): return false
	if car.backoff_time > 0 or car.unjam_time > 0 or car.bypass_side != 0 or car.bypass_blend != 0 or car.speed < 0: return false
	if car.has_meta("ambient_next_route") or str(car.get_meta("traffic_yield_state","")) != "": return false
	if car.traffic_escape != null and (car.traffic_escape.active or car.traffic_escape.retiring): return false
	return active or car.is_on_floor()

func _far(car: CharacterBody3D) -> bool:
	var world := car.get_parent()
	var player := world.get("player") as Node3D if world != null else null
	if not is_instance_valid(player): return false
	var distance := player.global_position.distance_squared_to(car.global_position)
	if distance <= OFFSCREEN_DISTANCE*OFFSCREEN_DISTANCE: return false
	if distance > VISIBLE_DISTANCE*VISIBLE_DISTANCE: return true
	var camera := car.get_viewport().get_camera_3d()
	if not is_instance_valid(camera): return false
	if _view_frame != Engine.get_physics_frames() or _camera != camera:
		_view_frame = Engine.get_physics_frames()
		_camera = camera
		_planes = camera.get_frustum()
	for plane in _planes:
		if plane.distance_to(car.global_position+Vector3.UP*car.body_height*.5) > car.half_length+2.0: return true
	return false

func prepare(car: CharacterBody3D, delta: float) -> bool:
	force_physics = _wake_pending
	_wake_pending = false
	_cooldown = maxf(0.0,_cooldown-delta)
	if not _eligible(car) or not _far(car):
		if active: wake(car)
		return false
	if _cooldown > 0:
		force_physics = true
		return false
	if active and (car.route != _route or car.global_position.distance_squared_to(_position) > .0001 or _route.sample_baked(_offset,true).distance_squared_to(_last_sample) > .0025):
		wake(car)
		return false
	if not active:
		_route = car.route
		_offset = car._traffic_route_offset(car.global_position)
		_last_sample = _route.sample_baked(_offset,true)
		_error = car.global_position-_last_sample
		_error.y = 0.0
		if _error.length_squared() > MAX_ROUTE_ERROR*MAX_ROUTE_ERROR: return false
	var length := _route.get_baked_length()
	if length < 1 or (_route.get_meta("traffic_open",false) and length-_offset <= ROUTE_END_MARGIN):
		if active: wake(car)
		return false
	var forward := _tangent(_offset,length)
	var future := _tangent(_offset+car.half_length+3.0,length)
	# Retornos e curvas apertadas continuam usando a manobra física já existente.
	if forward.length_squared() < .5 or forward.dot(-car.global_basis.z) < .98 or forward.dot(future) < .94:
		if active: wake(car)
		return false
	if _danger(car,delta):
		wake(car)
		return false
	active = true
	_position = car.global_position
	car.route_distance = _offset
	return true

func _sample(offset: float, length: float) -> Vector3:
	return _route.sample_baked(clampf(offset,0.0,length) if _route.get_meta("traffic_open",false) else fposmod(offset,length),true)

func _tangent(offset: float, length: float) -> Vector3:
	var direction := _sample(offset+.3,length)-_sample(offset-.3,length)
	direction.y = 0.0
	return direction.normalized()

func advance(car: CharacterBody3D, delta: float) -> bool:
	# prepare() acabou de testar o perigo neste mesmo passo; repetir dobrava o laço sobre os vizinhos.
	if not active or not _eligible(car) or car.route != _route:
		wake(car)
		return false
	var length := _route.get_baked_length()
	var next_offset := _offset+maxf(0.0,car.speed)*delta
	if _route.get_meta("traffic_open",false) and length-next_offset <= ROUTE_END_MARGIN:
		wake(car)
		return false
	var next_error := _error.move_toward(Vector3.ZERO,.15*delta)
	var sample := _sample(next_offset,length)
	var next := sample+next_error
	var direction := _tangent(next_offset,length)
	var desired := atan2(-direction.x,-direction.z)
	var yaw := rotate_toward(car.rotation.y,desired,delta*1.7)
	var basis := Basis(Vector3.UP,yaw)
	# O raio curto na altura da rota não confunde o túnel com a avenida acima.
	_ground.from = next+Vector3.UP*.6
	_ground.to = next-Vector3.UP*.6
	_ground.collision_mask = 1
	_ground.exclude = [car.get_rid()]
	var space := car.get_world_3d().direct_space_state
	var ground := space.intersect_ray(_ground)
	if ground.is_empty() or ground.normal.y < cos(car.floor_max_angle) or absf(ground.position.y-sample.y) > .35:
		wake(car)
		return false
	var support_y: float = ground.position.y
	# Apoio do centro sozinho deixaria rodas sobre uma borda sem chão.
	for x in [-car.half_width*.8,car.half_width*.8]:
		for z in [-car.half_length*.8,car.half_length*.8]:
			var corner: Vector3 = next+basis*Vector3(x,0,z)
			_ground.from = corner+Vector3.UP*.6
			_ground.to = corner-Vector3.UP*.6
			var hit := space.intersect_ray(_ground)
			if hit.is_empty() or hit.normal.y < cos(car.floor_max_angle) or absf(hit.position.y-sample.y) > .6:
				wake(car)
				return false
			support_y = maxf(support_y,hit.position.y)
	next.y = support_y+.02
	if absf(next.y-car.global_position.y) > maxf(.08,absf(car.speed)*delta*.3):
		wake(car)
		return false
	_sweep.shape = car.shape.shape
	_sweep.exclude = [car.get_rid()]
	_sweep.collision_mask = 1
	_sweep.transform = Transform3D(basis,car.global_position+basis*car.shape.position)
	_sweep.motion = next-car.global_position
	# Validar o casco inteiro, inclusive ao girar, impede atalhos através de sólidos.
	if not space.intersect_shape(_sweep,1).is_empty() or space.cast_motion(_sweep)[0] < 1.0:
		wake(car)
		return false
	_sweep.transform.origin = next+basis*car.shape.position
	_sweep.motion = Vector3.ZERO
	if not space.intersect_shape(_sweep,1).is_empty():
		wake(car)
		return false
	car.global_position = next
	_position = next
	car.rotation.y = yaw
	car.horizontal_velocity = direction*car.speed
	car.velocity = car.horizontal_velocity
	if next_offset >= length: car.route_laps += 1
	_offset = clampf(next_offset,0.0,length) if _route.get_meta("traffic_open",false) else fposmod(next_offset,length)
	_error = next_error
	_last_sample = _sample(_offset,length)
	car.route_distance = _offset
	steps += 1
	return true

func _danger(car: CharacterBody3D, delta: float) -> bool:
	# Esfera inclui pessoas e veículos; a colisão do carro continua disponível aos outros.
	var own_radius: float = Vector2(car.half_width,car.half_length).length()+.75+absf(car.speed)*delta
	# Margem de aproximação também protege pedestres fora dos grupos de veículos.
	_sphere.radius = own_radius+60.0*delta
	_neighbors.shape = _sphere
	_neighbors.transform = Transform3D(Basis.IDENTITY,car.global_position+Vector3.UP*car.body_height*.5)
	_neighbors.exclude = [car.get_rid()]
	_neighbors.collision_mask = 6
	_neighbors.collide_with_areas = true
	if not car.get_world_3d().direct_space_state.intersect_shape(_neighbors,1).is_empty(): return true
	_cache_hazards(car,delta)
	var center: Vector3 = car.global_position+Vector3.UP*car.body_height*.5
	for neighbor in _nearby_neighbors(center,own_radius):
		if neighbor.id == car.get_instance_id(): continue
		var closest := Geometry3D.get_closest_point_to_segment(center,neighbor.a,neighbor.b)
		var radius: float = own_radius+neighbor.radius
		if center.distance_squared_to(closest) <= radius*radius: return true
	for hazard in _hazards:
		var closest := Geometry3D.get_closest_point_to_segment(center,hazard.a,hazard.b)
		var radius: float = _sphere.radius+hazard.radius
		if center.distance_squared_to(closest) <= radius*radius: return true
	var world := car.get_parent()
	var gameplay: Variant = world.get("gameplay") if world != null else null
	if is_instance_valid(gameplay) and gameplay.has_method("aim_feedback_active") and gameplay.aim_feedback_active():
		var player := world.get("player") as Node3D
		if is_instance_valid(player):
			var closest := Geometry3D.get_closest_point_to_segment(center,player.global_position+Vector3.UP,gameplay.aim_point)
			if center.distance_squared_to(closest) <= _sphere.radius*_sphere.radius: return true
	return false

static func _cache_hazards(car: CharacterBody3D, delta: float) -> void:
	var world := car.get_parent()
	var frame := Engine.get_physics_frames()
	if _hazard_frame == frame and _hazard_world == world: return
	_hazard_frame = frame
	_hazard_world = world
	_hazards.clear()
	_moving_neighbors.clear()
	_neighbor_grid.clear()
	_wide_neighbors.clear()
	var horizon := delta+.1
	var gameplay: Variant = world.get("gameplay") if world != null else null
	if is_instance_valid(gameplay):
		for node in gameplay.get_children():
			var script: Script = node.get_script()
			if script == null or script.resource_path != "res://gameplay/Projectile.gd" or node.detonated: continue
			_hazards.append({"a":node.global_position,"b":node.global_position+node.velocity*horizon,"radius":node.radius})
		var rounds: Variant = gameplay.get("_police_rounds")
		if rounds is Array:
			for round_data in rounds:
				var travel := minf(float(round_data.speed)*horizon,maxf(0.0,float(round_data.range)-float(round_data.distance)))
				_hazards.append({"a":round_data.point,"b":round_data.point+round_data.direction*travel,"radius":0.0})
	for vehicle in car.get_tree().get_nodes_in_group("drivable"):
		if vehicle is CharacterBody3D and vehicle.get("half_length") != null and (vehicle.collision_layer & 6) != 0 and (not is_instance_valid(vehicle.shape) or not vehicle.shape.disabled):
			var center: Vector3 = vehicle.global_position+Vector3.UP*float(vehicle.body_height)*.5
			var radius := Vector2(vehicle.half_width,vehicle.half_length).length()
			var entry := {"id":vehicle.get_instance_id(),"a":center,"b":center+vehicle.velocity*horizon,"radius":radius}
			_moving_neighbors.append(entry)
			# O segmento inteiro entra em todas as células que ele cobre, com o raio do casco.
			var low := Vector2(minf(entry.a.x,entry.b.x)-radius,minf(entry.a.z,entry.b.z)-radius)
			var high := Vector2(maxf(entry.a.x,entry.b.x)+radius,maxf(entry.a.z,entry.b.z)+radius)
			var span := (high-low)/NEIGHBOR_CELL
			if not (low.is_finite() and high.is_finite()) or span.x > NEIGHBOR_MAX_CELLS or span.y > NEIGHBOR_MAX_CELLS:
				_wide_neighbors.append(entry)
				continue
			for cx in range(floori(low.x/NEIGHBOR_CELL),floori(high.x/NEIGHBOR_CELL)+1):
				for cz in range(floori(low.y/NEIGHBOR_CELL),floori(high.y/NEIGHBOR_CELL)+1):
					var key := Vector2i(cx,cz)
					if not _neighbor_grid.has(key): _neighbor_grid[key] = []
					_neighbor_grid[key].append(entry)
		var cannon: Variant = vehicle.get("tank_cannon")
		if not is_instance_valid(cannon): continue
		for shell in cannon.shells:
			_hazards.append({"a":shell.point,"b":shell.point+shell.direction*minf(80.0*horizon,shell.remaining),"radius":5.0})

## Vizinhos cujas células cruzam a esfera do carro; um vizinho em várias células aparece uma vez.
static func _nearby_neighbors(center: Vector3, own_radius: float) -> Array:
	var reach := own_radius+8.0
	var result := _wide_neighbors.duplicate()
	var seen := {}
	if not center.is_finite() or reach > NEIGHBOR_CELL*NEIGHBOR_MAX_CELLS: return _moving_neighbors
	for cx in range(floori((center.x-reach)/NEIGHBOR_CELL),floori((center.x+reach)/NEIGHBOR_CELL)+1):
		for cz in range(floori((center.z-reach)/NEIGHBOR_CELL),floori((center.z+reach)/NEIGHBOR_CELL)+1):
			for entry in _neighbor_grid.get(Vector2i(cx,cz),[]):
				if seen.has(entry.id): continue
				seen[entry.id] = true
				result.append(entry)
	return result
