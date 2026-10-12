extends SceneTree
## Verify the visible hand geometry, not merely the bone's nominal axis.
const BODY = preload("res://assets/CivilianModel.gd")
const CATALOG = preload("res://assets/civilians/CivilianBodyCatalog.gd")
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func run():
	for entry in CATALOG.ENTRIES:
		var model = BODY.new()
		model.body_source = CATALOG.FOLDER + entry.file
		model.appearance_locked = true
		model.lod_enabled = false
		root.add_child(model)
		model.set_process(false)
		var rig = model._meshy
		assert(model.palm_grip_enabled, "Pedestrians need calibrated anatomical hand frames")
		assert(model.mesh_node.mesh.get_surface_count() == 2, "Body and authored hands must both exist")
		var arrays: Array = model.mesh_node.mesh.surface_get_arrays(1)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var influences := bones.size() / vertices.size()
		for side in 2:
			var bone: int = rig._hand_bones[side]
			var centroid := Vector3.ZERO
			var count := 0
			for vertex in vertices.size():
				for influence in int(influences):
					var index := vertex * int(influences) + influence
					if bones[index] == bone and weights[index] > .8:
						centroid += vertices[vertex]
						count += 1
			assert(count > 0, "Visible hand vertices must exist")
			centroid /= count
			var rest: Transform3D = model.skeleton.get_bone_global_rest(bone)
			var local_direction := rest.basis.inverse() * (centroid - rest.origin)
			for swing in [0.0, -.65, .65]:
				model.upper_arms[side].rotation.x = swing
				model.forearms[side].rotation.x = -.3
				rig.sync()
				var pose: Transform3D = model.skeleton.get_bone_global_pose(bone)
				var visible_direction: Vector3 = (model.skeleton.global_basis * pose.basis * local_direction).normalized()
				var forearm_down: Vector3 = -model.forearms[side].global_basis.y.normalized()
				checks += 1
				if visible_direction.dot(forearm_down) < .98:
					failures += 1
					print("HAND_REST FAIL ", entry.id, " side=", side, " swing=", swing, " dot=", visible_direction.dot(forearm_down))
		model.free()
	print("PEDESTRIAN_HAND_REST checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
