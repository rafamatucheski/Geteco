extends "res://tests/test_mining_machine.gd"
## Separate hydraulic collision: parked motion, pool masks, destruction and
## a real loose rock must remain safe throughout support withdrawal.
func run() -> void:
	stage=Node3D.new(); root.add_child(stage)
	var ground:=StaticBody3D.new()
	var shape:=CollisionShape3D.new(); var box:=BoxShape3D.new()
	box.size=Vector3(80,1,80); shape.shape=box; shape.position.y=-.5
	ground.add_child(shape); stage.add_child(ground)
	machine=spawn("mining_backhoe",Vector3(0,.08,0))
	controls=machine.get_node("MiningMachine")
	await physics_frame
	var anchor: Vector3=controls.cargo_anchor()
	machine.position+=Vector3.RIGHT*3
	for i in 2: await physics_frame
	check(controls.cargo_anchor().distance_to(anchor+Vector3.RIGHT*3)<.02,"parked machine keeps its independent bucket aligned after displacement")
	machine.collision_layer=0
	for i in 2: await physics_frame
	check(controls._bucket_body.collision_layer==0 and controls._bucket_body.collision_mask==0,"pooled carrier has no ghost bucket collision")
	machine.collision_layer=4
	for i in 2: await physics_frame
	check(controls._bucket_body.collision_layer==4 and controls._bucket_body.collision_mask==machine.collision_mask,"reused carrier restores bucket collision")
	controls.set_physics_process(false)
	var rock:=OPERATION.create_rock(20)
	rock.position=controls.cargo_anchor()+Vector3(0,.65,-.5); stage.add_child(rock)
	await physics_frame
	check(controls.acquire(rock),"loose rock captured before support contact regression")
	for i in 75: controls.operate(1.0,1.0/60.0)
	controls.release_cargo()
	check(controls._withdrawal_load()==rock,"release clearance preserves recent-load history before contact")
	# Representa a pequena sobreposição do solver de uma rocha de minério rígida em repouso.
	var bottom := INF
	for child in rock.get_children():
		if child is CollisionShape3D and child.shape is ConvexPolygonShape3D:
			for point in child.shape.points:
				bottom = minf(bottom,(rock.global_basis*(child.transform*point)).y)
	check(is_finite(bottom),"contact fixture reads the current fractured ore collision geometry")
	rock.position.y=controls._bucket_shape.global_position.y+.15-bottom-.01
	rock.force_update_transform()
	var contact_query:=PhysicsShapeQueryParameters3D.new()
	contact_query.shape=controls._bucket_shape.shape
	contact_query.transform=controls._bucket_shape.global_transform
	contact_query.exclude=controls._carrier_rids()
	var contact_hits:=machine.get_world_3d().direct_space_state.intersect_shape(contact_query,8)
	check(not contact_hits.is_empty(),"withdrawal fixture establishes real existing rigid contact")
	var before:=machine.global_transform
	machine.position+=Vector3.FORWARD*.20
	controls.operate(0.0,0.0)
	check(machine.global_transform.is_equal_approx(before),"moving the scoop into its recently released load remains blocked")
	machine.position+=Vector3.BACK*.20
	controls.operate(0.0,0.0)
	check(machine.position.z>before.origin.z+.15,"scoop can separate from existing rigid-load contact")
	machine.controlled=true; machine.set_physics_process(true); controls.set_physics_process(true)
	Input.action_press("brake",.55)
	for i in 150: await physics_frame
	Input.action_release("brake"); Input.action_press("handbrake")
	for i in 90: await physics_frame
	Input.action_release("handbrake")
	check(machine.global_position.z>before.origin.z+3,"ordinary reverse physically withdraws bucket from released ore")
	check(rock.global_position.y>.35 and rock.global_position.y<.9,"released ore settles on real ground after ordinary reverse (y %.2f)" % rock.global_position.y)
	machine.receive_damage(machine.max_health*3)
	check(controls._bucket_body.collision_layer==0 and controls._bucket_body.collision_mask==0,"native machine death immediately removes live scoop collision")
	print("MINING_BUCKET_LIFECYCLE ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	stage.queue_free(); quit(0 if failures.is_empty() else 1)
