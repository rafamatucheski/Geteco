extends SceneTree
## Inspeção de arte de perto mais folga física dos modelos estacionados; não é benchmark de FPS.
const ART := preload("res://world/desert/DesertArchitecture.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var folder := "res://evidence/bitrem-art-%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	root.size=Vector2i(1440,900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("8c9fa7")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("bbcbd8")
	environment.environment.ambient_light_energy=.65
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-40,-28,0)
	sun.light_energy=1.3
	sun.shadow_enabled=true
	stage.add_child(sun)
	preload("res://world/desert/DesertGeometry.gd").box(stage,"Floor",Vector3(0,-.1,0),Vector3(100,.2,100),Color("77776e"),true)
	var trucks: Array[Node3D]=[]
	for i in 4:
		var truck := ART.bitrem([Color("a75339"),Color("718787"),Color("d2b676"),Color("76634e")][i])
		truck.position.x=-float(i)*6.4
		stage.add_child(truck)
		trucks.append(truck)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	for truck in trucks:
		# Um ator em pé precisa ser bloqueado na cabine e nos dois reboques, de qualquer lado.
		for z in [-11.0,-2.3,8.2]:
			for side in [-1.0,1.0]:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(truck.position+Vector3(side*3,.95,z),truck.position+Vector3(0,.95,z),1))
				if hit.is_empty(): failures.append("Missing physical envelope at "+str(truck.position)+" z="+str(z))
		var query := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.height=1.75
		capsule.radius=.32
		query.shape=capsule
		query.collision_mask=1
		query.transform=Transform3D(Basis.IDENTITY,truck.position+Vector3(3.2,.94,0))
		if not space.intersect_shape(query).is_empty(): failures.append("Parking aisle blocked")
	if DisplayServer.get_name()!="headless":
		var camera := Camera3D.new()
		camera.projection=Camera3D.PROJECTION_ORTHOGONAL
		stage.add_child(camera)
		camera.make_current()
		for shot in [
			{"id":"cab","at":Vector3(0,2,-10.8),"offset":Vector3(8,4,-10),"size":7.5},
			{"id":"side","at":Vector3(0,1.8,0),"offset":Vector3(30,5,-1),"size":29.0},
			{"id":"rear","at":Vector3(0,2,11.5),"offset":Vector3(8,4,10),"size":8.0},
			{"id":"fleet","at":Vector3(-9.6,1,0),"offset":Vector3(30,27,-36),"size":39.0}]:
			camera.position=shot.at+shot.offset
			camera.look_at(shot.at)
			camera.size=shot.size
			for i in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(shot.id+".png"))
	print("BITREM_ART ",folder," physics_checks=28 failures=",failures)
	quit(0 if failures.is_empty() else 1)
