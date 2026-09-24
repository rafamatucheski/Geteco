extends RefCounted
const GEO = preload("res://scripts/player/WeaponPresentation3D.gd")
const FINISHES := {"matte":Color("282d32"), "sand":Color("b9a175"), "olive":Color("596348"), "chrome":Color("b9c9d3"), "wood":Color("73452c")}

static func apply(root: Node3D, id: String, entry: Dictionary, muzzle: Vector3) -> void:
	var parts: Dictionary = entry.get("parts",{})
	var finish: String = parts.get("finish","none")
	if FINISHES.has(finish): _finish(root,finish)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("252b30")
	steel.metallic = .7
	steel.roughness = .4
	if parts.get("muzzle","") == "suppressor":
		GEO._cylinder(root,"Suppressor",muzzle+Vector3(0,0,-.068),.025,.145,steel,Vector3(90,0,0))
	if parts.has("laser"):
		var lens := StandardMaterial3D.new()
		lens.albedo_color = Color("67ed8b") if parts.laser == "laser_green" else Color("f54d49")
		GEO._box(root,"LaserModule",Vector3(-.039,muzzle.y-.025,muzzle.z+.085),Vector3(.026,.025,.065),steel)
		GEO._cylinder(root,"LaserLens",Vector3(-.039,muzzle.y-.025,muzzle.z+.051),.006,.002,lens,Vector3(90,0,0))
	if parts.get("magazine","") == "extended":
		if id == "shotgun":
			GEO._cylinder(root,"ExtendedMagazineTube",Vector3(0,-.015,muzzle.z+.09),.018,.17,steel,Vector3(90,0,0))
		elif id == "ak47":
			GEO._profile(root,"ExtendedMagazine",PackedVector2Array([Vector2(-.065,-.17),Vector2(-.115,-.15),Vector2(-.13,-.19),Vector2(-.095,-.225),Vector2(-.073,-.2)]),.031,steel)
		else:
			GEO._box(root,"ExtendedMagazine",Vector3(0,-.115,.016 if id == "pistol" else -.035),Vector3(.035,.085,.047),steel)
	if parts.has("grip"):
		GEO._box(root,"ControlGrip",Vector3(0,-.09,-.14),Vector3(.032,.105,.035),steel)
	if parts.has("stock"):
		# The authored meshes are material-batched before customization; use their
		# measured attachment coordinates, not names removed by the batching pass.
		var butt_z := .182 if id == "hunting_rifle" else (.29 if id == "ak47" else (.19 if id == "smg" else .25))
		GEO._box(root,"StabilizedButtPad",Vector3(0,.01 if id == "smg" else -.02,butt_z),Vector3(.055,.14 if id == "hunting_rifle" else .095,.025),steel)
	if parts.has("scope"):
		if id == "hunting_rifle":
			# Upgrade the existing optic's objective rather than stacking a second.
			GEO._cylinder(root,"UpgradedObjective",Vector3(0,.097,-.222),.034,.042,steel,Vector3(90,0,0))
			var lens := StandardMaterial3D.new()
			lens.albedo_color = Color("477d87")
			lens.metallic = .45
			GEO._cylinder(root,"UpgradedObjectiveLens",Vector3(0,.097,-.244),.029,.002,lens,Vector3(90,0,0))
			return
		GEO._box(root,"ScopeMount",Vector3(0,.045,-.045),Vector3(.035,.05,.095),steel)
		GEO._cylinder(root,"ScopeTube",Vector3(0,.086,-.045),.027,.19,steel,Vector3(90,0,0))
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color("477d87")
		glass.metallic = .45
		GEO._cylinder(root,"ScopeLens",Vector3(0,.086,-.141),.025,.002,glass,Vector3(90,0,0))

static func _finish(node: Node, finish: String) -> void:
	if node is MeshInstance3D:
		var source: Material = node.material_override
		if source == null and node.mesh != null and node.mesh.get_surface_count() > 0: source = node.get_active_material(0)
		if source is StandardMaterial3D and not source.emission_enabled and source.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			# Duplicate per mesh: never recolor another weapon or a shared material.
			var material: StandardMaterial3D = source.duplicate()
			material.albedo_color = FINISHES[finish].lerp(source.albedo_color,.18)
			material.metallic = .93 if finish == "chrome" else (.0 if finish == "wood" else .32)
			material.roughness = .2 if finish == "chrome" else .68
			node.material_override = material
	for child in node.get_children(): _finish(child,finish)
