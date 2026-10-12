extends SceneTree
const ACTOR:=preload("res://scripts/Actor.gd")
var world
var folder:="res://evidence/terrenos/2026-10-10-acabamento-acesso"
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print("RURAL_FINISH ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(n: int) -> void:
	for i in n: await physics_frame
func shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder+"/"+label+".png")
func focus(point: Vector3,size: float) -> void:
	world.player.teleport(point+Vector3.UP*.08)
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.camera.target_size=size
	world.camera.initialized=false
	world.production.region.prepare_collision_at(point)
	await frames(120)
func walk(a: Vector3,b: Vector3) -> void:
	world.production.region.prepare_collision_at(a)
	world.production.region.prepare_collision_at(b)
	var actor:=ACTOR.new()
	actor.identity=84501
	world.add_child(actor)
	actor.position=a+Vector3.UP*.08
	actor.controlled_automatically=true
	actor.automatic_direction=(b-a).normalized()
	actor.speed=3.5
	for i in 150:
		await physics_frame
		var toward:=b-actor.position
		toward.y=0
		actor.automatic_direction=toward.normalized()
		if actor.position.distance_to(b)<.7: break
	check(actor.position.distance_to(b)<.8 and absf(actor.position.y)<.3,"travessia física "+str(a)+" → "+str(b)+" final="+str(actor.position))
	actor.queue_free()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	create_timer(180).timeout.connect(func():quit(124))
	DirAccess.make_dir_recursive_absolute(folder)
	root.size=Vector2i(1280,720)
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Main .NET pronta")
	if world.session==null or not world.session.ready_for_play: quit(1); return
	await focus(Vector3(-324,0,30),55)
	check(world.find_child("TemporaryEscapeTestWall",true,false)==null,"sem muro temporário")
	var company: Node3D=world.find_child("Vertice",true,false)
	var roof: Node3D=company.find_child("BoothRoof",true,false)
	check(roof!=null and roof.has_node("BoothRoofDetails"),"telhado marcado detalhado")
	print("ROOF projected=",world.camera.unproject_position(roof.global_position)," world=",roof.global_position)
	await shot("01_visao_geral")
	await focus(Vector3(-326,0,5),24)
	await shot("02_telhado")
	world.player.automatic_direction=Vector3.RIGHT
	world.player.speed=2
	for i in 6:
		await frames(12)
		await shot("telhado_movimento_%02d"%i)
	world.player.automatic_direction=Vector3.ZERO
	await focus(Vector3(-340,0,20),28)
	await shot("03_encontro_superior")
	if "--capture-only" not in OS.get_cmdline_user_args(): await walk(Vector3(-341,0,18),Vector3(-349,0,18))
	await focus(Vector3(-290,0,25),26)
	await shot("04_encontro_inferior")
	# O observador está em (-290,25); caminhe ao lado da sua cápsula.
	if "--capture-only" not in OS.get_cmdline_user_args(): await walk(Vector3(-289,0,23),Vector3(-289,0,31))
	# Duas posições da câmera no mesmo acabamento para conferir continuidade.
	world.player.automatic_direction=Vector3.RIGHT
	world.player.speed=2
	for i in 8:
		await frames(12)
		await shot("movimento_%02d"%i)
	print("RURAL_FINISH failures=",failures)
	world.free()
	quit(0 if failures.is_empty() else 1)
