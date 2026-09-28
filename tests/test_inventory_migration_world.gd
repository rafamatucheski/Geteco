extends SceneTree
const ECONOMY=preload("res://systems/economy/Economy.gd")
const GRID=preload("res://systems/inventory/GridInventory.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1; push_error(label)
	print("MIGRATION_WORLD ","PASS " if ok else "FAIL ",label)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var world=load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival",true); root.add_child(world); current_scene=world
	for i in 2400:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: quit(3); return
	var field=world.session.field_inventory
	world.player.controlled_automatically=true; world.player.automatic_direction=Vector3.ZERO
	var e=world.session.state.economy
	var legacy=ECONOMY.new(); legacy.grant_item("first_aid",25)
	check(e.restore_snapshot(legacy.snapshot()),"legacy non-spatial supplies restore")
	e.enable_grid_inventory()
	check(e.grid_snapshot().trunk.is_empty() and GRID.count(e.grid_snapshot(),"first_aid",false)==25,"migration preserves all supplies outside Monaliza")
	var source: Dictionary=field.sources[3]
	world.player.teleport(source.point+Vector3(0,.1,2)); world.production.region.set_focus(world.player.position)
	for i in 120: await physics_frame
	field._refresh_world()
	var drop: Dictionary=e.grid_snapshot().ground.back()
	check(not drop.get("pending",false) and drop.region==world.session.state.region_id,"pending migrated bag is placed in actual region")
	var key:="drop_"+str(drop.uid)
	check(field.pickups.has(key),"migrated bag has physical presentation")
	if field.pickups.has(key):
		# A neighboring source bag or passing vehicle may own the first approach.
		# Find a walkable side using the same ground and interaction queries.
		for i in 8:
			var candidate: Vector3=field._ground_point(field.pickups[key].node.global_position+Vector3.FORWARD.rotated(Vector3.UP,i*TAU/8.0)*.85)
			if not candidate.is_finite(): continue
			world.player.teleport(candidate+Vector3.UP*.02)
			for frame in 8: await physics_frame
			if field.nearest_action().get("target","")==key: break
		print("MIGRATION_APPROACH expected=",key," actual=",field.nearest_action()," player=",world.player.position," bag=",field.pickups[key].node.position)
		check(field.perform(key),"migrated supplies can be recovered by real interaction")
	check(e.grid_snapshot().bag=="handbag" and GRID.count(e.grid_snapshot(),"first_aid")==25,"recovery reunites preserved supplies")
	world.free(); await process_frame
	print("MIGRATION_WORLD_RESULT failures=",failures)
	quit(1 if failures else 0)
