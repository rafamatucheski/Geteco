extends "res://tests/test_vertice_depth.gd"
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const NATIVE = preload("res://world/places/NativePlace.gd")
var folder := ""

func run() -> void:
	create_timer(180).timeout.connect(func(): quit(3))
	var rendered:=DisplayServer.get_name()!="headless"
	folder=preload("res://tests/fixtures/NorthGatewayFixtures.gd").output_dir("harbor-building-contract")
	viewport=SubViewport.new()
	viewport.size=Vector2i(960,720)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage:=Node3D.new()
	stage.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(stage)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	stage.add_child(camera)
	camera.current=true
	var sun:=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-25,0)
	stage.add_child(sun)
	var diagnostic:=StandardMaterial3D.new()
	diagnostic.albedo_color=Color(1,0,1)
	diagnostic.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	for definition in CATALOG.definitions():
		for floor_index in definition.floor_count:
			var selected:=""
			for arg in OS.get_cmdline_user_args():
				if arg.begins_with("--variant="): selected=arg.trim_prefix("--variant=")
			if not selected.is_empty() and int(selected)!=int(definition.variant)+floor_index: continue
			var room=NATIVE.new()
			room.definition=definition.duplicate(true)
			room.definition.variant+=floor_index
			stage.add_child(room)
			camera.size=definition.camera_size
			camera.position=definition.camera_target+Vector3(0,18,15)
			camera.look_at(definition.camera_target)
			await physics_frame
			await physics_frame
			var label: String=definition.id+"-"+str(floor_index)
			var stair:=Vector3(-definition.size.x*.5+1.45,.04,1.45)
			for player in [true,false]:
				var actor=ACTOR.new()
				actor.is_player=player
				actor.controlled_automatically=true
				actor.disable_mode=CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
				stage.add_child(actor)
				actor.set_physics_process(false)
				for frame in 4: await process_frame
				actor.process_mode=Node.PROCESS_MODE_DISABLED
				var who:=label+("-Dante" if player else "-NPC")
				for point in [definition.spawn,definition.exit,stair,stair+Vector3.RIGHT*1.35,Vector3(0,0,-1.5)]:
					actor.position=point+Vector3.UP*.04
					check(room.is_floor_clear(point),who+" floor clear "+str(point))
					check(not actor.test_move(actor.global_transform,Vector3.UP*.002),who+" full body admission "+str(point))
					var hit:=stage.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.position+Vector3.UP*.1,actor.position-Vector3.UP*.3,1))
					check(not hit.is_empty(),who+" floor support "+str(point))
				actor.position=Vector3(0,.04,definition.spawn.z)
				check(not actor.test_move(actor.global_transform,Vector3(0,0,-definition.spawn.z-1.5)),who+" entrance central corridor")
				actor.position=Vector3(0,.04,1.45)
				check(not actor.test_move(actor.global_transform,stair-actor.position),who+" central corridor to stairs")
				var furniture_checked:=0
				for bounds in room.solid_bounds:
					var center: Vector3=bounds.get_center()
					for side in [Vector3.BACK,Vector3.FORWARD,Vector3.RIGHT,Vector3.LEFT]:
						var half: float=bounds.size.x*.5 if side.x!=0 else bounds.size.z*.5
						var start: Vector3=Vector3(center.x,.04,center.z)+side*(half+.6)
						if absf(start.x)>definition.size.x*.5-.4 or absf(start.z)>definition.size.y*.5-.4 or not room.is_floor_clear(start): continue
						actor.position=start
						check(actor.test_move(actor.global_transform,-side*(half+1.2)),who+" furniture swept solid "+str(bounds))
						furniture_checked+=1
						break
				check(furniture_checked>=12,who+" at least 12 reachable solids exercised")
				if rendered:
					actor.position=definition.spawn+Vector3.UP*.04
					actor.reset_physics_interpolation()
					(await capture()).save_png(folder.path_join(who+"-natural.png"))
					mask_meshes(actor.visual,diagnostic)
					# All four floors share a low partition at z=-.8. Compare actual
					# depth behind it with the same unobstructed rig and a front control.
					for point in [Vector3(1.4,.04,-1.35),Vector3(0,.04,2.4)]:
						actor.position=point
						actor.reset_physics_interpolation()
						check(room.is_floor_clear(point),who+" depth pose on accessible floor")
						var actual:=await capture()
						room.hide()
						var control:=await capture()
						room.show()
						var count:=mask_count(control)
						var ratio:=float(mask_count(actual))/maxf(1,count)
						check(count>100,who+" depth positive control")
						check(ratio>.05 and ratio<.95 if point.z<0 else ratio>.95,who+" occlusion separately from visibility: "+str(ratio))
						actual.save_png(folder.path_join(who+("-behind.png" if point.z<0 else "-front.png")))
				actor.free()
			room.set_active(false)
			check(not room.visible and room.process_mode==Node.PROCESS_MODE_DISABLED,label+" inactive room disabled")
			room.free()
			await physics_frame
	check(CATALOG.valid_floors({"harbor_customs_house":1}),"floor save accepts authored storey")
	check(CATALOG.valid_floors(JSON.parse_string('{"harbor_customs_house":1}')),"floor save accepts JSON numeric representation")
	for invalid in [null,[],{"harbor_customs_house":4},{"harbor_customs_house":.5},{"unknown":0}]:
		check(not CATALOG.valid_floors(invalid),"malformed floor save rejected "+str(invalid))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("HARBOR_BUILDING_CONTRACT ",folder," checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
