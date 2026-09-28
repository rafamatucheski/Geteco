extends "res://tests/test_police_walkin.gd"
const DATA := preload("res://world/editing/WorldEditData.gd")
func _process(_delta: float) -> bool:
	# The current camera maps move_up diagonally in world space. Drive the real
	# CharacterBody along the doorway normal, independent of camera mapping.
	if is_instance_valid(world) and is_instance_valid(world.player):
		world.player.controlled_automatically = true
		world.player.speed = 3.5
		var direction := Vector3.FORWARD
		if world.session != null and world.session.state.place_id.is_empty(): direction = world.session.weapon_shop_entrance._inward("harbor_police")
		world.player.automatic_direction = direction if Input.is_action_pressed("move_up") else Vector3.BACK if Input.is_action_pressed("move_down") else Vector3.ZERO
	return false
func check(ok: bool, label: String) -> void:
	if not ok and is_instance_valid(world):
		print("SERVICE_DIAGNOSTIC player=",world.player.position," velocity=",world.player.velocity," place=",world.session.state.place_id," door=",world.session.weapon_shop_entrance._door_position("harbor_police",PLACES.get_definition("harbor_police")))
	super.check(ok,label)
func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	var folder := "res://evidence/service-editor-20260926/"+("before" if "--baseline" in OS.get_cmdline_user_args() else "after")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder+"/"+label+".png") == OK,"capture "+label)
func _initialize() -> void:
	var region := preload("res://world/regions/NativeRegion.gd").build_region("harbor")
	region.prepare_data()
	var catalog := DATA.catalog(region)
	var document := DATA.empty_document()
	for id in preload("res://world/editing/WorldServiceBuildings.gd").PLACES:
		var entry: Dictionary = catalog["building/"+id]
		check(not entry.locked and entry.service_building,"Editable service facade: "+id)
	check(catalog["building/Garage"].locked,"Maciota remains protected")
	var row: Dictionary = catalog["building/Police"].duplicate(true)
	row.position[0] += 2.0
	row.size = [row.size[0]*1.2,row.size[1]*1.2]
	row.height *= 1.25
	row.color = "728496"
	if "--rotated" in OS.get_cmdline_user_args():
		# Rotating in place would put the entrance over the existing sewer hatch.
		row.rotation = 25.0
		row.position = [5.0,95.0]
	check(DATA.validate_entity(row).is_empty(),"Police move, resize, height and color validate")
	if "--baseline" not in OS.get_cmdline_user_args(): document.regions.harbor[row.id] = row
	Engine.set_meta("geteco_world_edit_document",document)
	region.free()
	run.call_deferred()
