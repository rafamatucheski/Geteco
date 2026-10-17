extends SceneTree
## As 6 casas rurais da Vila dos Caminhoneiros com a casca pintada (PaintedFacadeKit):
## uma porta só (a DoorPivot 3D, no vão pintado), colisão que barra/libera, telhado e
## paredes altas que somem ao entrar, base rente ao chão e interior/porão intactos.
## Roda com: tools/run_godot_locked.sh --path . --script res://tests/test_painted_truckers_homes.gd
const HOMES := preload("res://gameplay/urban_v1/TruckersVillageHomes.gd")
const PAINTED := preload("res://gameplay/urban_v1/TruckersVillagePaintedHomes.gd")
const LAYOUT := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd").HOME_LAYOUT
const ACTOR := preload("res://scripts/Actor.gd")
var checks := 0
var failures: Array[String] = []
class WorldFixture extends Node3D:
	var player: Node3D
class StateFixture extends RefCounted:
	var place_id := ""
class SessionFixture extends RefCounted:
	var world
	var state := StateFixture.new()
	var weather = null
class VillageFixture extends Node3D:
	var solids: Array[StaticBody3D] = []
	var placements: Array[Dictionary] = []
	var houses: Array[Vector3] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)

func _count_named(node: Node,prefix: String) -> int:
	var total := 1 if String(node.name).begins_with(prefix) else 0
	for child in node.get_children(): total += _count_named(child,prefix)
	return total

## Algum triângulo de `mesh` cobre o ponto (x, y) da frente? (projeção XY; frente em +Z)
func _front_covers(mesh: MeshInstance3D,x: float,y: float) -> bool:
	var faces := mesh.mesh.get_faces()
	for i in range(0,faces.size(),3):
		var a := faces[i]
		var b := faces[i+1]
		var c := faces[i+2]
		if absf(a.z-b.z)>.01 or absf(a.z-c.z)>.01 or a.z<1.0: continue
		var p := Vector2(x,y)
		var d1 := (p-Vector2(b.x,b.y)).cross(Vector2(a.x,a.y)-Vector2(b.x,b.y))
		var d2 := (p-Vector2(c.x,c.y)).cross(Vector2(b.x,b.y)-Vector2(c.x,c.y))
		var d3 := (p-Vector2(a.x,a.y)).cross(Vector2(c.x,c.y)-Vector2(a.x,a.y))
		if not ((d1<0 or d2<0 or d3<0) and (d1>0 or d2>0 or d3>0)): return true
	return false

func _ids(homes: Node3D,index: int) -> Array:
	var out := []
	for row in homes.furniture:
		if row.home==index and not (row.id in ["ExteriorWall","DoorHeader"]): out.append(row.id)
	out.sort()
	return out

