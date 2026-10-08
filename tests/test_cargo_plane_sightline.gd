extends "res://tests/measure/measure_cargo_plane.gd"
## Câmera, física e circulação do avião no Main .NET renderizado.
var checks := 0
var failures: Array[String] = []
var depth: Array = []

func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func walk(local: Vector3) -> bool:
	var goal := plane.to_global(local)
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<12000:
		var direction: Vector3=goal-world.player.global_position
		direction.y=0
		if direction.length()<.12:
			world.player.automatic_direction=Vector3.ZERO
			await frames(3)
			return world.player.is_on_floor()
		world.player.automatic_direction=direction.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	print("PLANE_WALK_BLOCKED ",plane.to_local(world.player.global_position)," goal=",local)
	return false

func magenta_count(img: Image) -> int:
	img.convert(Image.FORMAT_RGBA8)
	var bytes := img.get_data()
	var count := 0
	for i in range(0,bytes.size(),4):
		if bytes[i]>150 and bytes[i+2]>150 and bytes[i+1]<85: count+=1
	return count

func player_visibility(id: String, heading: float) -> void:
	world.camera.heading=heading; world.camera.initialized=false
	await frames(35)
	await RenderingServer.frame_post_draw
	var actual := root.get_texture().get_image()
	plane.model.hide()
	await frames(3)
	await RenderingServer.frame_post_draw
	var control := root.get_texture().get_image()
	plane.model.show()
	var actor: Node3D=world.camera.target
	actor.visual.hide()
	await frames(3)
	await RenderingServer.frame_post_draw
	var negative := root.get_texture().get_image()
	actor.visual.show()
	var background := magenta_count(negative)
	var seen := maxi(0,magenta_count(actual)-background)
	var unobstructed := maxi(0,magenta_count(control)-background)
	depth.append({"id":id,"visible":seen,"control":unobstructed,"background":background})
	check(unobstructed>80,id+": controle positivo do ator renderizado")
	check(seen>80 and seen>=unobstructed*.60,id+": Dante visível no corredor com cutaway")
	actual.save_png(folder.path_join("depth-"+id+".png"))
	control.save_png(folder.path_join("control-"+id+".png"))
	negative.save_png(folder.path_join("negative-"+id+".png"))

