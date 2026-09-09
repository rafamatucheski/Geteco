extends "res://world/mountain_pass/MountainStaticModelView.gd"

const BOARD_INTERACTION := Vector3(5.25, 0, 3.55)

const ART := preload("res://world/harbor/art/monaliza_workshop/MonalizaWorkshopProps3D.gd")

func build_workshop() -> void:
	build_view(ART, 14.0, 20.0, Vector3(1.2, 0.8, 0.3), Vector3(0, 24, 12))
	for obstacle: AABB in model.get_obstacle_bounds():
		if obstacle.position.y < 1.5:
			add_solid(Rect2(Vector2(obstacle.position.x, obstacle.position.z), Vector2(obstacle.size.x, obstacle.size.z)), "WorkshopObstacle")
	# Cut away foreground masonry and overhead fittings for the gameplay camera.
	# Physical footprints stay intact; actors cannot walk through these walls.
	for child in model.get_children():
		if child is MeshInstance3D:
			if child.mesh is BoxMesh and child.position.y > 3.3 and child.mesh.size.z > 3.0:
				child.hide() # Ceiling fluorescent strips obscure the bay in this camera.
			elif child.position.z > 2.2 and child.position.y > 1.0:
				child.transparency = 0.88
			elif child.position.y > 2.6:
				child.transparency = 0.8
	var board := MeshInstance3D.new()
	board.name = "MissionBoard3D"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.15, 1.05, 0.1)
	board.mesh = mesh
	board.position = Vector3(5.85, 0.95, 4.15)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("805b31")
	mat.roughness = 0.9
	board.material_override = mat
	model.add_child(board)
	for x in [5.4, 6.3]:
		var leg := MeshInstance3D.new()
		var leg_mesh := BoxMesh.new()
		leg_mesh.size = Vector3(0.06, 1.1, 0.06)
		leg.mesh = leg_mesh
		leg.position = Vector3(x, 0.55, 4.15)
		leg.material_override = mat
		model.add_child(leg)
	add_solid(Rect2(5.25, 4.08, 1.2, 0.15), "MissionBoardFeet")

	var title := Label3D.new()
	title.text = "MISSÕES"
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.font_size = 36
	title.pixel_size = 0.006
	title.position = Vector3(5.85, 1.3, 4.215)
	title.modulate = Color("ffdc80")
	model.add_child(title)
	for i in 3:
		var paper := MeshInstance3D.new()
		var page := BoxMesh.new()
		page.size = Vector3(0.26, 0.4, 0.012)
		paper.mesh = page
		paper.position = Vector3(5.5 + i * 0.35, 0.87, 4.215)
		var page_mat := StandardMaterial3D.new()
		page_mat.albedo_color = Color("f0e6c9")
		paper.material_override = page_mat
		model.add_child(paper)
