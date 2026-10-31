extends RefCounted
const SITES := [
	["paddock",Vector3(-978,.1,-1274),Vector3.FORWARD,5.0],
	["truck-apron",Vector3(315,.1,-743),Vector3.FORWARD,8.0],
	["digo-apron",Vector3(-118,.1,-908),Vector3.RIGHT,7.0],
]
static func capture(tree: SceneTree, world) -> bool:
	var folder := "res://evidence/desert-floor-fix-20261014/temporal-crossings"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var previous_fps := Engine.max_fps
	Engine.max_fps=30 # Só captura; todas as janelas de desempenho já terminaram.
	var report: Array=[]
	var crossings: Array=[]
	var failed := false
	for site in SITES:
		world.player.automatic_direction=Vector3.ZERO
		world.player.teleport(site[1])
		world.production.region.set_focus(site[1],true)
		world.camera.heading=0
		world.camera.target_size=42
		world.camera.initialized=false
		await tree.create_timer(3).timeout
		world.player.automatic_direction=site[2]
		var start := Time.get_ticks_msec()
		var frame := 0
		while Time.get_ticks_msec()-start<12000:
			world.camera.heading=minf(1.0,float(Time.get_ticks_msec()-start)/5000)*.08
			await RenderingServer.frame_post_draw
			var at: Vector3=world.player.global_position
			var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.2,at-Vector3.UP*2,1))
			if hit.is_empty() or at.y<-.05: failed=true
			var path := "%s/%s-%03d.jpg"%[folder,site[0],frame]
			tree.root.get_texture().get_image().save_jpg(path,.85)
			report.append({"site":site[0],"frame":frame,"time_ms":Time.get_ticks_msec(),"position":str(at),"support":str(hit.get("position","none")),"image":path})
			frame+=1
			if (at-Vector3(site[1])).dot(Vector3(site[2]))>=float(site[3]): break
		world.player.automatic_direction=Vector3.ZERO
		var distance: float=(world.player.global_position-Vector3(site[1])).dot(Vector3(site[2]))
		crossings.append({"site":site[0],"distance_m":distance,"required_m":site[3],"reached":distance>=float(site[3])})
		if distance<float(site[3]): failed=true
		print("DESERT_TOUR ",site[0]," frames=",frame," at=",world.player.position)
	Engine.max_fps=previous_fps
	FileAccess.open(folder+"/frames.json",FileAccess.WRITE).store_string(JSON.stringify({"frames":report,"crossings":crossings,"failed_support_or_crossing":failed},"\t"))
	return not failed