func run() -> void:
	await super.run()
	started=0
	if not is_instance_valid(plane): return
	check(world.production.no_save,"sessão isolada não sobrescreve saves pessoais")
	check(plane.reward_points.size()==2,"dinheiro e SMG preservados")
	world.player.speed=3
	check(await walk(Vector3(.2,0,3.5)),"entrada caminhando pela rampa")
	check(await walk(Vector3(.2,0,-5.5)),"corredor de carga livre")
	check(await walk(Vector3(-.25,0,-6.4)),"desvio do baú acessível")
	check(await walk(Vector3(-.25,0,-8.0)),"passagem junto aos coletáveis")
	check(await walk(Vector3(0,0,-10.4)),"rampa física até cockpit")
	check(await walk(Vector3(0,0,-12.1)),"circulação entre assentos do cockpit")
	check(await walk(Vector3(0,0,-8.0)),"retorno pelo degrau do cockpit")
	check(await walk(Vector3(.2,0,-5.5)),"retorno à carga sem atravessar baú")
	world.player.automatic_direction=Vector3.ZERO
	await frames(8)
	world.camera.locked=true
	await frames(3)
	check(plane.model.cutaway_roof.visible and plane.model.port_shell.visible and plane.model.starboard_shell.visible,"câmera de transição restaura recorte exterior")
	world.camera.locked=false
	world.camera.target=null
	await frames(3)
	check(plane.model.cutaway_roof.visible,"sem alvo não conserva avião aberto")
	world.camera.target=world.player
	world.camera.initialized=false
	await frames(3)
	check(not plane.model.cutaway_roof.visible,"retomar alvo reabre a área ocupada")
	var current_at: Vector3=world.player.global_position
	var previous_physics: bool=world.player.is_physics_processing()
	var previous_process: bool=world.player.is_processing()
	world.player.set_physics_process(false)
	world.player.set_process(false)
	world.player.animation.pause()
	# Varredura contra paredes: recortar o visual conserva bloqueio físico.
	for side in [-1.0,1.0]:
		world.player.teleport(plane.to_global(Vector3(0,.24,-.8)))
		await frames(2)
		var collision: KinematicCollision3D=world.player.move_and_collide(Vector3(side*4,0,0),true)
		var wall: Node=collision.get_collider() if collision!=null else null
		check(wall!=null and wall.get_parent()==plane and wall.get_meta("plane_solid_id","")=="FuselageWall" and collision.get_normal().dot(Vector3(-side,0,0))>.99,"parede lateral permanece sólida "+str(side))
	world.player.teleport(current_at)
	await frames(3)
	var diagnostic := StandardMaterial3D.new()
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	diagnostic.albedo_color=Color(1,0,1)
	var original: Array=[]
	for mesh in world.player.visual.find_children("*","MeshInstance3D",true,false):
		original.append([mesh,mesh.material_override]); mesh.material_override=diagnostic
	for angle in 8:
		await player_visibility("cargo-%d"%angle,angle*PI*.25)
	world.player.teleport(plane.to_global(Vector3(0,.68,-10.4)))
	await frames(3)
	for angle in 4:
		await player_visibility("cockpit-%d"%angle,angle*PI*.5)
	for entry in original: entry[0].material_override=entry[1]
	# Visitante real compartilha o piso, sólidos e profundidade de Dante.
	var visitor=preload("res://scripts/Actor.gd").new()
	visitor.identity=919
	visitor.controlled_automatically=true
	world.add_child(visitor)
	visitor.teleport(plane.to_global(Vector3(0,.24,-.8)))
	await frames(10)
	check(visitor.is_on_floor(),"NPC visitante apoiado no piso do avião")
	visitor.set_physics_process(false)
	visitor.set_process(false)
	if visitor.animation!=null: visitor.animation.pause()
	for side in [-1.0,1.0]:
		var impact: KinematicCollision3D=visitor.move_and_collide(Vector3(side*4,0,0),true)
		var wall: Node=impact.get_collider() if impact!=null else null
		check(wall!=null and wall.get_parent()==plane and wall.get_meta("plane_solid_id","")=="FuselageWall" and impact.get_normal().dot(Vector3(-side,0,0))>.99,"NPC também bloqueado pela lateral "+str(side))
	visitor.teleport(plane.to_global(Vector3(.2,.24,-5.5)))
	world.player.hide()
	world.camera.target=visitor
	for mesh in visitor.visual.find_children("*","MeshInstance3D",true,false): mesh.material_override=diagnostic
	await player_visibility("visitor-port",-PI*.5)
	await player_visibility("visitor-starboard",PI*.5)
	world.camera.target=world.player
	world.player.show()
	visitor.queue_free()
	await frames(3)
	world.player.set_physics_process(previous_physics)
	world.player.set_process(previous_process)
	world.player.teleport(current_at)
	check(await walk(Vector3(.2,0,10.5)),"saída caminhando pela mesma rampa")
	check(await walk(Vector3(.2,0,14.0)),"retorno ao lago sem perder controle")
	await frames(4)
	check(plane.model.cutaway_roof.visible,"teto restaurado longe do acesso")
	check(plane.model.port_shell.visible and plane.model.starboard_shell.visible,"laterais restauradas após saída")
	await photograph("exterior-closed")
	check(await walk(Vector3(.2,0,8)),"reentrada abre corredor novamente")
	await frames(4)
	check(not plane.model.cutaway_roof.visible,"teto aberto na reentrada")
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"depth":depth},"\t"))
	print("CARGO_PLANE_SIGHTLINE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	world.queue_free(); await process_frame; quit(0 if failures.is_empty() else 1)

func _process(_delta: float) -> bool:
	return false
