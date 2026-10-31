extends Node
## Deformação de malha só por evento. As malhas intactas ficam compartilhadas até o primeiro amassado.
## Os registros usam metros locais do veículo; reconstruir a partir do repouso deixa save/load exato.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const MAX_DENTS := 12
const MAX_DEPTH := .34
const MAX_VERTICES := 60000
const REST_MESH_META := "body_dents_rest_mesh"
## Arrays em repouso por Mesh compartilhado. `surface_get_arrays` lê o buffer de volta da GPU
## e, no RenderingDevice, espera os quadros em voo terminarem: cada carro batido pela primeira
## vez pagava isso por superfície (street.crash.damage_self ~4 ms p50 e até 12 ms no release,
## logs de 13-15/10). Carros do mesmo modelo dividem as malhas, então a leitura é uma por malha.
## Limitado: malha recortada (porta) é única do carro e não deve ficar presa para sempre.
const REST_CACHE_LIMIT := 48
static var _rest_cache: Dictionary = {}   # Mesh -> Array (arrays por superfície)
var vehicle: CharacterBody3D
var dents: Array = []
var parts: Array[Dictionary] = []
var prepared := false
var rebuild_usec := 0
var _remaining := 0.0
var _kick := Vector3.ZERO
var _last_rotation := Vector3.ZERO
var _last_position := Vector3.ZERO

func configure(car: CharacterBody3D) -> void:
	vehicle=car
	set_process(false)
	set_physics_process(false)

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

static func valid_records(value: Variant) -> bool:
	if not value is Array or value.size()>MAX_DENTS: return false
	for row in value:
		if not row is Dictionary: return false
		for field in ["point","direction"]:
			if not row.get(field) is Array or row[field].size()!=3: return false
			for number in row[field]:
				if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or absf(float(number))>20: return false
		var direction:=Vector3(row.direction[0],row.direction[1],row.direction[2])
		if absf(direction.length()-1)>.01 or absf(direction.y)>.01: return false
		for field in ["radius","depth"]:
			if typeof(row.get(field)) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(row[field])): return false
		if row.radius<.3 or row.radius>1.6 or row.depth<=0 or row.depth>MAX_DEPTH: return false
	return true

func snapshot() -> Array:
	return dents.duplicate(true)

func restore_records(records: Array) -> void:
	if not valid_records(records): return
	clear()
	dents=records.duplicate(true)
	if not dents.is_empty(): _prepare(); _rebuild()

func impact(amount: float, point: Vector3, contact_inward := Vector3.ZERO) -> void:
	if amount<2 or not is_finite(amount) or not point.is_finite(): return
	if vehicle.archetype.begins_with("bike_") or vehicle.archetype in ["army_tank","biarticulated_510"]: return
	var frontal:=absf(point.z)/maxf(vehicle.half_length,.1)>=absf(point.x)/maxf(vehicle.half_width,.1)
	var direction:=Vector3(0,0,-signf(point.z)) if frontal else Vector3(-signf(point.x),0,0)
	if contact_inward.is_finite() and contact_inward.length_squared()>.01:
		direction=Vector3(contact_inward.x,0,contact_inward.z).normalized()
	if direction.length_squared()<.5: return
	point.x=clampf(point.x,-vehicle.half_width,vehicle.half_width)
	point.z=clampf(point.z,-vehicle.half_length,vehicle.half_length)
	point.y=clampf(point.y,.35,minf(.8,vehicle.body_height*.5))
	var depth:=clampf(amount*.009,.025,.26 if contact_inward.length_squared()>.01 else .20)
	var row: Dictionary={}
	for existing in dents:
		var old:=Vector3(existing.point[0],existing.point[1],existing.point[2])
		var inward:=Vector3(existing.direction[0],existing.direction[1],existing.direction[2])
		if old.distance_to(point)<.65 and inward.dot(direction)>.9: row=existing; break
	if row.is_empty():
		if dents.size()>=MAX_DENTS: return
		row={"point":[point.x,point.y,point.z],"direction":[direction.x,direction.y,direction.z],"radius":1.25 if frontal else 1.0,"depth":0.0}
		dents.append(row)
	var prior:=float(row.depth)
	row.depth=minf(MAX_DEPTH,prior+depth)
	if row.depth>prior:
		var fresh:=not prepared
		# Spans (22/10): a 1ª batida custa 19–21 ms (vehicle.impact.dents) sem dizer se é leitura ou cálculo.
		var stage := STALL_WORK.begin()
		_prepare()
		STALL_WORK.finish_slow("vehicle.dents.prepare", stage, 2000)
		stage = STALL_WORK.begin()
		# Só este amassado mudou: o resto da lataria continua exatamente como estava.
		if _async_active(): _request_rebuild({} if fresh else row)
		else: _rebuild({} if fresh else row)
		STALL_WORK.finish_slow("vehicle.dents.rebuild_full" if fresh else "vehicle.dents.rebuild_partial", stage, 2000)
	# Short damped body recoil. No permanent processing on damaged vehicles.
	if vehicle.controlled and vehicle.health>0:
		_kick=Vector3(direction.z,0,-direction.x)*clampf(amount*.002,.012,.045)
		_remaining=.38
		set_process(true)

