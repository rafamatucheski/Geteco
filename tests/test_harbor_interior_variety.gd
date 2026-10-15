extends SceneTree
## Variedade dos interiores do porto: mede, sem renderizar, quantas plantas,
## conjuntos de móveis, paletas, objetos de vida e posturas de estação distintas
## existem nos andares habitados, e se o mesmo andar se repete idêntico entre
## montagens (determinismo para streaming/revisita).
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const CONTENT = preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const DRESSING = preload("res://world/places/harbor_buildings/HarborBuildingDressing.gd")
var failures: Array[String] = []
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("FALHA " + label)

func _initialize() -> void:
	var dump := "--dump" in OS.get_cmdline_user_args()
	var floors := 0
	var layouts := {}
	var furniture_sets := {}
	var palettes := {}
	var decor_sets := {}
	var station_poses := {}
	var activities := {}
	var by_program := {}
	var program_layouts := {}
	var repeated := 0
	for definition in CATALOG.definitions():
		for floor_index in int(definition.floor_count):
			floors += 1
			var model := Node3D.new()
			var spec: Dictionary = DRESSING.populate(model, definition, floor_index)
			var signature := _signature(model)
			# Determinismo: a segunda montagem do mesmo andar é idêntica.
			var again := Node3D.new()
			DRESSING.populate(again, definition, floor_index)
			if _signature(again).hash != signature.hash: repeated += 1
			again.free()
			model.free()
			var program := str(spec.program)
			var layout := program + "|" + str(spec.get("layout", "")) + "|" + str(signature.solids)
			layouts[layout] = true
			furniture_sets[signature.solids] = true
			palettes[JSON.stringify(spec.palette)] = true
			decor_sets[str(signature.decor)] = true
			by_program[program] = int(by_program.get(program, 0)) + 1
			if not program_layouts.has(program): program_layouts[program] = {}
			program_layouts[program][signature.hash] = true
			for station in spec.occupants:
				var point: Vector3 = station.position
				station_poses["%.1f,%.1f,%.2f" % [point.x / maxf(1.0, spec.size.x), point.z / maxf(1.0, spec.size.y), float(station.yaw)]] = true
				var activity := str(station.get("activity", ""))
				activities[activity] = int(activities.get(activity, 0)) + 1
			if dump:
				var acts := []
				for station in spec.occupants: acts.append("%s@(%.1f,%.1f)" % [station.activity, station.position.x, station.position.z])
				print("ANDAR %s-%d %s fam=%s compact=%s layout=%s solids=%s decor=%s ocup=%s" % [definition.id, floor_index, program, spec.family, spec.compact, spec.get("layout", "-"), signature.solids, signature.decor, acts])
	var distinct_hashes := 0
	for program in program_layouts: distinct_hashes += program_layouts[program].size()
	print("INTERIOR_VARIETY andares=", floors, " plantas=", layouts.size(), " conjuntos_moveis=", furniture_sets.size(),
		" paletas=", palettes.size(), " decor=", decor_sets.size(), " posturas_estacao=", station_poses.size(),
		" atividades=", activities, " montagens_distintas=", distinct_hashes, " nao_deterministicos=", repeated)
	print("INTERIOR_VARIETY programas=", by_program)
	check(repeated == 0, "mesmo prédio/andar monta igual entre visitas")
	# Critérios do rework de variedade (15/10): quase nenhum andar idêntico a outro
	# e atividades além de ler/escrever/consertar parado.
	check(distinct_hashes >= floors * 9 / 10, "andares visualmente distintos %d/%d" % [distinct_hashes, floors])
	check(palettes.size() >= 12, "paletas variando por prédio: %d" % palettes.size())
	check(activities.size() >= 8, "atividades distintas nas estações: %d" % activities.size())
	print("INTERIOR_VARIETY checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _signature(model: Node3D) -> Dictionary:
	var solids := PackedStringArray()
	var decor := PackedStringArray()
	var parts := PackedStringArray()
	for child in model.get_children():
		if child.has_meta("dressing_envelope"):
			var id := str(child.get_meta("interior_solid_id")).trim_prefix("Dressing_")
			# Remove sufixos numéricos para contar o tipo de móvel, não a instância.
			var kind := id.rstrip("0123456789").split("_")[-1] if id.begins_with("CompactUse") else id.rstrip("0123456789")
			solids.append(kind)
			parts.append(id + str(child.position.snapped(Vector3.ONE * .05)) + str(child.mesh.size.snapped(Vector3.ONE * .05)))
		elif child is MultiMeshInstance3D:
			# O nome do nó colide entre caixa e cilindro da mesma cor e ganha
			# um serial global; a assinatura usa malha e material.
			parts.append(child.multimesh.mesh.get_class() + child.material_override.albedo_color.to_html() + ":" + str(child.multimesh.instance_count))
	for key in model.get_meta("dressing_decor", []): decor.append(str(key))
	solids.sort()
	parts.sort()
	decor.sort()
	return {"solids":",".join(solids), "decor":",".join(decor), "hash":hash(",".join(parts))}
