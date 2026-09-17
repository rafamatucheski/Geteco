extends SceneTree
## GETECO-PERF: pré-renderiza os modelos 3D do Porto Sul (HarborPortModelView)
## para textura PNG + dados de projeção analítica, eliminando o SubViewport/
## Camera3D/malha 3D do caminho de carregamento em tempo real.
##
## Por quê: HarborSouthPort._build_port_models()/_build_buildings() criam 37
## SubViewports (containers, navio, wheelhouse, 3 gruas, 3 cargas suspensas,
## paletes, 5 prédios) -- geometria 100% determinística dado (kind, tamanho,
## variant), medida pela rodada GETECO-PERF-03A como o maior bloco indivisível
## do world_build (22-28s). Nada disso depende de estado de save ou RNG.
##
## A projeção usada em tempo real (project_floor/project_point, consumida por
## HarborSouthPort para os pontos de içamento da grua e a colisão dos prédios)
## é uma câmera ortográfica FIXA -- unproject_position() é uma transformação
## afim determinística. A fórmula analítica abaixo foi verificada contra a
## unproject_position() real (erro máximo 0,0003px em 5 kinds/vários pontos,
## incluindo hoist_start/hoist_end) antes de ser usada aqui; ver
## HarborPortModelBaked.gd para a mesma fórmula em tempo de execução.
##
## Uso: Godot..._console.exe --path . --script res://tools/bake_south_port_models.gd
## Saída: world/harbor/baked_port_models/<label>.png (imagem) +
## world/harbor/HarborPortModelBakeData.gd (dados, sobrescrito por completo).

const L := preload("res://world/harbor/HarborSouthPortLayout.gd")
const MODEL := preload("res://world/harbor/HarborPortModel3D.gd")
const OUT_DIR := "res://world/harbor/baked_port_models"
const PPM := 20.0
const FLOOR_Y := .8

var _entries: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("bake_south_port_models requer renderização real (nunca headless)")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var root_node := Node2D.new()
	root.add_child(root_node)

	# Réplica exata das definições de HarborSouthPort._build_buildings().
	var building_defs := [
		{"rect": L.WAREHOUSES[0], "kind": "warehouse"},
		{"rect": L.WAREHOUSES[1], "kind": "warehouse"},
		{"rect": Rect2(3400, 4050, 210, 180), "kind": "office"},
		{"rect": Rect2(3370, 5130, 200, 270), "kind": "warehouse"},
		{"rect": Rect2(3420, 3390, 85, 90), "kind": "office"},
	]
	for i in building_defs.size():
		var item: Dictionary = building_defs[i]
		await _bake(root_node, item.kind, item.rect, i, "PortBuilding%d" % i)

	# Réplica exata das definições de HarborSouthPort._build_port_models().
	var containers := L.containers()
	for i in containers.size():
		await _bake(root_node, "containers", containers[i], i, "CargoStack3D%02d" % i)
	await _bake(root_node, "ship_cargo", L.SHIP_CARGO, 0, "SantaMareCargo3D")
	await _bake(root_node, "office", L.WHEELHOUSE, 2, "SantaMareWheelhouse3D")
	for i in L.CRANES.size():
		var base: Vector2 = L.CRANES[i]
		await _bake(root_node, "crane", Rect2(base + Vector2(-35, -360), Vector2(240, 410)), i, "QuaysideCrane3D%d" % i)
		await _bake(root_node, "transfer_cargo", Rect2(base, Vector2(96, 42)), i + 1, "HoistedCargo3D%d" % i)
	for i in 6:
		var rect := Rect2(3970 + (i % 3) * 550, 4900 if i < 3 else 5420, 130, 55)
		await _bake(root_node, "supplies", rect, i, "PalletsAndDrums3D%d" % i)

	_write_data_file()
	print("BAKE_SOUTH_PORT_DONE entries=%d" % _entries.size())
	quit(0)

