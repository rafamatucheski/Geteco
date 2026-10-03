extends "res://tests/test_vertice_depth.gd"
## Actual native meshes + player/NPC rigs. Pixel masks verify the Mobile fade,
## separately from swept physics, with unobstructed positive controls.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
var dest := "res://evidence/bank-gameplay-20261002/depth"

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest))
	viewport=SubViewport.new()
	viewport.size=Vector2i(960,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node3D.new()
	# Static probes must render at the measured pose, not an interpolated prior
	# location from the swept-collision cases (3 render frames can be <1 tick).
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var room = PLACES.create_place("harbor_bank")
	stage.add_child(room)
	var camera := Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=14
	stage.add_child(camera)
	camera.position=Vector3(0,18.7,15)
	camera.look_at(Vector3(0,.7,0))
	camera.current=true
	var diagnostic := StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for player in [true,false]:
		var actor := ACTOR.new()
		actor.is_player=player
		actor.controlled_automatically=true
		actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		stage.add_child(actor)
		actor.set_physics_process(false)
		for frame in 20: await process_frame
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		mask_meshes(actor.visual,diagnostic)
		var who := "player" if player else "npc"
		room.set_vault_open(0)
		await physics_frame
		actor.position=Vector3(0,.04,-2.3)
		check(actor.test_move(actor.global_transform,Vector3(0,0,-2)),who+" closed door blocks swept body")
		room.set_vault_open(1)
		await physics_frame
		check(not actor.test_move(actor.global_transform,Vector3(0,0,-1.9)),who+" open door permits full-body vault crossing")
		actor.position=Vector3(-3,.04,-4.2)
		check(actor.test_move(actor.global_transform,Vector3(0,0,2)),who+" vault partition blocks full-body movement")
		for x in [-3,0,3]:
			actor.position=Vector3(x,.04,-4.2)
			check(not actor.test_move(actor.global_transform,Vector3.UP*.001),who+" cash spawn has full-body clearance "+str(x))
		for point in [Vector3(-4.5,.04,-.6),Vector3(4.5,.04,-.6)]:
			actor.position=point+Vector3(0,0,1)
			check(actor.test_move(actor.global_transform,Vector3(0,0,-2)),who+" counter blocks swept body "+str(point.x))
		for setup in [
			{"id":"vault-left","point":Vector3(-3,.04,-4.2),"fade":true},
			{"id":"vault-right","point":Vector3(3,.04,-4.2),"fade":true},
			{"id":"vault-center","point":Vector3(0,.04,-4.2),"fade":true},
			{"id":"lobby","point":Vector3(0,.04,.5),"fade":false},
			{"id":"exit","point":Vector3(.95,.04,3.5),"fade":false}]:
			actor.position=setup.point
			actor.reset_physics_interpolation()
			room.update_bank_visibility(Vector3.ZERO,1)
			var opaque := await capture()
			room.update_bank_visibility(actor.position,1)
			var actual := await capture()
			room.hide()
			var control := await capture()
			room.show()
			var count := mask_count(control)
			var ratio := float(mask_count(actual))/maxf(1,count)
			print("BANK_DEPTH pixels ",who," ",setup.id," opaque=",mask_count(opaque)," faded=",mask_count(actual)," control=",count)
			check(count>100,who+" "+setup.id+" positive visible control")
			check(ratio>.65,who+" "+setup.id+" visible actor ratio="+str(ratio))
			if setup.fade:
				check(mask_count(actual)>mask_count(opaque)*1.2,who+" "+setup.id+" real fade reveals previously occluded actor")
			actual.save_png(dest.path_join(who+"-"+setup.id+".png"))
			opaque.save_png(dest.path_join(who+"-"+setup.id+"-opaque.png"))
		actor.free()
	FileAccess.open(dest.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("BANK_DEPTH checks=",checks," failures=",failures)
	stage.free()
	viewport.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