func _prepare() -> void:
	if prepared: return
	prepared=true
	var inverse:=vehicle.global_transform.affine_inverse()
	var total:=0
	for part: MeshInstance3D in vehicle.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.skeleton!=NodePath("") or part.is_queued_for_deletion() or not part.visible: continue
		var path:=str(vehicle.visual.get_path_to(part)).to_lower()
		if "wheel" in path or "interior" in path or "rider" in path: continue
		var eligible: Array[bool] = []
		var painted:=false
		var detachable:=part.has_meta("breakaway_part_id")
		# Papel antes da geometria: peça sem pintura (vidro, farol, cromado) não lê arrays.
		for surface in part.mesh.get_surface_count():
			var material:=part.get_active_material(surface)
			var role:=ROLES.key(part,surface).get_slice("#",0)
			# A lista da pintura é tipada (StandardMaterial3D): procurar um ShaderMaterial (pintura
			# molhada, para-brisa) nela registrava erro do motor a cada batida, sem mudar o resultado.
			var is_paint: bool=detachable or role=="paint" or (vehicle._paint!=null and material is StandardMaterial3D and material in vehicle._paint.materials and role!="roof_paint")
			eligible.append(is_paint)
			painted=painted or is_paint
		if not painted: continue
		var count:=0
		for surface in part.mesh.get_surface_count(): count+=part.mesh.surface_get_array_len(surface)
		if total+count>MAX_VERTICES: continue
		var read_began := STALL_WORK.begin()
		var rest_mesh := preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").pristine_part(vehicle,part)
		var arrays:=_rest_arrays(rest_mesh)
		# Qual peça ainda cai fora dos caches (22/10: 3–5 ms de leitura da GPU por 1ª batida nos sobrados e no
		# porto mesmo com a frota pré-lida); o span diz o modelo e a peça.
		if read_began != 0 and Time.get_ticks_usec() - read_began >= 1000:
			STALL_WORK.finish("vehicle.dents.rest_miss", read_began, {"archetype": vehicle.archetype,
				"part": str(vehicle.visual.get_path_to(part)), "mesh": part.mesh.resource_name})
		total+=count
		parts.append({"node":part,"mesh":rest_mesh,"arrays":arrays,"eligible":eligible,"transform":inverse*part.global_transform})
		part.set_meta(REST_MESH_META,rest_mesh)