func _bake(root_node: Node2D, kind: String, rect: Rect2, variant: int, label: String) -> void:
	var viewport_3d := SubViewport.new()
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	root_node.add_child(viewport_3d)
	var model := MODEL.new()
	viewport_3d.add_child(model)
	model.build(kind, rect.size.x / PPM, rect.size.y / PPM / FLOOR_Y, variant)
	var projected_height: float = rect.size.y + model.height * .6 * PPM
	viewport_3d.size = Vector2i(clampi(ceili(rect.size.x + 50), 128, 1536), clampi(ceili(projected_height + 70), 128, 1024))
	var camera_3d := Camera3D.new()
	camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.keep_aspect = Camera3D.KEEP_WIDTH
	camera_3d.size = float(viewport_3d.size.x) / PPM
	viewport_3d.add_child(camera_3d)
	var target := Vector3(0, model.height * .5, 0)
	camera_3d.position = target + Vector3(0, 24, 18)
	camera_3d.look_at(target)
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -60, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b3c6d0")
	env.environment.ambient_light_energy = .35
	viewport_3d.add_child(env)
	# UPDATE_ONCE só desenha no próximo quadro em que o viewport está visível;
	# vários quadros de folga garantem que o render (incluindo sombra) assentou
	# antes de capturar a imagem -- isto roda uma vez offline, custo não importa.
	for i in 6: await process_frame

	var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	var sprite_scale := Vector2.ONE * PPM / metre
	var sprite_position := -(camera_3d.unproject_position(Vector3.ZERO) - Vector2(viewport_3d.size) * .5) * sprite_scale

	var image := viewport_3d.get_texture().get_image()
	var png_path := OUT_DIR.path_join(label + ".png")
	image.save_png(png_path)

	var entry := {
		"label": label,
		"texture": png_path,
		"sprite_scale": sprite_scale,
		"sprite_position": sprite_position,
		"camera_position": camera_3d.position,
		"camera_target": target,
		"camera_size": camera_3d.size,
		"viewport_size": viewport_3d.size,
		"height": model.height,
		"hoist_start": model.hoist_start,
		"hoist_end": model.hoist_end,
		"solid_floor_bounds": model.solid_floor_bounds.duplicate(),
		"kind": kind,
		"footprint": rect.size,
	}
	_entries.append(entry)
	print("BAKED %s kind=%s variant=%d viewport=%s" % [label, kind, variant, viewport_3d.size])
	viewport_3d.queue_free()

func _fmt_vector2(v: Vector2) -> String:
	return "Vector2(%s, %s)" % [v.x, v.y]

func _fmt_vector2i(v: Vector2i) -> String:
	return "Vector2i(%d, %d)" % [v.x, v.y]

func _fmt_vector3(v: Vector3) -> String:
	return "Vector3(%s, %s, %s)" % [v.x, v.y, v.z]

func _fmt_rect2(r: Rect2) -> String:
	return "Rect2(%s, %s, %s, %s)" % [r.position.x, r.position.y, r.size.x, r.size.y]

func _write_data_file() -> void:
	var lines := PackedStringArray()
	lines.append("extends RefCounted")
	lines.append("## GERADO por tools/bake_south_port_models.gd -- não editar à mão.")
	lines.append("## Dados de projeção + geometria dos 37 modelos 3D pré-renderizados do")
	lines.append("## Porto Sul (ver HarborPortModelBaked.gd para como isto é consumido).")
	lines.append("const ENTRIES := {")
	for entry in _entries:
		lines.append('\t"%s": {' % entry.label)
		lines.append('\t\t"texture": "%s",' % entry.texture)
		lines.append('\t\t"sprite_scale": %s,' % _fmt_vector2(entry.sprite_scale))
		lines.append('\t\t"sprite_position": %s,' % _fmt_vector2(entry.sprite_position))
		lines.append('\t\t"camera_position": %s,' % _fmt_vector3(entry.camera_position))
		lines.append('\t\t"camera_target": %s,' % _fmt_vector3(entry.camera_target))
		lines.append('\t\t"camera_size": %s,' % entry.camera_size)
		lines.append('\t\t"viewport_size": %s,' % _fmt_vector2i(entry.viewport_size))
		lines.append('\t\t"height": %s,' % entry.height)
		lines.append('\t\t"hoist_start": %s,' % _fmt_vector3(entry.hoist_start))
		lines.append('\t\t"hoist_end": %s,' % _fmt_vector3(entry.hoist_end))
		var bounds_parts := PackedStringArray()
		for id in entry.solid_floor_bounds:
			var rect: Rect2 = entry.solid_floor_bounds[id]
			bounds_parts.append('&"%s": %s' % [String(id), _fmt_rect2(rect)])
		lines.append('\t\t"solid_floor_bounds": {%s},' % ", ".join(bounds_parts))
		lines.append('\t\t"kind": "%s",' % entry.kind)
		lines.append('\t\t"footprint": %s,' % _fmt_vector2(entry.footprint))
		lines.append('\t},')
	lines.append("}")
	var f := FileAccess.open(ProjectSettings.globalize_path("res://world/harbor/HarborPortModelBakeData.gd"), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
