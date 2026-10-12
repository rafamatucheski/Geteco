extends SceneTree
const ACTOR:=preload("res://scripts/Actor.gd")
var world
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(90).timeout.connect(func():quit(124))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	while world.session==null or not world.session.ready_for_play: await process_frame
	world.player.teleport(Vector3(-324,.08,30))
	world.player.controlled_automatically=true
	world.player.automatic_direction=Vector3.ZERO
	world.production.region.prepare_collision_at(Vector3(-334,0,12))
	for i in 120: await physics_frame
	var actors:=[]
	for point in [Vector3(-333,0,11.5),Vector3(-333,0,12.5),Vector3(-334.5,0,11.5),Vector3(-334.5,0,12.5)]:
		var actor:=ACTOR.new()
		actor.identity=82200+actors.size()
		world.add_child(actor)
		actor.position=point+Vector3.UP*.08
		actor.route=PackedVector3Array([actor.position,actor.position+Vector3.RIGHT*1.5])
		world.people.append(actor)
		actors.append(actor)
	for frame in 240:
		await physics_frame
		if frame%30!=0: continue
		for actor in actors:
			var meta:={}
			for key in actor.get_meta_list(): meta[key]=str(actor.get_meta(key))
			print("OWNER frame=",frame," actor=",actor.identity," physics=",actor.is_physics_processing()," script=",actor.get_script().resource_path," position=",actor.position," locked=",actor.input_locked," automatic=",actor.controlled_automatically," meta=",meta," groups=",actor.get_groups()," children=",actor.get_children().map(func(n):return n.name))
	world.free()
	quit(0)