## Arrays em repouso da frota inteira lidas sob a cortina (22/10): o cache acima guarda 48 malhas e a
## frota passa disso, então a 1ª batida de cada modelo ainda lia a GPU no quadro do choque
## (vehicle.dents.readback 6–14 ms, até 8 superfícies). Só malhas dos modelos da frota (compartilhadas
## por todos os carros do modelo); portas recortadas, únicas de cada carro, seguem no cache limitado.
## GETECO_DENTS_FLEET_PREWARM=0 desliga.
static var _fleet_rest: Dictionary = {}
static var fleet_rest_vertices := 0

static func prewarm_rest(model: Node3D) -> void:
	if OS.get_environment("GETECO_DENTS_FLEET_PREWARM") == "0" or model == null: return
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		# Só ArrayMesh (a lataria da frota): primitivas (barra de luz, faróis em caixa) não têm
		# surface_get_array_len e nunca entram no amassado como peça pintada da frota.
		if not part.mesh is ArrayMesh or part.skeleton!=NodePath("") or _fleet_rest.has(part.mesh): continue
		var path:=str(model.get_path_to(part)).to_lower()
		if "wheel" in path or "interior" in path or "rider" in path: continue
		# Mesma leitura do caminho do jogo; a cópia sai do cache limitado para o da frota.
		var arrays: Array=_rest_arrays(part.mesh)
		_rest_cache.erase(part.mesh)
		for surface in part.mesh.get_surface_count(): fleet_rest_vertices += part.mesh.surface_get_array_len(surface)
		_fleet_rest[part.mesh]=arrays

## Malha montada na CPU por outro módulo (porta recortada, VehicleDoorBuilder): as arrays de origem
## entram no cache limitado e o 1º amassado depois do recorte não lê a GPU. GETECO_DENTS_DOOR_PRIME=0 desliga.
static func prime_rest(mesh: Mesh, arrays: Array) -> void:
	if OS.get_environment("GETECO_DENTS_DOOR_PRIME") == "0" or mesh == null or arrays.size() != mesh.get_surface_count(): return
	_rest_cache.erase(mesh)
	while _rest_cache.size()>=REST_CACHE_LIMIT: _rest_cache.erase(_rest_cache.keys()[0])
	_rest_cache[mesh]=arrays

## Arrays em repouso da frota já lidas, para quem só precisa ler vértices (VehicleEquipment._car_points).
static func cached_rest(mesh: Mesh) -> Array:
	var fleet: Array=_fleet_rest.get(mesh,[])
	return fleet if _valid_rest(fleet, mesh) else []