func run() -> void:
	OS.set_environment("GETECO_PAINTED_TRUCKERS_HOMES","1")
	check(PAINTED.enabled(),"Casca pintada ligada por padrão (sem GETECO_PAINTED_TRUCKERS_HOMES=0)")
	var world := WorldFixture.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var ground := BoxShape3D.new()
	ground.size = Vector3(350,.2,350)
	collision.shape = ground
	collision.position.y = -.1
	floor.add_child(collision)
	world.add_child(floor)
	var village := VillageFixture.new()
	world.add_child(village)
	var homes := HOMES.new()
	village.add_child(homes)
	homes.build(village,LAYOUT)
	# Referência: as mesmas casas em caixas (A/B pelo interruptor), só para comparar contagens.
	OS.set_environment("GETECO_PAINTED_TRUCKERS_HOMES","0")
	var old_village := VillageFixture.new()
	world.add_child(old_village)
	var old_homes := HOMES.new()
	old_village.add_child(old_homes)
	old_homes.build(old_village,LAYOUT)
	# Só para contar: sem colisão (senão a porta antiga ficaria no meio do vão novo).
	old_homes.set_region_active(false)
	OS.set_environment("GETECO_PAINTED_TRUCKERS_HOMES","1")
	var player := ACTOR.new()
	player.is_player = true
	player.controlled_automatically = true
	player.position = Vector3(100,.04,100)
	world.add_child(player)
	world.player = player
	var outside_camera := Camera3D.new()
	world.add_child(outside_camera)
	outside_camera.make_current()
	player.camera = outside_camera
	var session := SessionFixture.new()
	session.world = world
	homes.configure(session)
	for i in 4: await physics_frame
	# --- Interruptor A/B: sem casca pintada nada do kit existe e a porta é a de antes.
	check(old_homes.homes.all(func(room): return not room.painted and absf(float(room.door_layout.x))<.001 and is_equal_approx(float(room.door_layout.width),1.8)),"Interruptor =0 volta ao 3D antigo (porta centrada 1,8 m)")
	check(_count_named(old_homes,"PaintedFacade_")==0,"Interruptor =0 não cria nenhum kit pintado")
	check(homes.homes.size()==6,"Seis casas")
	var styles := {}
	for index in 6:
		var room: Dictionary = homes.homes[index]
		var home: Node3D = room.root
		var label := "Casa%d"%(index+1)
		check(room.painted and room.has("painted_shell"),"%s tem casca pintada"%label)
		var kit: Node3D = room.painted_shell
		styles[String(kit.get_meta("style"))] = true
		check(String(kit.name).begins_with("PaintedFacade_casa-rural-chapa"),"%s usa um dos três estilos casa-rural-chapa"%label)
		check(kit.get_parent()==room.upper,"%s: paredes pintadas penduradas em UpperWalls"%label)
		var roof_mesh := kit.get_parent().get_parent().get_node("Roof").get_node_or_null("Roof")
		check(roof_mesh!=null and roof_mesh.get_parent()==room.roof and kit.get_node_or_null("Roof")==null,"%s: telhado pintado pendurado em Roof"%label)
		# Uma porta só: a DoorPivot 3D; nenhuma folha do kit.
		check(_count_named(home,"DoorPivot")==1 and _count_named(home,"EntryDoor")==1,"%s: uma única DoorPivot/EntryDoor"%label)
		check(_count_named(kit,"Door")==0 and _count_named(kit,"Doorway")==0 and _count_named(kit,"Hinge")==0,"%s: sem folha nem âncora de porta do kit (sem porta duplicada)"%label)
		check(_count_named(home,"PaintedFacadeSolid")==0,"%s: o kit não acrescenta colisão"%label)
		check(_count_named(home.get_node("DoorPivot"),"PaintedDoorFront")==1,"%s: a porta 3D leva a imagem da porta"%label)
		# Vão pintado = onde a porta 3D gira.
		var layout: Dictionary = room.door_layout
		var pivot: Node3D = room.door
		check(absf(pivot.position.x+float(layout.width)*.5-float(layout.x))<.005,"%s: dobradiça da DoorPivot no batente do vão pintado"%label)
		var front := kit.get_node("Front") as MeshInstance3D
		check(not _front_covers(front,float(layout.x),1.0),"%s: a parede pintada tem o vão aberto onde a porta gira"%label)
		check(not _front_covers(front,float(layout.x)+float(layout.width)*.45,1.0) and not _front_covers(front,float(layout.x)-float(layout.width)*.45,1.0),"%s: vão aberto até os batentes"%label)
		check(_front_covers(front,float(layout.x),2.7) and _front_covers(front,float(layout.x)+float(layout.width),1.0),"%s: verga e parede ao lado do vão fechadas"%label)
		check(absf(float(layout.width)-1.86)<.08 and absf(float(layout.height)-2.1)<.08,"%s: vão medido ~1,86 x 2,1 m"%label)
		# Rente ao chão: nada da casca abaixo do chão nem solto acima dele.
		var low := INF
		for mesh_name in ["Front","Back","Sides"]:
			var mesh := kit.get_node(mesh_name) as MeshInstance3D
			low = minf(low,mesh.mesh.get_aabb().position.y+kit.position.y)
		check(absf(low)<.05,"%s: base da casca rente ao chão (%.3f m)"%[label,low])
		# Interior e peças que a lógica procura estão como no 3D antigo.
		check(_ids(homes,index)==_ids(old_homes,index),"%s: mesmos móveis/sólidos do interior que no 3D antigo"%label)
		check(room.has("loot") and is_instance_valid(room.loot) and home.has_node("CashFind"),"%s: CashFind presente"%label)
		check(room.inside==old_homes.homes[index].inside,"%s: retângulo interno igual"%label)
	check(styles.size()>=2,"As casas variam entre os estilos (%d usados)"%styles.size())
	check(homes.solids.size()==old_homes.solids.size(),"Mesmo número de colisões de sólidos que no 3D antigo (%d)"%homes.solids.size())
	check(village.solids.size()==homes.solids.size(),"Sólidos continuam no ciclo da região")
	# --- Casa 1: anexo de despensa e porta do porão no fundo.
	check(homes.furniture.any(func(row): return row.home==0 and row.id=="CellarDoorHeader"),"Casa1: verga do porão e vão do fundo mantidos")
	check(homes.furniture.filter(func(row): return row.home==0 and row.id=="ExteriorWall").size()==homes.furniture.filter(func(row): return row.home==1 and row.id=="ExteriorWall").size()+1,"Casa1: fundo partido ao redor do porão (uma parede a mais)")
	var cellar_room: Dictionary = homes.homes[0]
	cellar_room.upper.visible = false
	cellar_room.roof.visible = false
	check(not cellar_room.painted_shell.get_node("Back").is_visible_in_tree(),"Casa1: ao descer ao porão (upper/roof escondidos) o fundo pintado some junto")
	cellar_room.upper.visible = true
	cellar_room.roof.visible = true
	# --- Porta, colisão, recorte ao entrar.
	for index in 6:
		var room: Dictionary = homes.homes[index]
		var home: Node3D = room.root
		var label := "Casa%d"%(index+1)
		var door_x := float(room.door_layout.x)
		var exterior := home.to_global(Vector3(door_x,.04,6))
		var motion: Vector3 = home.basis*Vector3(0,0,-5)
		check(player.test_move(Transform3D(Basis.IDENTITY,exterior),motion),"%s: porta fechada barra o jogador no vão pintado"%label)
		# A parede pintada ao lado do vão também barra (colisão das caixas continua).
		var beside := home.to_global(Vector3(door_x+2.6,.04,6))
		check(player.test_move(Transform3D(Basis.IDENTITY,beside),motion),"%s: parede ao lado do vão barra"%label)
		player.teleport(exterior)
		for frame in 28: await physics_frame
		check(float(room.amount)>.98,"%s: proximidade abre a porta"%label)
		var contact := player.move_and_collide(motion)
		check(contact==null,"%s: jogador atravessa o vão com a porta aberta"%label)
		for frame in 10: await physics_frame
		check(homes.current_home==index,"%s: entrar ativa o interior"%label)
		check(not room.roof.visible and not room.upper.visible,"%s: Roof e UpperWalls escondem"%label)
		var roof_mesh := room.roof.get_node("Roof") as Node3D
		check(not roof_mesh.is_visible_in_tree(),"%s: telhado pintado some ao entrar (cutaway)"%label)
		check(not room.painted_shell.get_node("Front").is_visible_in_tree() and not room.painted_shell.get_node("Sides").is_visible_in_tree(),"%s: paredes pintadas somem ao entrar, o interior fica à vista"%label)
		check(player.camera==homes.interior_camera,"%s: câmera ortogonal interna"%label)
		check(absf(player.position.y)<.15,"%s: jogador no chão"%label)
		player.teleport(home.to_global(Vector3(door_x,.04,3)))
		for frame in 28: await physics_frame
		player.global_position.y = .04
		contact = player.move_and_collide(home.basis*Vector3(0,0,4))
		check(contact==null,"%s: saída pelo vão pintado livre"%label)
		for frame in 10: await physics_frame
		check(homes.current_home==-1 and room.roof.visible and roof_mesh.is_visible_in_tree() and room.painted_shell.get_node("Front").is_visible_in_tree(),"%s: ao sair o telhado e as paredes pintadas voltam"%label)
		player.teleport(Vector3(100,.04,100))
		for frame in 28: await physics_frame
		check(float(room.amount)<.02,"%s: porta fecha depois que o jogador se afasta"%label)
		check(player.test_move(Transform3D(Basis.IDENTITY,exterior),motion),"%s: porta fechada de novo barra"%label)
	world.free()
	print("PAINTED_TRUCKERS_HOMES checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
