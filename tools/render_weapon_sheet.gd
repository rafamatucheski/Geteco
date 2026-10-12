extends SceneTree
## Folha de contato das armas do arsenal (vista lateral + 3/4) para revisão visual.
## Uso (sem --headless, precisa de renderização real):
##   Godot --path . --script res://tools/render_weapon_sheet.gd -- [--out=evidence/weapons/sheet.png] [--ids=a,b]
const ARSENAL := preload("res://gameplay/ArsenalWeapon3D.gd")
const ALL_IDS := ["pistol", "magnum", "smg", "shotgun", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower", "grenade", "knife", "axe", "bat", "knuckles"]
const CELL := Vector2i(560, 300)
const COLS := 3

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var out := "evidence/weapons/sheet.png"
	var ids: Array = ALL_IDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--ids="): ids = arg.trim_prefix("--ids=").split(",")
	await _render_cells(ids, out)
	quit(0)

func _render_cells(ids: Array, out: String) -> void:
	var rows := ceili(ids.size() / float(COLS))
	var sheet := Image.create(CELL.x * COLS * 2, CELL.y * rows, false, Image.FORMAT_RGB8)
	sheet.fill(Color("5b6066"))
	for i in ids.size():
		for view in 2:
			var vp := SubViewport.new()
			vp.size = CELL
			vp.own_world_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(vp)
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.background_color = Color("5b6066")
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.environment.ambient_light_color = Color("aab3bb")
			env.environment.ambient_light_energy = 0.7
			vp.add_child(env)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-40, -35, 0)
			sun.light_energy = 1.4
			vp.add_child(sun)
			var weapon := Node3D.new()
			vp.add_child(weapon)
			ARSENAL.build(weapon, ids[i])
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.near = 0.05
			cam.far = 20.0
			vp.add_child(cam)
			var box := _bounds(weapon)
			var center := box.get_center()
			var aspect := CELL.x / float(CELL.y)
			# Enquadra pela extensão real da arma: lateral olha por +X (cano para -Z, à esquerda).
			var along := box.size.z if view == 0 else box.size.length() * 0.8
			var up := box.size.y if view == 0 else box.size.length() * 0.6
			cam.size = maxf(up * 1.25, along * 1.25 / aspect)
			if view == 0:
				cam.position = center + Vector3(3, 0, 0)
				cam.look_at(center)
			else:
				cam.position = center + Vector3(-2.0, 1.2, -2.0)
				cam.look_at(center)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, CELL), Vector2i(((i % COLS) * 2 + view) * CELL.x, (i / COLS) * CELL.y))
			vp.queue_free()
			await process_frame
	var path := ProjectSettings.globalize_path("res://" + out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("salvo: ", path, " erro=", sheet.save_png(path))

static func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		var local := node.global_transform.affine_inverse() * m.global_transform
		var part := local * m.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
