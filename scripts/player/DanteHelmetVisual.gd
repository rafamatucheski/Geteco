extends RefCounted
## A closed helmet is an alternative head presentation. Keep the authored head
## transform and every face/hair mesh intact; never combine them into the shell.
const ADAPTER = preload("res://scripts/player/DanteVisualAdapter.gd")

static func attach(head: Node3D) -> Node3D:
	var existing := head.get_node_or_null("MotorcycleHelmet") as Node3D
	if existing: return existing
	var helmet := Node3D.new()
	helmet.name = "MotorcycleHelmet"
	head.add_child(helmet)
	var shell := ADAPTER._make_mat(Color("e9e7e2"),.27,.22)
	var trim := ADAPTER._make_mat(Color("191e26"),.65)
	var visor := ADAPTER._make_mat(Color("152434"),.16,.45)
	helmet.add_child(ADAPTER._make_ellipsoid(Vector3(.325,.395,.352),shell,Vector3(0,.044,.018)))
	helmet.add_child(ADAPTER._make_ellipsoid(Vector3(.292,.162,.112),visor,Vector3(0,.052,-.138)))
	helmet.add_child(ADAPTER._make_box(Vector3(.23,.060,.064),shell,Vector3(0,-.088,-.146)))
	helmet.add_child(ADAPTER._make_box(Vector3(.105,.014,.008),trim,Vector3(0,-.085,-.180)))
	for side in [-1.0,1.0]:
		helmet.add_child(ADAPTER._make_ellipsoid(Vector3(.014,.038,.038),trim,Vector3(side*.158,.044,-.025)))
	helmet.hide()
	return helmet

static func apply(head: Node3D, worn: bool, action: String = "", progress: float = 0.0) -> void:
	var helmet := attach(head)
	var covering := worn
	var show_helmet := worn
	var offset := Vector3.ZERO
	if action == "put_on":
		show_helmet = true
		covering = progress >= .68
		offset = Vector3(0,-.28,-.22).lerp(Vector3(0,.24,-.08),smoothstep(0,.35,progress)) if progress < .35 else Vector3(0,.24,-.08).lerp(Vector3.ZERO,smoothstep(.35,.80,progress))
	elif action == "take_off":
		show_helmet = true
		covering = progress < .30
		offset = Vector3.ZERO.lerp(Vector3(0,.24,-.08),smoothstep(.15,.55,progress)) if progress < .55 else Vector3(0,.24,-.08).lerp(Vector3(-.13,-.28,-.18),smoothstep(.55,.92,progress))
	for child in head.get_children():
		if child is Node3D and child != helmet:
			if not child.has_meta("helmet_rest_visible"): child.set_meta("helmet_rest_visible",child.visible)
			child.visible = bool(child.get_meta("helmet_rest_visible")) and not covering
	var parent: Node = head.get_parent()
	if is_instance_valid(parent):
		var outfit_head := parent.find_child("MeshyOutfitHead", true, false) as Node3D
		if is_instance_valid(outfit_head):
			if not outfit_head.has_meta("helmet_rest_visible"): outfit_head.set_meta("helmet_rest_visible", outfit_head.visible)
			outfit_head.visible = bool(outfit_head.get_meta("helmet_rest_visible")) and not covering
	helmet.visible = show_helmet
	helmet.position = offset
