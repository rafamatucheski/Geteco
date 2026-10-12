extends SceneTree
const ANIMAL = preload("res://world/mountain_detail/zoo/ZooAnimal.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func run() -> void:
	var animals: Array = []
	var triangles := 0
	var draws := 0
	for species in ["giraffe","lion","zebra","monkey"]:
		for identity in 3:
			var animal = ANIMAL.new(); animal.species = species; animal.phase = float(identity)
			animal.home = Vector3(identity*3,0,0); root.add_child(animal); animals.append(animal)
			check(animal.legs.size() == 4 and animal.knees.size() == 4, species+" has four articulated limbs")
			check(animal.tail.size() >= 3, species+" has an articulated tail")
			var instances := animal.find_children("*","MeshInstance3D",true,false)
			for instance in instances:
				check(instance.mesh is ArrayMesh, "Anatomy uses profile meshes rather than primitive stacks")
				draws += instance.mesh.get_surface_count()
				for surface in instance.mesh.get_surface_count(): triangles += int(instance.mesh.surface_get_array_len(surface)/3)
			var travelled := 0.0
			var stepped := false
			for frame in 1200:
				var before: Vector3 = animal.position
				animal.advance(1.0/60.0)
				travelled += before.distance_to(animal.position)
				if absf(animal.knees[0].rotation.x) > .01: stepped = true
				var offset: Vector3 = animal.position-animal.home
				if not animal.transform.is_finite() or absf(offset.x) > 1.2 or absf(offset.z) > .7:
					check(false,"Finite motion stays within established pen lanes"); break
			check(travelled > .2 and stepped, species+" walks with bending knees")
			# Set every identity in the middle of its rest interval.
			animal.clock = 12.0-animal.phase*1.7; animal.advance(0.0)
			var rest_transform: Transform3D = animal.transform
			var rest_leg: Transform3D = animal.legs[0].transform
			for frame in 120: animal.advance(1.0/60.0)
			check(not animal.moving and animal.transform == rest_transform, species+" truly stops without sliding")
			check(animal.legs[0].transform == rest_leg, species+" keeps feet still during idle breathing and gaze")
			check(absf(animal.head.rotation.x) <= .017 and absf(animal.head.rotation.y) <= .036, species+" has restrained idle head motion")
	check(animals.size() == 12,"Twelve original animals remain supported")
	check(draws <= 260,"Bounded draw submissions for all twelve animals")
	check(triangles <= 50000,"Bounded sculpted geometry for all twelve animals")
	for species_index in 4:
		var first = animals[species_index*3].torso.get_child(0)
		var second = animals[species_index*3+1].torso.get_child(0)
		check(first.mesh == second.mesh and first.material_override == second.material_override,"Species share torso mesh and material")
	print("ZOO_ANIMAL_ANATOMY ", checks," checks ",failures," failures; draws=",draws," triangles=",triangles)
	for animal in animals: animal.free()
	await process_frame
	quit(1 if failures else 0)
