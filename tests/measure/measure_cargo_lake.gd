extends "res://tests/measure/measure_cargo_plane.gd"
## Caminhada real no encontro acampamento, margem sul e rampa do avião.
func fingerprints() -> Dictionary:
	var result:=super.fingerprints()
	for path in ["world/regions/NativeLake.gd","world/regions/CargoLakeSurface.gd","world/regions/cargo_lake_surface.gdshader","world/regions/CargoLakeDressing.gd","world/regions/cargo_lake_props.gdshader","world/regions/OriginalLakeData.json","world/regions/mountain_ground.gdshaderinc","world/regions/mountain_lake.gdshader","world/regions/MountainTerrain3D.gd","world/regions/mountain_terrain.gdshader"]:
		result[path]=FileAccess.get_sha256("res://"+path) if FileAccess.file_exists("res://"+path) else "absent"
	return result

func run() -> void:
	await super.run()
	started=0
	if not is_instance_valid(plane): return
	var origin: Vector3=plane.global_position
	world.player.teleport(origin+Vector3(9,.14,18.5))
	world.player.speed=2.4
	world.camera.heading=0; world.camera.initialized=false
	route=PackedVector3Array()
	for point in [Vector3(16,0,14.5),Vector3(14,0,7.5),Vector3(7.1,0,10.5),Vector3(0,0,10.5),Vector3(-4,0,14),Vector3(9,0,18.5)]:
		route.append(origin+point)
	waypoint=0; sample_age=0
	for i in 90: await physics_frame
	await photograph("camp-ground")
	started=Time.get_ticks_usec(); previous=started
	print("CARGO_LAKE_READY ",folder)

func finish() -> void:
	# O benchmark de rota e as fotografias gerais do pai usam o mesmo Main.
	await super.finish()
