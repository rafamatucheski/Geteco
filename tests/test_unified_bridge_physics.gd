extends SceneTree
## Fixture construtiva sem sessão/save; física de carro é a DispatchVehicle de produção.
## Pela fila .NET após build: --script res://tests/test_unified_bridge_physics.gd -- --no-save [--drive]
## --drive acrescenta quatro percursos físicos; --drive-route=<id> seleciona um.
## Não mede FPS nem certifica streaming/Main.
const KIT := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const NORTH := preload("res://world/north_gateway/NorthGatewayScenery.gd")
const LAYOUT := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const REGION := preload("res://world/regions/NativeRegion.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const ROAD := preload("res://world/desert/DesertRoadGeometry.gd")
const CAR := preload("res://gameplay/dispatch/DispatchVehicle.gd")
const ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const DRIVE_ROUTES := ["tronco_curva_leste_ida","tronco_curva_leste_volta","norte_ida","norte_volta"]
class Game extends RefCounted:
	var player: Node3D
	var aiming := false
	func pursuit_target() -> Node3D: return player
class World extends Node3D:
	var player: Node3D
	var gameplay := Game.new()
	var production: Node3D
var world: World
var north: NORTH
var checks := 0
var failures: Array[String] = []
var drives: Array[Dictionary] = []
var triangles := {}
var started := 0
var drive_requested := false
var drive_route_filter := ""

func _initialize() -> void:
	create_timer(480).timeout.connect(func(): check(false,"limite global de 480 s"); finish(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("UNIFIED_BRIDGE_PHYSICS ","PASS " if ok else "FAIL ",label)

func run() -> void:
	started = Time.get_ticks_msec()
	if "--no-save" not in OS.get_cmdline_user_args() or not KIT.enabled():
		check(false,"exige --no-save e gerador unificado habilitado")
		finish(2)
		return
	var filter_seen := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--drive": drive_requested = true
		elif argument == "--drive-route":
			check(false,"--drive-route exige =<id>: "+str(DRIVE_ROUTES))
			finish(2)
			return
		elif argument.begins_with("--drive-route="):
			if filter_seen:
				check(false,"informe --drive-route somente uma vez")
				finish(2)
				return
			filter_seen = true
			drive_route_filter = argument.trim_prefix("--drive-route=")
			if drive_route_filter not in DRIVE_ROUTES:
				check(false,"percurso inválido: "+drive_route_filter+"; permitidos: "+str(DRIVE_ROUTES))
				finish(2)
				return
			drive_requested = true
	NORTH.prewarm_geometry()
	world = World.new()
	root.add_child(world)
	current_scene = world
	world.player = Node3D.new()
	world.add_child(world.player)
	world.player.position = Vector3(1000,10,1000)
	world.gameplay.player = world.player
	# Os dois donos regionais ficam residentes juntos, como na fronteira real.
	for id in ["harbor","mountain"]:
		var region: Node3D = REGION.build_region(id,Vector3(490,0,-285))
		world.add_child(region)
		for x in [394,420,450,480,512,544,576,608,640]:
			region.prepare_collision_at(Vector3(x,0,-285))
		for section in KIT.east_sections():
			region.prepare_collision_at(section.point)
		for d in [0.0,8.0,16.0,24.0,32.0]:
			region.prepare_collision_at(LAYOUT.sample(d))
		if id=="harbor": check_old_coast_boundaries(region)
	var connection := CONNECTION.new()
	world.add_child(connection)
	north = NORTH.new()
	world.add_child(north)
	north.build(false)
	check_cached_geometry()
	var road := ROAD.new()
	road.configure(DESERT.roads())
	road.build_chunk(world,Rect2(320,-448,48,74.5))
	for frame in 5: await physics_frame
	check_closed()
	north.set_completed(true)
	for frame in 3: await physics_frame
	index_asphalt()
	check_east()
	check_trunk_and_curve()
	check_north()
	# Restaurar diretamente o mesmo estado construtivo não pode duplicar malhas.
	var count := north.find_children("*","MeshInstance3D",true,false).size()
	north.set_completed(true)
	check(north.find_children("*","MeshInstance3D",true,false).size()==count,"reaplicar estado concluído não duplica malhas")
	north.set_completed(false)
	for frame in 3: await physics_frame
	check_closed()
	north.set_completed(true)
	for frame in 3: await physics_frame
	if drive_requested:
		await drive_all()
		check(drives.size()==(1 if not drive_route_filter.is_empty() else DRIVE_ROUTES.size()),"todos os percursos solicitados foram executados")
	finish(0 if failures.is_empty() else 1)

func ray(a: Vector3, b: Vector3, exclude: Array[RID] = []) -> Dictionary:
	return world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1,exclude))

func floor_hit(point: Vector3) -> Dictionary:
	return ray(point+Vector3.UP*.45,point-Vector3.UP*.30)

func check_cached_geometry() -> void:
	# Instância fora da árvore: compara recursos compartilhados sem adicionar
	# nenhum colisor ao cenário da passagem física.
	var rebuilt: NORTH = NORTH.new()
	rebuilt.build(true)
	var originals: Array[Node] = north.find_children("*","MeshInstance3D",true,false)
	var reused := not originals.is_empty()
	for original: MeshInstance3D in originals:
		var path: NodePath = north.get_path_to(original)
		var copy: MeshInstance3D = rebuilt.get_node_or_null(path)
		reused = reused and copy!=null and copy.mesh==original.mesh
	check(reused,"remontagem usa as mesmas malhas preparadas, sem reconstrução procedural")
	var shared_shapes := true
	for original: CollisionShape3D in north.find_children("*","CollisionShape3D",true,false):
		var copy: CollisionShape3D = rebuilt.get_node_or_null(north.get_path_to(original))
		shared_shapes = shared_shapes and copy!=null and copy.shape==original.shape
	check(shared_shapes,"remontagem compartilha formas físicas sem reconstruir recursos")
	var materials: Array = NORTH.geometry_materials()
	var covered := not materials.is_empty()
	for original: GeometryInstance3D in north.find_children("*","GeometryInstance3D",true,false):
		if original.material_override!=null: covered = covered and materials.has(original.material_override)
	check(covered,"pré-aquecimento enumera materiais reais da ponte e dos MultiMeshes do canteiro")
	check(rebuilt._common.get_script()==null and rebuilt._finished.get_script()==null and rebuilt._works.get_script()==null,"template conserva somente os três grupos geométricos sem controladores")
	check(rebuilt.completed and rebuilt._finished.visible and not rebuilt._works.visible,"nova montagem seleciona estado concluído independentemente da instância anterior")
	rebuilt.free()

func check_old_coast_boundaries(region: Node3D) -> void:
	var inside := []
	var coast: RefCounted = region.get("coastal_protection")
	check(coast!=null,"região real tem proteção costeira configurada")
	if coast==null: return
	for border in coast.boundaries:
		for weight in [.25,.5,.75]:
			var point: Vector2 = (border.a as Vector2).lerp(border.b,weight)
			if KIT.owns_surface_point(point): inside.append(str(point))
	check(inside.is_empty(),"nenhuma aresta de parede costeira antiga dentro do território reconstruído: "+str(inside))

func check_closed() -> void:
	check(north._common.visible and north._works.visible and not north._finished.visible,"estado em obra mantém trecho permanente/canteiro e oculta vão concluído")
	check_group_collision(north._works,true,"canteiro em obra")
	check_group_collision(north._finished,false,"vão desabilitado")
	var gate := LAYOUT.WORK_POSITION
	check(not ray(gate+Vector3(0,.8,3),gate+Vector3(0,.8,-3)).is_empty(),"obra bloqueia fisicamente antes da conclusão")
	for z in [-311.1,-315.7,-321.1]:
		check(floor_hit(Vector3(342.5,2.4,z)).is_empty(),"vão sem piso transitável enquanto obra: z="+str(z))
	check(ray(Vector3(410,.8,-282.8),Vector3(444,.8,-282.8)).is_empty(),"bloqueio norte preserva saída leste independente")

func check_group_collision(group: Node3D, enabled: bool, label: String) -> void:
	var bodies: Array[Node] = group.find_children("*","StaticBody3D",true,false)
	var consistent: bool = not bodies.is_empty()
	for body: StaticBody3D in bodies:
		consistent = consistent and body.collision_layer==(1 if enabled else 0)
	check(consistent,label+": todos os corpos seguem o estado de colisão do grupo")

func check_east() -> void:
	var support := true
	var walks := true
	var guards := true
	var unique := true
	var visual := true
	for i in 59:
		var x := 394.137+float(i)*4.0
		var point := Vector3(x,0,-282.781)
		var hit := floor_hit(point)
		support = support and not hit.is_empty() and absf(float(hit.get("position",Vector3.INF).y))<.055
		var layers := asphalt_layers(point)
		unique = unique and layers.size()==1
		visual = visual and layers.size()>0
		if layers.size()!=1: print("UNIFIED_ASPHALT_LAYERS ",point," ",layers)
		# Portal/túnel têm suas paredes; aqui verificamos o tabuleiro aberto.
		if x<CONNECTION.TUNNEL_START_X-2:
			for sign_value in [-1.0,1.0]:
				var p := Vector3(x,.07,-285+sign_value*(KIT.east_deck_half_width(x)-.85))
				var h := floor_hit(p)
				walks = walks and not h.is_empty() and absf(float(h.get("position",Vector3.INF).y)-.07)<.03
				var start := Vector3(x,.95,-285+sign_value*(KIT.east_deck_half_width(x)-1.0))
				guards = guards and not ray(start,start+Vector3(0,0,sign_value*2.0)).is_empty()
	check(support,"leste: piso físico contínuo do conector até saída do túnel")
	check(walks,"leste: calçadas físicas no perfil de 7 cm")
	check(guards,"leste: guardas físicas contêm as duas margens")
	check(visual,"leste: asfalto visual cobre corredor amostrado")
	check(unique,"leste: exatamente uma camada de triângulos de asfalto por amostra, com regiões juntas")

func floor_layers(point: Vector3) -> Array:
	var found := []
	var excluded: Array[RID] = []
	for index in 10:
		var hit := ray(point+Vector3.UP*.22,point-Vector3.UP*.22,excluded)
		if hit.is_empty(): break
		excluded.append(hit.rid)
		if hit.normal.y>.7: found.append({"path":str(hit.collider.get_path()),"height":float(hit.position.y)})
	return found

func check_trunk_and_curve() -> void:
	var support := true
	var sidewalks := true
	var guards := true
	var visual_unique := true
	var floor_unique := true
	var old_coast := false
	var sections: Array = KIT.east_sections()
	for i in range(sections.size()-1):
		var a: Dictionary = sections[i]
		var b: Dictionary = sections[i+1]
		var p: Vector3 = (a.point as Vector3).lerp(b.point,.371)
		if p.x>405.0: continue
		var side: Vector3 = (a.side as Vector3).lerp(b.side,.371).normalized()
		var width: float = lerpf(float(a.deck),float(b.deck),.371)
		for lane in [-7.137,2.219,7.137]:
			var point: Vector3 = p+side*lane
			var hit := floor_hit(point)
			support = support and not hit.is_empty() and absf(float(hit.get("position",Vector3.INF).y))<.04
			var layers := floor_layers(point)
			floor_unique = floor_unique and layers.size()==1
			for layer in layers: old_coast=old_coast or str(layer.path).contains("CoastalWalkSupport")
			var visible := asphalt_layers(point)
			visual_unique = visual_unique and visible.size()==1
			if layers.size()!=1 or visible.size()!=1: print("UNIFIED_TRUNK_LAYERS ",point," physical=",layers," visual=",visible)
		for sign_value in [-1.0,1.0]:
			var point: Vector3 = p+side*sign_value*(width-.85)
			var hit := floor_hit(point)
			# A boca oeste é rebaixada para receber o braço norte sem meio-fio.
			var mouth_limits := KIT.east_mouth_limits()
			var mouth: bool = p.x<390 and p.z>=mouth_limits.x and p.z<=mouth_limits.y
			var west: bool = sign_value<0 and p.x<390
			var expected: float = .07
			if is_equal_approx(p.x,375.0):
				expected *= smoothstep(133.0,135.0,-p.z)
				if west: expected *= smoothstep(0,2,maxf(p.z-mouth_limits.y,mouth_limits.x-p.z))
			sidewalks=sidewalks and not hit.is_empty() and absf(float(hit.get("position",Vector3.INF).y)-expected)<.035
			if is_equal_approx(p.x,375.0) and p.z> -136.0: continue
			if mouth and west: continue
			var start: Vector3 = p+side*sign_value*(width-1.0)+Vector3.UP*.95
			var guard := ray(start,start+side*sign_value*2.0)
			guards=guards and not guard.is_empty()
			if not guard.is_empty(): old_coast=old_coast or str(guard.collider.get_path()).contains("CoastalBarrierSolid")
	check(support,"tronco/curvas: piso físico contínuo em três faixas amostradas")
	check(floor_unique,"tronco/curvas: uma camada de piso físico por amostra")
	check(visual_unique,"tronco/curvas: uma camada visual de asfalto por amostra")
	check(sidewalks,"tronco/curvas: calçadas físicas contínuas e boca norte rebaixada")
	check(guards,"tronco/curvas: contenções físicas dos dois lados fora da boca norte")
	check(not old_coast,"tronco/curvas: suporte e guardas antigos da costa removidos do território novo")

func check_north() -> void:
	var support := true
	var walks := true
	var guards := true
	var unique := true
	var unique_floor := true
	check(north._common.visible and north._finished.visible and not north._works.visible,"estado concluído mantém ponte permanente/vão e remove apresentação da obra")
	check_group_collision(north._works,false,"canteiro concluído")
	check_group_collision(north._finished,true,"vão concluído")
	for i in range(1,ceili(LAYOUT.length()/2.0)):
		var d := minf(float(i)*2.0+.137,LAYOUT.length()-.2)
		var p: Vector3 = LAYOUT.sample(d)
		var direction: Vector3 = LAYOUT.sample(minf(d+.2,LAYOUT.length()))-LAYOUT.sample(maxf(d-.2,0.0))
		var side: Vector3 = Vector3(-direction.z,0,direction.x).normalized()
		var h := floor_hit(p)
		support = support and not h.is_empty() and absf(float(h.get("position",Vector3.INF).y)-p.y)<.055
		# Amostra afastada das diagonais de triangulação da pista.
		var layers := asphalt_layers(p+side*.219)
		var physical_layers: Array = floor_layers(p+side*.219)
		unique_floor = unique_floor and physical_layers.size()==1
		if physical_layers.size()!=1: print("UNIFIED_NORTH_FLOOR_LAYERS ",p," ",physical_layers)
		unique = unique and layers.size()==1
		if layers.size()!=1: print("UNIFIED_ASPHALT_LAYERS ",p," ",layers)
		for sign_value in [-1.0,1.0]:
			var width := LAYOUT.deck_half_width(p)
			var walk: Vector3 = p+side*sign_value*(width-.8)
			var expected_walk: float = 0.0 if KIT.owns_east_point(Vector2(walk.x,walk.z)) else LAYOUT.walk_height_at(d)
			walk.y += expected_walk
			h = floor_hit(walk)
			walks = walks and not h.is_empty() and absf(float(h.get("position",Vector3.INF).y)-walk.y)<.04
			if d>4.0:
				var start: Vector3 = p+side*sign_value*(width-1.0)+Vector3.UP*.95
				guards = guards and not ray(start,start+side*sign_value*2.0).is_empty()
	check(support,"norte: piso físico contínuo, incluindo curva e vão de 13 m")
	check(walks,"norte: calçadas físicas contínuas dos dois lados")
	check(guards,"norte: guardas físicas contínuas após boca de acesso")
	check(unique,"norte: exatamente uma camada visual de asfalto por amostra")
	check(unique_floor,"norte: exatamente um corpo de piso por amostra, incluindo desembocadura compartilhada")
	var mouth_asphalt_unique := true
	var mouth_floor_unique := true
	for distance in [.1,.5,1.0,1.5,2.0,2.5,3.0,3.5,4.0]:
		var point: Vector3 = LAYOUT.sample(distance)
		var tangent: Vector3 = LAYOUT.sample(distance+.1)-LAYOUT.sample(maxf(0,distance-.1))
		var lateral: Vector3 = Vector3(-tangent.z,0,tangent.x).normalized()
		for offset in [-2.137,.219,2.137]:
			var at: Vector3 = point+lateral*offset
			var asphalt: Array = asphalt_layers(at)
			var floor: Array = floor_layers(at)
			mouth_asphalt_unique = mouth_asphalt_unique and asphalt.size()==1
			mouth_floor_unique = mouth_floor_unique and floor.size()==1
			if asphalt.size()!=1 or floor.size()!=1: print("UNIFIED_NORTH_MOUTH_LAYERS ",at," asphalt=",asphalt," floor=",floor)
	check(mouth_asphalt_unique,"desembocadura norte: asfalto contínuo e único nos 4 m iniciais em três linhas")
	check(mouth_floor_unique,"desembocadura norte: piso físico único nas três linhas de travessia da antiga calçada")
	check(is_zero_approx(LAYOUT.sample(0).y),"boca norte nasce no piso físico zero da rua urbana")
	for endpoint in [0.0,.5,1.0,LAYOUT.length()-1.0,LAYOUT.length()-.5,LAYOUT.length()]:
		var p: Vector3 = LAYOUT.sample(endpoint)
		var next: Vector3 = LAYOUT.sample(minf(endpoint+.1,LAYOUT.length()))
		var previous: Vector3 = LAYOUT.sample(maxf(endpoint-.1,0))
		var delta: Vector3 = next-previous
		var side: Vector3 = Vector3(-delta.z,0,delta.x).normalized()
		# Evitar a própria borda exata do colisor na amostra dos dois extremos.
		var inset := clampf(endpoint,.01,LAYOUT.length()-.01)
		p = LAYOUT.sample(inset)
		var walk: Vector3 = p+side*(LAYOUT.deck_half_width(p)-.8)
		walk.y += 0.0 if KIT.owns_east_point(Vector2(walk.x,walk.z)) else LAYOUT.walk_height_at(inset)
		var hit := floor_hit(walk)
		check(not hit.is_empty() and absf(float(hit.get("position",Vector3.INF).y)-walk.y)<.025,"calçada concorda com piso regional no extremo d="+str(endpoint))
	var gate := LAYOUT.WORK_POSITION
	check(ray(gate+Vector3(0,.8,3),gate+Vector3(0,.8,-3)).is_empty(),"conclusão remove colisão da barreira da obra")
	for z in [-373.31,-373.51,-374.1,-377.3]:
		var p := Vector3(344.137,DESERT.surface_height(Vector2(344.137,z)),z)
		check(not floor_hit(p).is_empty(),"emenda Route 66 tem suporte físico: z="+str(z))

func is_asphalt(mesh: MeshInstance3D, surface: int) -> bool:
	var material := mesh.get_active_material(surface)
	if material==KIT.material("asphalt"): return true
	if str(mesh.name).to_lower().contains("asphalt"): return true
	return material is ShaderMaterial and material.shader.resource_path.ends_with("desert_surface.gdshader") and material.get_shader_parameter("asphalt")==true

func index_asphalt() -> void:
	triangles.clear()
	for mesh: MeshInstance3D in world.find_children("*","MeshInstance3D",true,false):
		if not mesh.is_visible_in_tree() or mesh.mesh==null: continue
		var box: AABB = mesh.global_transform*mesh.get_aabb()
		if box.position.x>650 or box.end.x<320 or box.position.z> -115 or box.end.z< -450: continue
		for surface in mesh.mesh.get_surface_count():
			if not is_asphalt(mesh,surface): continue
			var arrays := ARRAYS.arrays_of(mesh.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if indices!=null and indices.size()>0 else vertices.size()
			for i in range(0,count,3):
				var points := PackedVector3Array()
				for k in 3:
					var index: int = indices[i+k] if indices!=null and indices.size()>0 else i+k
					points.append(mesh.global_transform*vertices[index])
				if absf((points[1]-points[0]).cross(points[2]-points[0]).normalized().y)<.7: continue
				var bounds := Rect2(Vector2(points[0].x,points[0].z),Vector2.ZERO)
				for p in points: bounds=bounds.expand(Vector2(p.x,p.z))
				var item := {"points":points,"path":str(mesh.get_path())}
				for x in range(floori(bounds.position.x/8),floori(bounds.end.x/8)+1):
					for z in range(floori(bounds.position.y/8),floori(bounds.end.y/8)+1):
						var cell := Vector2i(x,z)
						if not triangles.has(cell): triangles[cell]=[]
						triangles[cell].append(item)

func asphalt_layers(point: Vector3) -> Array:
	var hits := []
	var p := Vector2(point.x,point.z)
	for item in triangles.get(Vector2i(floori(p.x/8),floori(p.y/8)),[]):
		var v: PackedVector3Array = item.points
		var a := Vector2(v[0].x,v[0].z)
		var b := Vector2(v[1].x,v[1].z)
		var c := Vector2(v[2].x,v[2].z)
		var denominator := (b-a).cross(c-a)
		if absf(denominator)<.000001: continue
		var u := (p-a).cross(c-a)/denominator
		var w := (b-a).cross(p-a)/denominator
		if u<.00001 or w<.00001 or u+w> .99999: continue
		var height := v[0].y+(v[1].y-v[0].y)*u+(v[2].y-v[0].y)*w
		if absf(height-point.y)<.15: hits.append({"path":item.path,"height":height})
	return hits

func drive_all() -> void:
	# Northbank Gateway Avenue e horizontal em z=-125, com7.5m de largura.
	# Prolongar o tronco ate z=-120 apontava para passeio/poste legitimo; a
	# fixture deve fazer a conversao pela avenida, preservando esses obstaculos.
	var east := PackedVector3Array([Vector3(372.5,0,-125),Vector3(376.5,0,-125)])
	var arc_steps := ceili(6.0*PI*.5)
	for i in range(1,arc_steps+1):
		var angle := lerpf(PI*.5,0.0,float(i)/arc_steps)
		east.append(Vector3(376.5+cos(angle)*6.0,0,-131.0+sin(angle)*6.0))
	var sections: Array = KIT.east_sections()
	for section in sections:
		var point: Vector3 = section.point
		if point.z>=-131.0: continue
		var side: Vector3 = section.side
		var lane := lerpf(7.5,2.2,clampf((point.x-405.0)/(468.25-405.0),0,1))
		east.append(point+side*lane)
	east.append(Vector3(644,0,-282.8))
	await drive("tronco_curva_leste_ida",east)
	east.reverse()
	await drive("tronco_curva_leste_volta",east)
	var path := PackedVector3Array()
	var direction: Vector3 = LAYOUT.sample(.2)-LAYOUT.sample(0)
	direction.y=0
	direction=direction.normalized()
	# O carro entra vindo da rua existente, incluindo o encontro que antes tinha 3,2 cm.
	path.append(LAYOUT.APPROACH-direction*5.0)
	path.append(LAYOUT.APPROACH-direction*2.0)
	path.append(LAYOUT.sample(0))
	for i in range(1,ceili(LAYOUT.length()/2.0)):
		path.append(LAYOUT.sample(float(i)*2.0))
	for z in range(-374,-402,-2): path.append(Vector3(342.5,DESERT.surface_height(Vector2(342.5,z)),z))
	await drive("norte_ida",path)
	path.reverse()
	await drive("norte_volta",path)

func drive(label: String, path: PackedVector3Array) -> void:
	if not drive_route_filter.is_empty() and label != drive_route_filter: return
	var car: CAR = CAR.new()
	car.archetype = "winter_suv_heavy"
	car.position = path[0]+Vector3.UP*.06
	var initial: Vector3 = path[1]-path[0]
	car.rotation.y = atan2(-initial.x,-initial.z)
	world.add_child(car)
	car.set_external_driver(true)
	for frame in 5: await physics_frame
	var waypoint := 1
	var began := Time.get_ticks_msec()
	var route_length := 0.0
	for i in range(1,path.size()): route_length+=path[i-1].distance_to(path[i])
	# A rota passou a incluir o tronco inteiro; prazo acompanha sua extensão a 4 m/s.
	var deadline_msec := int((route_length/4.0+20.0)*1000.0)
	var supported := true
	var contacts: Array = []
	var max_error := 0.0
	while Time.get_ticks_msec()-began<deadline_msec and waypoint<path.size():
		var target: Vector3 = path[waypoint]
		var offset: Vector3 = target-car.global_position
		offset.y=0
		if offset.length()<2.1:
			waypoint+=1
			continue
		var wanted: float = atan2(-offset.x,-offset.z)
		var angle: float = angle_difference(car.rotation.y,wanted)
		car.steer_input=clampf(angle*2.8,-1.0,1.0)
		car.throttle_input=.35 if car.speed<5.0 else 0.0
		car.brake_input=car.speed>6.0
		await physics_frame
		var a: Vector3 = path[maxi(0,waypoint-1)]
		var b: Vector3 = path[waypoint]
		var closest := Geometry2D.get_closest_point_to_segment(Vector2(car.position.x,car.position.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
		max_error=maxf(max_error,closest.distance_to(Vector2(car.position.x,car.position.z)))
		var query := ray(car.position+Vector3.UP*.5,car.position-Vector3.UP*.8,[car.get_rid()])
		supported=supported and not query.is_empty()
		for index in car.get_slide_collision_count():
			var hit: KinematicCollision3D = car.get_slide_collision(index)
			if absf(hit.get_normal().y)<.3 and contacts.size()<8:
				contacts.append({"body":str(hit.get_collider().get_path()),"point":str(hit.get_position()),"normal":str(hit.get_normal())})
		if car.position.y< -1 or max_error>4.0: break
	var reached := waypoint==path.size()
	check(reached,label+": carro real percorre rota inteira sob throttle e steering")
	check(supported,label+": suporte físico permanece sob carro durante percurso")
	check(contacts.is_empty(),label+": nenhuma colisão frontal/lateral inesperada na rota")
	check(car.health==car.max_health,label+": travessia em baixa velocidade não danifica veículo")
	drives.append({"id":label,"reached":reached,"supported":supported,"max_lateral_error":max_error,"last_waypoint":waypoint,"waypoints":path.size(),"position":str(car.position),"seconds":float(Time.get_ticks_msec()-began)/1000.0,"contacts":contacts})
	print("UNIFIED_BRIDGE_DRIVE_RESULT ",JSON.stringify(drives[-1]))
	car.free()
	await physics_frame

func finish(code: int) -> void:
	print("UNIFIED_BRIDGE_PHYSICS_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"drive_requested":drive_requested,"drive_route_filter":drive_route_filter,"drives":drives,"elapsed_seconds":float(Time.get_ticks_msec()-started)/1000.0,"scope":"Geometria e física reais em fixture isolada. Campanha/save/Main/streaming/performance exigem testes complementares."}))
	if is_instance_valid(world): world.free()
	quit(code)
