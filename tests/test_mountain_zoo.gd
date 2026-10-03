extends SceneTree
const ZOO=preload("res://world/mountain_detail/zoo/MountainZoo.gd")
const REGION=preload("res://world/editing/EditableRegion.gd")
const ACTOR=preload("res://scripts/Actor.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); push_error(message)
func frames(n: int) -> void:
	for i in n: await physics_frame
func run() -> void:
	var region=REGION.build_region("mountain",ZOO.CENTER)
	root.add_child(region)
	for i in 900:
		await process_frame
		if region.pending.is_empty() and region.build_jobs.is_empty(): break
	var zoo=region.find_child("MountainZoo",true,false)
	check(zoo!=null,"Zoo must be present in the production mountain chunks")
	if zoo==null: quit(1); return
	check(zoo.animals.size()==12,"Twelve animals in four habitats")
	var species: Dictionary={}
	for animal in zoo.animals: species[animal.species]=int(species.get(animal.species,0))+1
	check(species=={"giraffe":3,"lion":3,"monkey":3,"zebra":3},"Requested species and zebra group")
	# Flat terrain and no forest trunks throughout the visitor route and pens.
	for x in range(694,739,4):
		for z in range(-381,-343,4):
			check(absf(region.terrain.surface_height_at(Vector2(x,z)))<.01,"Flat supported clearing")
	for key in region.records:
		for record in region.records[key]:
			if record.kind=="tree": check(not ZOO.FOOTPRINT.grow(2).has_point(Vector2(record.position.x,record.position.z)),"No forest trunk inside zoo")
	for animal in zoo.animals:
		for i in 600:
			animal.advance(.1)
			check(absf(animal.position.x-animal.home.x)<=1.21 and absf(animal.position.z-animal.home.z)<=.71,"Animals stay in their separated roaming lanes")
	# Both real actor bodies must be blocked by all sixteen pen walls, including a large step.
	for is_player in [true,false]:
		var actor=ACTOR.new(); actor.is_player=is_player
		root.add_child(actor); actor.set_physics_process(false)
		await frames(3)
		for x in [-10.5,10.5]:
			for z in [-8.5,8.5]:
				for side in [-1.0,1.0]:
					actor.teleport(ZOO.CENTER+Vector3(x+side*9.3,.08,z))
					check(actor.move_and_collide(Vector3(-side*4,0,0))!=null,"Actor blocked by side fence")
					actor.teleport(ZOO.CENTER+Vector3(x,.08,z+side*7.5))
					check(actor.move_and_collide(Vector3(0,0,-side*4))!=null,"Actor blocked by front/back fence")
		actor.teleport(ZOO.CENTER+Vector3(0,.08,18))
		check(actor.move_and_collide(Vector3(0,0,-35))==null,"Entrance and central promenade stay open")
		actor.teleport(ZOO.CENTER+Vector3(-19,.08,0))
		check(actor.move_and_collide(Vector3(38,0,0))==null,"Cross promenade stays open")
		for x in [-21.8,21.8]:
			actor.teleport(ZOO.CENTER+Vector3(x,.08,3))
			check(actor.move_and_collide(Vector3(0,0,-3))!=null,"Bench occupies its visible footprint")
		actor.teleport(ZOO.CENTER+Vector3(0,.08,22))
		check(actor.move_and_collide(Vector3(0,0,-5))!=null,"Unpaid actor cannot enter through ticket barrier")
		actor.queue_free(); await frames(2)
	# Ground support includes the complete roadside approach, with no step or gap.
	for z in range(-381,-328,2):
		var from:=Vector3(716,1,z)
		var hit:=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,from-Vector3.UP*2,1))
		check(not hit.is_empty(),"Ground supports route to road")
	# Streaming out removes the zoo from physics/rendering; re-entry restores one instance.
	region.set_focus(Vector3(470,0,-285))
	for i in 600:
		await process_frame
		if region.pending.is_empty() and region.build_jobs.is_empty(): break
	check(region.find_child("MountainZoo",true,false)==null,"Zoo detached when its chunk leaves residency")
	region.set_focus(ZOO.CENTER)
	for i in 900:
		await process_frame
		if region.pending.is_empty() and region.build_jobs.is_empty(): break
	check(region.find_children("MountainZoo","Node3D",true,false).size()==1,"One zoo restored on re-entry")
	print("MOUNTAIN_ZOO ","PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
