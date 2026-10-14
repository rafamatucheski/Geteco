extends RefCounted
## Capture-only material/architecture study. Call once after the Police chunk
## has loaded. No production hook, shared-material mutation, collision or light.
## Removing CoastalFacadeTrial restores the original opaque concrete facade.

static func apply(world: Node) -> Dictionary:
	var result := {"buildings": 0, "panes": 0, "draw_meshes": 0}
	for candidate in world.get_tree().get_nodes_in_group("exterior_reveal_building"):
		if not candidate is UrbanBuildingBase or not world.is_ancestor_of(candidate): continue
		var building := candidate as UrbanBuildingBase
		if building.building_id != "Police": continue
		if building.visuals_root.has_node("CoastalFacadeTrial"): continue
		var bottom := 4.12
		var top := building.height - .38
		if top <= bottom + .8: continue
		var trial := Node3D.new()
		trial.name = "CoastalFacadeTrial"
		building.visuals_root.add_child(trial)
		var glass := StandardMaterial3D.new()
		glass.resource_name = "CoastalTrialCoatedGlazing"
		glass.albedo_color = Color("8ba4ae")
		glass.roughness = .12
		glass.metallic = .75
		glass.metallic_specular = .8
		glass.clearcoat_enabled = false
		# Diagnostic coated-glass response, intentionally stronger than the first
		# trial. Keep the plane normals unchanged to isolate reflection response:
		# from the elevated camera, a vertical facade reflects the lower hemisphere
		# (street/opposing buildings); a uniform sky-ground stays uniform here.
		# Opaque glazing is intentional: the original building has no upper-floor
		# room geometry behind this study; never expose its solid collision shell.
		var frame := StandardMaterial3D.new()
		frame.albedo_color = Color("354650")
		frame.roughness = .62
		frame.metallic = .25
		var panes := SurfaceTool.new()
		var joints := SurfaceTool.new()
		panes.begin(Mesh.PRIMITIVE_TRIANGLES)
		joints.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Match the EXISTING concrete pilasters in PoliceStationDressing._facade.
		# Their structure, parapet, rear and side elevations remain untouched.
		var count := maxi(1, int(building.building_size.x / 2.2))
		var span := (building.building_size.x - .3) / float(count)
		var first := -building.building_size.x * .5 + .15
		var z := building.building_size.y * .5
		for index in count:
			var x := first + (float(index) + .5) * span
			var width := maxf(.1, span - .39)
			_append_box(panes, Vector3(x, (bottom + top) * .5, z + .025), Vector3(width, top - bottom, .016))
			# Thin horizontal mullions describe panes, not a reflective solid wall.
			var floors := maxi(1, int((top - bottom) / 1.65))
			for level in range(1, floors):
				var y := lerpf(bottom, top, float(level) / float(floors))
				_append_box(joints, Vector3(x, y, z + .041), Vector3(width, .032, .022))
			for y in [bottom, top]:
				_append_box(joints, Vector3(x, y, z + .041), Vector3(width, .04, .022))
			result.panes += 1
		_install(trial, "FrontGlazing", panes, glass)
		_install(trial, "GlazingMullions", joints, frame)
		result.buildings += 1
		result.draw_meshes += 2
	return result

static func _append_box(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	surface.append_from(box, 0, Transform3D(Basis.IDENTITY, center))

static func _install(parent: Node3D, label: String, surface: SurfaceTool, material: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = surface.commit()
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
