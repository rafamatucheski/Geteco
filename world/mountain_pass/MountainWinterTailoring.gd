extends RefCounted
## Preserve residents' identity and routine joints; use Dante's native tapered
## geometry for sleeves, trousers and boots instead of rectangular limbs.
const DANTE = preload("res://scripts/player/DanteVisualAdapter.gd")

static func refine(model: Node3D) -> void:
	# Replacing sleeves also replaces their joints, including after clothing changes.
	model.elbows.clear()
	var cloth := DANTE._make_mat(model.coat_color, .86)
	var pants := DANTE._make_mat(Color("293846"), .9)
	var boots := DANTE._make_mat(Color("242a30"), .7)
	for side in 2:
		var leg: Node3D = model.limbs[side * 2]
		var knee: Node3D = model.knees[side]
		for child in leg.get_children():
			if child != knee: child.free()
		for child in knee.get_children(): child.free()
		leg.add_child(DANTE._make_tapered_limb(.091, .072, .35, pants, Vector3(0,-.175,0)))
		knee.add_child(DANTE._make_ellipsoid(Vector3(.15,.15,.16), pants, Vector3.ZERO))
		knee.add_child(DANTE._make_tapered_limb(.073, .062, .30, pants, Vector3(0,-.15,0)))
		knee.add_child(DANTE._make_ellipsoid(Vector3(.16,.17,.28), boots, Vector3(0,-.34,.04)))
		knee.add_child(DANTE._make_box(Vector3(.16,.035,.28), boots, Vector3(0,-.412,.04)))
		var arm: Node3D = model.limbs[side * 2 + 1]
		for child in arm.get_children(): child.free()
		arm.add_child(DANTE._make_ellipsoid(Vector3(.19,.17,.20), cloth, Vector3(0,-.035,0)))
		arm.add_child(DANTE._make_tapered_limb(.083,.067,.25,cloth,Vector3(0,-.125,0)))
		var elbow := Node3D.new()
		elbow.name = "Elbow"
		elbow.position.y = -.25
		arm.add_child(elbow)
		model.elbows.append(elbow)
		elbow.add_child(DANTE._make_ellipsoid(Vector3(.14,.13,.15),cloth,Vector3.ZERO))
		elbow.add_child(DANTE._make_tapered_limb(.068,.051,.21,cloth,Vector3(0,-.105,0)))
		elbow.add_child(DANTE._make_ellipsoid(Vector3(.105,.12,.13),boots,Vector3(0,-.255,.015)))
	var head := model.pose_root.get_node("Head") as Node3D
	head.scale = Vector3.ONE * .87
	# Same adult head/body ratio as Dante, with the residents' own faces/hair.
	var coat := model.pose_root.get_node("Coat") as MeshInstance3D
	for child in model.pose_root.get_children():
		if child == head or child == coat or child == model.breath or child in model.limbs: continue
		child.free()
	var body := DANTE._make_loft([
		Vector4(-.31,.18,.12,0), Vector4(-.10,.17,.13,0),
		Vector4(.12,.215,.14,0), Vector4(.27,.22,.125,0),
		Vector4(.34,.095,.08,0)],cloth)
	coat.mesh = body.mesh
	coat.material_override = cloth
	coat.scale = Vector3.ONE
	body.free()
	var scarf := DANTE._make_mat(model.coat_color.lightened(.22),.94)
	model.pose_root.add_child(DANTE._make_tapered_limb(.082,.082,.15,scarf,Vector3(0,1.46,0)))
	model.pose_root.add_child(DANTE._make_ellipsoid(Vector3(.27,.075,.22),scarf,Vector3(0,1.43,0)))
	model.pose_root.add_child(DANTE._make_box(Vector3(.06,.24,.025),scarf,Vector3(.08,1.29,.145)))
	var trim := DANTE._make_mat(Color("9da9a9"),.72)
	model.pose_root.add_child(DANTE._make_box(Vector3(.012,.46,.012),trim,Vector3(0,1.08,.139)))
	for side in [-1,1]:
		model.pose_root.add_child(DANTE._make_box(Vector3(.10,.10,.014),cloth,Vector3(side*.105,.95,.128)))
	if model.role in ["ranger","logger"]:
		model.pose_root.add_child(DANTE._make_box(Vector3(.062,.11,.04),boots,Vector3(-.13,1.31,.147)))
