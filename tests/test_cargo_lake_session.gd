extends "res://tests/measure/measure_cargo_lake.gd"
## Encontros, acesso e propriedade do cenário na sessão renderizada real.
var checks:=0
var failures: Array[String]=[]
var lake: Node3D
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func frames(count: int) -> void:
	for i in count: await physics_frame
func walk(point: Vector3) -> bool:
	var target_point:=plane.to_global(point)
	var began:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<13000:
		var direction: Vector3=target_point-world.player.global_position
		direction.y=0
		if direction.length()<.15:
			world.player.automatic_direction=Vector3.ZERO
			await frames(3)
			return world.player.is_on_floor()
		world.player.automatic_direction=direction.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	print("CARGO_LAKE_BLOCKED ",plane.to_local(world.player.global_position)," target=",point)
	return false
func run() -> void:
	await super.run()
	started=0
	if not is_instance_valid(plane): return
	for item in get_nodes_in_group("native_water_surface"):
		if item.variant=="secret": lake=item; break
	check(lake!=null,"lago secreto original carregado")
	if lake==null: quit(1); return
	check(world.production.no_save,"save pessoal preservado")
	var dry_before: Array=lake.dry_polygons.duplicate(true)
	var water_before: PackedVector2Array=lake.water_polygon.duplicate()
	# Rota de comparação também precisa ser transitável, além de medir FPS.
	world.player.speed=3
	for local in [Vector3(16,0,14.5),Vector3(14,0,7.5),Vector3(7.1,0,10.5),Vector3(0,0,10.5),Vector3(-4,0,14),Vector3(9,0,18.5)]:
		check(await walk(local),"apoio/caminhada no encontro "+str(local))
	check(await walk(Vector3(0,0,10.5)),"aproximação alinhada à rampa do avião")
	check(await walk(Vector3(0,0,3.5)),"entrada do avião preservada")
	check(await walk(Vector3(.2,0,-5.5)),"carga acessível após entorno")
	check(await walk(Vector3(0,0,10.5)),"saída pela rampa preservada")
	check(lake.water_polygon==water_before and lake.dry_polygons==dry_before,"percorrer o trecho não modifica domínios")
	check(not lake.contains_water(plane.to_global(Vector3(0,0,-5))),"convés mantém classificação seca")
	check(lake.contains_water(lake.to_global(Vector3(-5,0,0))),"água aberta mantém classificação molhada")
	check(not lake.contains_water(lake.to_global(Vector3(12.8,0,10))),"acampamento mantém classificação seca")
	# Apoio físico nos terrenos secos; independente dos nomes das novas malhas.
	for at in [Vector2(11.3,8),Vector2(11,14),Vector2(15.3,-4.1),Vector2(-20.2,0),Vector2(18.8,1)]:
		var global_at:=lake.to_global(Vector3(at.x,0,at.y))
		var query:=PhysicsRayQueryParameters3D.create(global_at+Vector3.UP*4,global_at-Vector3.UP*2,1)
		var hit:=lake.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(),"margem/apoio físico presente "+str(at))
		if not hit.is_empty(): check(hit.normal.y>.6,"apoio sem parede/pico artificial "+str(at))
	for at in [Vector2(45,105)/16.0,Vector2(58,75)/16.0,Vector2(65,50)/16.0]:
		var base:=lake.to_global(Vector3(at.x,0,at.y))
		var support:=lake.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(base+Vector3.UP,base-Vector3.UP,1))
		check(not support.is_empty() and support.position.y-lake.global_position.y>.08 and support.position.y-lake.global_position.y<.16,"pedra de passagem com apoio correspondente "+str(at))
		check(not lake.contains_water(base),"pedra mantém domínio seco "+str(at))
	world.player.teleport(plane.to_global(Vector3(6.3,.15,-1)))
	world.camera.target_size=40; world.camera.heading=PI*.5; world.camera.initialized=false
	await frames(45)
	await photograph("lake-overview")
	world.player.teleport(plane.to_global(Vector3(11,.2,14)))
	world.camera.target_size=20; world.camera.heading=0; world.camera.initialized=false
	await frames(45)
	await photograph("camp-detail")
	var visitor=preload("res://scripts/Actor.gd").new()
	visitor.identity=949; visitor.controlled_automatically=true; visitor.speed=3
	world.add_child(visitor)
	visitor.teleport(lake.to_global(Vector3(11,.2,14)))
	await frames(20)
	check(visitor.is_on_floor(),"NPC visitante apoiado no acampamento")
	visitor.automatic_direction=Vector3.FORWARD
	var visitor_began:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-visitor_began<6000 and lake.to_local(visitor.global_position).z>8.1: await physics_frame
	visitor.automatic_direction=Vector3.ZERO
	check(lake.to_local(visitor.global_position).z<8.2 and visitor.is_on_floor(),"NPC atravessa o piso do acampamento livre")
	visitor.queue_free(); await frames(3)
	var cached_lake: WeakRef=weakref(lake)
	var child_count:=lake.get_child_count()
	var away: Vector3=plane.global_position+Vector3(220,0,0)
	away.y=world.production.region.terrain.surface_height_at(Vector2(away.x,away.z))+.15
	var return_at: Vector3=plane.global_position+Vector3(9,.15,18.5)
	world.player.teleport(away)
	await frames(240)
	check(is_instance_valid(cached_lake.get_ref()) and lake.get_parent()==null,"streaming guarda lago fora da árvore sem processar")
	world.player.teleport(return_at)
	await frames(240)
	check(is_instance_valid(cached_lake.get_ref()) and lake.is_inside_tree(),"retorno reutiliza lago original")
	check(lake.get_child_count()==child_count,"retorno não duplica geometria, props ou colisores")
	check(lake.water_polygon==water_before and lake.dry_polygons==dry_before,"retorno preserva contornos/classificação")
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CARGO_LAKE_SESSION ","PASS" if failures.is_empty() else "FAIL"," ",folder," checks=",checks," failures=",failures)
	world.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)
func _process(_delta: float) -> bool: return false