static func _valid_rest(cached: Array, mesh: Mesh) -> bool:
	if cached.is_empty() or cached.size()!=mesh.get_surface_count(): return false
	for surface in cached.size():
		if (cached[surface][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()!=mesh.surface_get_array_len(surface): return false
	return true

static func _rest_arrays(mesh: Mesh) -> Array:
	var fleet: Array=_fleet_rest.get(mesh,[])
	if _valid_rest(fleet, mesh): return fleet
	var cached: Array=_rest_cache.get(mesh,[])
	# Alguém reescreveu as superfícies da malha no lugar: a cópia não vale mais.
	var valid:=cached.size()==mesh.get_surface_count()
	for surface in cached.size():
		if not valid: break
		valid=(cached[surface][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()==mesh.surface_get_array_len(surface)
	if valid and not cached.is_empty(): return cached
	var read_began := STALL_WORK.begin()
	var arrays: Array=[]
	for surface in mesh.get_surface_count(): arrays.append(MESH_ARRAYS.arrays_of(mesh, surface))
	STALL_WORK.finish_slow("vehicle.dents.readback", read_began, 1000)
	_rest_cache.erase(mesh)
	while _rest_cache.size()>=REST_CACHE_LIMIT: _rest_cache.erase(_rest_cache.keys()[0])
	_rest_cache[mesh]=arrays
	return arrays

## Peça cuja caixa (em repouso, coordenadas do veículo) fica fora da esfera do amassado.
static func _outside(entry: Dictionary, point: Vector3, radius: float) -> bool:
	var box: AABB=(entry.transform as Transform3D)*(entry.mesh as Mesh).get_aabb()
	var nearest:=point.clamp(box.position,box.end)
	return nearest.distance_squared_to(point)>=radius*radius

## `changed` vazio = reconstrói tudo a partir do repouso (primeira batida, carga, troca de malha).
## Com o registro que acabou de aprofundar, só vértices dentro do raio dele mudam: o deslocamento
## de cada vértice só depende dos amassados que o alcançam (peso zero fora do raio). Os demais
## reaproveitam a posição já aplicada, então o resultado é o mesmo da reconstrução completa.
func _rebuild(changed: Dictionary = {}) -> void:
	# Caminho síncrono (carga do save, troca de malha, testes): um cálculo em voo deixa de valer.
	_generation += 1
	_pending = null
	var started:=Time.get_ticks_usec()
	var job:=_make_job(changed)
	_compute(job)
	_apply_job(job)
	rebuild_usec=Time.get_ticks_usec()-started

## Amassado calculado fora do thread principal (22/10). Na 1ª batida de cada carro a reconstrução da
## lataria inteira custava 8–10 ms de GDScript (vehicle.dents.rebuild_full), no mesmo quadro de física
## da batida; com a leitura das arrays, 19–25 ms (estresse de 22/10, oeste/porto/sobrados). O cálculo
## (posições, normais, tangentes) é o mesmo de antes, sobre cópias; só a malha nova entra no thread
## principal, um ou dois quadros depois do choque. Outra batida no meio espera e refaz, parcial se for
## o mesmo registro. Headless (testes) continua síncrono. GETECO_DENTS_ASYNC=0 volta ao síncrono.
static var async_enabled := OS.get_environment("GETECO_DENTS_ASYNC") != "0"
static var async_in_headless := false
var _task := -1
var _job: Dictionary = {}
var _job_started := 0
var _pending: Variant = null
var _generation := 0

func _async_active() -> bool:
	return async_enabled and (async_in_headless or DisplayServer.get_name() != "headless")

func _request_rebuild(changed: Dictionary) -> void:
	# Aplicação fatiada ainda no meio conta como cálculo em andamento: a próxima espera.
	if _task >= 0 or not _apply_items.is_empty():
		# Dois registros diferentes (ou uma completa) no meio: a próxima é completa, sempre correta.
		if _pending == null: _pending = changed
		elif changed.is_empty() or (_pending as Dictionary).is_empty() or _pending != changed: _pending = {}
		set_process(true)
		return
	_job = _make_job(changed)
	_job_started = Time.get_ticks_usec()
	_task = _launch(_job)
	set_process(true)

static func _launch(job: Dictionary) -> int:
	return WorkerThreadPool.add_task(func() -> void: _compute(job), false, "VehicleBodyDents")

func _poll_rebuild() -> void:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task): return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var job := _job
	_job = {}
	if int(job.get("generation", -1)) == _generation:
		# Sem janela (testes de contrato) aplica no ato, como antes.
		if sliced_apply and DisplayServer.get_name() != "headless":
			_apply_items = (job.work as Array).duplicate()
			_step_apply()
			return
		var stage := STALL_WORK.begin()
		_apply_job(job)
		STALL_WORK.finish_slow("vehicle.dents.apply", stage, 2000)
		rebuild_usec = Time.get_ticks_usec() - _job_started
	_request_pending()

func _request_pending() -> void:
	if _pending != null and is_instance_valid(vehicle):
		var next: Dictionary = _pending
		_pending = null
		_request_rebuild(next)

## Aplicação fatiada (27/10): `vehicle.dents.apply` levava 8–20 ms num quadro (rodada de 24/10), com o
## cálculo já no trabalhador; o que sobrava no thread principal era montar a malha nova de cada peça
## (envio à GPU) e refazer o vidro. Agora vai uma peça por vez até ~2 ms por quadro, e o vidro sozinho
## no fim, cada um com span. O amassado aparece em 2–3 quadros. GETECO_DENTS_SLICED_APPLY=0 volta ao ato.
static var sliced_apply := OS.get_environment("GETECO_DENTS_SLICED_APPLY") != "0"
const APPLY_SLICE_USEC := 2000
var _apply_items: Array = []

func _step_apply() -> void:
	var began := Time.get_ticks_usec()
	var stage := STALL_WORK.begin()
	while not _apply_items.is_empty():
		_apply_item(_apply_items.pop_front())
		if Time.get_ticks_usec() - began >= APPLY_SLICE_USEC: break
	STALL_WORK.finish_slow("vehicle.dents.apply.mesh", stage, 2000)
	if not _apply_items.is_empty():
		set_process(true)
		return
	stage = STALL_WORK.begin()
	preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").geometry_changed(vehicle)
	STALL_WORK.finish_slow("vehicle.dents.apply.glass", stage, 2000)
	rebuild_usec = Time.get_ticks_usec() - _job_started
	_request_pending()

## Tudo que o cálculo lê, copiado ou compartilhado só para leitura (arrays em repouso do cache).
func _make_job(changed: Dictionary) -> Dictionary:
	var partial:=not changed.is_empty()
	var changed_point:=Vector3(changed.point[0],changed.point[1],changed.point[2]) if partial else Vector3.ZERO
	var changed_radius:=float(changed.radius) if partial else 0.0
	# Registros convertidos uma vez, não por vértice.
	var dent_points: Array[Vector3]=[]
	var dent_offsets: Array[Vector3]=[]
	var dent_radii: Array[float]=[]
	for row in dents:
		dent_points.append(Vector3(row.point[0],row.point[1],row.point[2]))
		dent_offsets.append(Vector3(row.direction[0],row.direction[1],row.direction[2])*float(row.depth))
		dent_radii.append(float(row.radius))
	var work: Array[Dictionary]=[]
	for entry in parts:
		var part: MeshInstance3D=entry.node
		if not is_instance_valid(part) or not part.visible: continue
		if partial and entry.has("applied_mesh") and part.mesh==entry.applied_mesh and _outside(entry,changed_point,changed_radius): continue
		var reuse: bool=partial and entry.has("applied_mesh") and part.mesh==entry.applied_mesh
		var primitives: Array[int]=[]
		for surface in entry.arrays.size(): primitives.append(entry.mesh.surface_get_primitive_type(surface))
		work.append({"entry":entry,"arrays":entry.arrays,"eligible":entry.eligible,"transform":entry.transform,
			"hood":part.get_meta("breakaway_part_id","")=="hood","reuse":reuse,"primitives":primitives,
			"rest_points":(entry.get("rest_points",[]) as Array).duplicate(),"applied_vertices":(entry.get("applied_vertices",[]) as Array).duplicate()})
	return {"generation":_generation,"partial":partial,"changed_point":changed_point,"changed_radius":changed_radius,
		"dent_points":dent_points,"dent_offsets":dent_offsets,"dent_radii":dent_radii,"body_height":float(vehicle.body_height),"work":work}

## Só dados: roda no thread principal (síncrono) ou num trabalhador do WorkerThreadPool.
static func _compute(job: Dictionary) -> void:
	var changed_point: Vector3=job.changed_point
	var changed_radius: float=job.changed_radius
	var dent_points: Array[Vector3]=job.dent_points
	var dent_offsets: Array[Vector3]=job.dent_offsets
	var dent_radii: Array[float]=job.dent_radii
	var body_height: float=job.body_height
	for item: Dictionary in job.work:
		var transform: Transform3D=item.transform
		var inverse:=transform.affine_inverse()
		var hood: bool=item.hood
		var reuse: bool=item.reuse
		var rest_list: Array=item.rest_points
		var applied_list: Array=item.applied_vertices
		var surfaces: Array=[]
		for surface in (item.arrays as Array).size():
			var arrays: Array=(item.arrays[surface] as Array).duplicate()
			if item.eligible[surface]:
				var source: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
				while rest_list.size()<=surface: rest_list.append(null)
				while applied_list.size()<=surface: applied_list.append(null)
				if rest_list[surface]==null:
					var points:=PackedVector3Array()
					points.resize(source.size())
					for index in source.size(): points[index]=transform*source[index]
					rest_list[surface]=points
				var rest_points: PackedVector3Array=rest_list[surface]
				var applied: Variant=applied_list[surface] if reuse else null
				var vertices: PackedVector3Array=(applied as PackedVector3Array).duplicate() if applied!=null else source.duplicate()
				var radius_squared:=changed_radius*changed_radius
				for index in vertices.size():
					var rest:=rest_points[index]
					if applied!=null and rest.distance_squared_to(changed_point)>=radius_squared: continue
					# Beltline/roof and cabin remain stable, including upper door frames.
					var belt:=1.0 if hood else 1.0-smoothstep(body_height*.58,body_height*.82,rest.y)
					var displacement:=Vector3.ZERO
					for dent in dent_points.size():
						var distance:=rest.distance_to(dent_points[dent])/dent_radii[dent]
						if distance>=1: continue
						var weight:=pow(1.0-distance*distance,2)*belt
						displacement+=dent_offsets[dent]*weight
						# A tampa do motor empena para cima enquanto a borda dianteira se comprime para dentro.
						# A traseira dela continua presa pelo mesmo decaimento espacial; teto/cabine não levantam.
						if hood: displacement.y+=maxf(0.0,dent_offsets[dent].z)*weight*.55
					if displacement.length()>MAX_DEPTH: displacement=displacement.normalized()*MAX_DEPTH
					vertices[index]=inverse*(rest+displacement)
				arrays[Mesh.ARRAY_VERTEX]=vertices
				applied_list[surface]=vertices
				# Mantém a topologia, os UVs e as emendas divididas definidos. SurfaceTool reindexa
				# malhas exportadas, o que pode fundir vértices em fronteiras duras de painel.
				_update_normals(arrays)
			surfaces.append(arrays)
		item["surfaces"]=surfaces

## Thread principal: malhas novas a partir do cálculo pronto.
func _apply_job(job: Dictionary) -> void:
	for item: Dictionary in job.work: _apply_item(item)
	preload("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").geometry_changed(vehicle)

func _apply_item(item: Dictionary) -> void:
	var entry: Dictionary=item.entry
	var part: MeshInstance3D=entry.node
	if not is_instance_valid(part) or not item.has("surfaces"): return
	var mesh:=ArrayMesh.new()
	var surfaces: Array=item.surfaces
	for surface in surfaces.size():
		mesh.add_surface_from_arrays(item.primitives[surface],surfaces[surface])
		mesh.surface_set_material(surface,entry.mesh.surface_get_material(surface))
		preload("res://gameplay/VehicleInterior.gd").remember_contact(mesh,surface,surfaces[surface])
	entry["rest_points"]=item.rest_points
	entry["applied_vertices"]=item.applied_vertices
	part.mesh=mesh
	entry["applied_mesh"]=mesh

static func _update_normals(arrays: Array) -> void:
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var normals:=PackedVector3Array()
	normals.resize(vertices.size())
	var count:=indices.size() if not indices.is_empty() else vertices.size()
	for triangle in range(0,count-2,3):
		var a:=indices[triangle] if not indices.is_empty() else triangle
		var b:=indices[triangle+1] if not indices.is_empty() else triangle+1
		var c:=indices[triangle+2] if not indices.is_empty() else triangle+2
		var normal:=(vertices[b]-vertices[a]).cross(vertices[c]-vertices[a])
		# Godot's front faces use clockwise winding.
		normals[a]-=normal; normals[b]-=normal; normals[c]-=normal
	for index in normals.size(): normals[index]=normals[index].normalized()
	arrays[Mesh.ARRAY_NORMAL]=normals
	if arrays[Mesh.ARRAY_TANGENT]!=null:
		var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT].duplicate()
		for index in normals.size():
			var offset:=index*4
			var tangent:=Vector3(tangents[offset],tangents[offset+1],tangents[offset+2])
			tangent=(tangent-normals[index]*tangent.dot(normals[index])).normalized()
			tangents[offset]=tangent.x; tangents[offset+1]=tangent.y; tangents[offset+2]=tangent.z
		arrays[Mesh.ARRAY_TANGENT]=tangents

func clear() -> void:
	_generation += 1
	_pending = null
	_apply_items.clear()
	_stop_recoil()
	for entry in parts:
		if is_instance_valid(entry.node):
			entry.node.mesh=entry.mesh
			if entry.node.has_meta(REST_MESH_META): entry.node.remove_meta(REST_MESH_META)
	dents.clear()
	parts.clear()
	prepared=false

## Os builders de porta/teto leem a geometria intacta via REST_MESH_META. Depois da
## troca atômica deles, adota essa nova topologia e reaplica os mesmos registros de dano.
## Isso impede que um reparo ou outro impacto ressuscite um painel de porta fechado.
func geometry_changed() -> void:
	# Topologia nova: o resto de uma aplicação fatiada é de peças antigas.
	_apply_items.clear()
	if dents.is_empty(): return
	_stop_recoil()
	var keep: Dictionary = {}
	for entry in parts:
		var part: MeshInstance3D=entry.node
		if not is_instance_valid(part): continue
		if part.mesh==entry.get("applied_mesh"):
			keep[part]=part.mesh
			part.mesh=entry.mesh
		if part.has_meta(REST_MESH_META): part.remove_meta(REST_MESH_META)
	parts.clear()
	prepared=false
	_prepare()
	if not _async_active():
		_rebuild()
		return
	# Assíncrono (22/10): a viatura que chega batida trocava as portas e refazia a lataria inteira no
	# mesmo quadro (dispatch.doors.prewarm 19 ms). As peças só amassadas seguem com a malha amassada
	# até a nova chegar; o repouso já foi lido acima, com a malha inteira no lugar.
	_generation += 1
	_pending = null
	for part: MeshInstance3D in keep:
		if is_instance_valid(part): part.mesh=keep[part]
	_request_rebuild({})

func _process(delta: float) -> void:
	if not _apply_items.is_empty(): _step_apply()
	elif _task >= 0: _poll_rebuild()
	if _remaining > 0.0: _recoil(delta)
	if _task < 0 and _remaining <= 0.0 and _apply_items.is_empty(): set_process(false)

func _notification(what: int) -> void:
	# O trabalhador só lê dados copiados, mas a tarefa precisa ser recolhida antes de o nó sumir.
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1

func _recoil(delta: float) -> void:
	if not is_instance_valid(vehicle.visual) or vehicle.health<=0: _stop_recoil(); return
	vehicle.visual.rotation-=_last_rotation
	vehicle.visual.position-=_last_position
	_remaining=maxf(0,_remaining-delta)
	var elapsed:=.38-_remaining
	var decay:=exp(-elapsed*10)*sin(elapsed*26)
	_last_rotation=_kick*decay
	_last_position=Vector3(0,absf(decay)*.025,0)
	vehicle.visual.rotation+=_last_rotation
	vehicle.visual.position+=_last_position
	if _remaining<=0: _stop_recoil()

func _stop_recoil() -> void:
	if is_instance_valid(vehicle) and is_instance_valid(vehicle.visual):
		vehicle.visual.rotation-=_last_rotation
		vehicle.visual.position-=_last_position
	_last_rotation=Vector3.ZERO
	_last_position=Vector3.ZERO
	_remaining=0
	# Uma malha ainda sendo calculada mantém o _process (recolhe e aplica no quadro em que ficar pronta).
	set_process(_task >= 0)
