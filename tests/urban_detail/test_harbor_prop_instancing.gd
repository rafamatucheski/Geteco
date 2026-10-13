extends SceneTree
## Paridade geométrica e física dos lotes, incluindo tampa móvel e poste recuperável.

const INSTANCING := preload("res://world/urban_detail/HarborPropInstancing.gd")
const PROP := preload("res://world/urban_detail/HarborProp3D.gd")
const MANHOLE := preload("res://world/urban_detail/HarborManholeExterior3D.gd")
const ROUTE := preload("res://world/harbor_route_detail/HarborRouteProps.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const RECOVERY := preload("res://gameplay/street_physics/LampRecovery3D.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if value: return
	failures += 1
	push_error("FALHA: " + message)

func check_geometry(expected: Array[String], actual: Array[String], message: String) -> void:
	check(expected == actual, message)
	if expected == actual: return
	var missing := expected.duplicate()
	var extra: Array[String] = []
	for row in actual:
		var index := missing.find(row)
		if index >= 0: missing.remove_at(index)
		else: extra.append(row)
	print("DIFERENÇA_GEOMETRIA ", message, "\nESPERADO_AUSENTE=", missing, "\nATUAL_EXTRA=", extra)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("O teste exige --no-save.")
		quit(1)
		return
	var previous: bool = INSTANCING.enabled
	INSTANCING.enabled = false
	var old_lamps := _lamps("Chunk_Baseline")
	var old_manhole := _manhole()
	var old_grate := ROUTE.create_drain_grate()
	root.add_child(old_grate)
	INSTANCING.enabled = true
	var new_lamps := _lamps("Chunk_Instanced")
	var new_manhole := _manhole()
	var new_grate := ROUTE.create_drain_grate()
	root.add_child(new_grate)
	check_geometry(_geometry(old_lamps), _geometry(new_lamps), "Postes preservam formas, materiais, posições, rotações e escalas.")
	check(_collisions(old_lamps) == _collisions(new_lamps), "Postes preservam colisão.")
	check(new_lamps.find_children("InstancedStreetLamp*", "MultiMeshInstance3D", true, false).size() == 3, "Postes compartilham três lotes no chunk.")
	check(_visible_count(new_lamps) < _visible_count(old_lamps), "Lotes reduzem geometrias visíveis dos postes.")
	check(_light_sources(old_lamps) == _light_sources(new_lamps), "Fontes de luz, grupo e metadados permanecem iguais.")
	_test_local_lighting(old_lamps, new_lamps)
	for label in ["StreetLampPost", "StreetLampArm", "StreetLampHead"]:
		var batch := new_lamps.get_node(NodePath("Instanced" + label)) as MultiMeshInstance3D
		check(batch.cast_shadow == (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if label == "StreetLampPost" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), "Sombra correta na peça " + label)
	for amount in [0.0, 0.5, 1.0]:
		old_manhole.set_open_amount(amount)
		new_manhole.set_open_amount(amount)
		check(_geometry(old_manhole) == _geometry(new_manhole), "Bueiro preserva geometria com abertura %s." % amount)
		check(_collisions(old_manhole) == _collisions(new_manhole), "Bueiro preserva colisão com abertura %s." % amount)
	check(_visible_count(new_manhole) < _visible_count(old_manhole), "Lotes reduzem geometrias visíveis do bueiro.")
	check(_geometry(old_grate) == _geometry(new_grate), "Grade preserva as seis barras e a bacia.")
	check(_visible_count(new_grate) == 2, "Grade usa somente duas geometrias visíveis.")
	check(_shadow_count(new_grate) == 0 and _shadow_count(new_manhole) == 4, "Detalhes não projetam sombras; paredes do poço conservam as quatro sombras.")
	_test_instanced_visibility(new_lamps)
	_test_recovery(new_lamps)
	var moving_chunk := _lamps("Chunk_Reparent")
	var moving_lamp: Node3D
	for child in moving_chunk.get_children():
		if child.get_script() == PROP:
			moving_lamp = child
			break
	var moving_before := _geometry(moving_chunk)
	moving_chunk.remove_child(moving_lamp)
	moving_chunk.add_child(moving_lamp)
	check_geometry(moving_before, _geometry(moving_chunk), "Saída e reentrada do poste preservam sua geometria.")
	moving_chunk.free()
	for node in [old_lamps, old_manhole, old_grate, new_lamps, new_manhole, new_grate]: node.free()
	INSTANCING.enabled = previous
	print("INSTANCIAMENTO_HARBOR falhas=", failures)
	quit(1 if failures else 0)

func _lamps(label: String) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = label
	root.add_child(chunk)
	for index in 2:
		var lamp := PROP.new()
		lamp.configure({"kind": "lamp", "source_id": "teste"})
		lamp.position = Vector3(8.0 + index * 12.0, 0.3, 18.0)
		lamp.rotation.y = 0.3 * index
		lamp.scale = Vector3(1.0, 1.0 + 0.2 * index, 1.0)
		chunk.add_child(lamp)
	DRESSING._night_pass(chunk, {"lamps": []})
	return chunk

func _manhole() -> Node3D:
	var result := MANHOLE.new()
	result.position = Vector3(2.0, 0.0, 4.0)
	result.rotation.y = 0.4
	root.add_child(result)
	return result

func _geometry(node: Node3D) -> Array[String]:
	var result: Array[String] = []
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		if not child.is_visible_in_tree(): continue
		if child is MeshInstance3D and child.mesh != null:
			result.append(_piece(child.mesh, child.material_override, child.global_transform))
		elif child is MultiMeshInstance3D and child.multimesh != null:
			var count: int = child.multimesh.instance_count
			if child.multimesh.visible_instance_count >= 0: count = mini(count, child.multimesh.visible_instance_count)
			for index in count:
				var placement: Transform3D = child.global_transform * child.multimesh.get_instance_transform(index)
				if absf(placement.basis.determinant()) < 0.0000001: continue
				result.append(_piece(child.multimesh.mesh, child.material_override, placement))
	result.sort()
	return result

func _piece(mesh: Mesh, material: Material, placement: Transform3D) -> String:
	var appearance := str(material.resource_path) if material != null else ""
	if material is StandardMaterial3D:
		appearance = str([material.albedo_color, material.roughness, material.metallic, material.emission_enabled, material.emission])
	return str([mesh.get_class(), mesh.get_aabb(), appearance, _transform_key(placement)])

func _transform_key(value: Transform3D) -> Array:
	return [value.origin.snapped(Vector3.ONE * .001), value.basis.x.snapped(Vector3.ONE * .001), value.basis.y.snapped(Vector3.ONE * .001), value.basis.z.snapped(Vector3.ONE * .001)]

func _collisions(node: Node3D) -> Array[String]:
	var result: Array[String] = []
	for collider in node.find_children("*", "CollisionShape3D", true, false):
		var body := collider.get_parent() as CollisionObject3D
		var shape: Shape3D = collider.shape
		var dimensions: Variant = shape.size if shape is BoxShape3D else Vector2(shape.radius, shape.height)
		result.append(str([shape.get_class(), dimensions, _transform_key(collider.global_transform), collider.disabled, body.collision_layer, body.collision_mask]))
	result.sort()
	return result

func _visible_count(node: Node3D) -> int:
	var count := 0
	for item in node.find_children("*", "GeometryInstance3D", true, false):
		if item.is_visible_in_tree(): count += 1
	return count

func _shadow_count(node: Node3D) -> int:
	var count := 0
	for item in node.find_children("*", "GeometryInstance3D", true, false):
		if item.is_visible_in_tree() and item.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: count += 1
	return count

func _light_sources(node: Node3D) -> Array[String]:
	var result: Array[String] = []
	for item in node.find_children("*", "Node3D", true, false):
		if item.is_in_group("city_local_light_source"):
			result.append(str([item.get_class(), _transform_key(item.global_transform), item.get_meta("local_light", {})]))
	result.sort()
	return result

func _test_local_lighting(old_chunk: Node3D, new_chunk: Node3D) -> void:
	var lighting := preload("res://world/city_look/CityLocalLighting.gd").new()
	root.add_child(lighting)
	lighting.set_process(false)
	var focus := Vector3(14.0, 0.0, 18.0)
	var old_sources: Array[Dictionary] = []
	var new_sources: Array[Dictionary] = []
	for source in lighting.nearby_sources(focus):
		if String(source.id).begins_with("street:%s:" % old_chunk.get_instance_id()): old_sources.append(source)
		if String(source.id).begins_with("street:%s:" % new_chunk.get_instance_id()): new_sources.append(source)
	check(old_sources.size() == 2 and new_sources.size() == 2, "Dois postes de cada variante registram fontes reais pelo FRAGILE.")
	var old_rows: Array[String] = []
	var new_rows: Array[String] = []
	for source in old_sources: old_rows.append(str([source.point, source.range, source.energy, source.color]))
	for source in new_sources: new_rows.append(str([source.point, source.range, source.energy, source.color]))
	old_rows.sort()
	new_rows.sort()
	check(old_rows == new_rows, "Postes preservam posição, alcance, energia e cor das fontes locais.")
	lighting.apply_sources(new_sources, focus, 1.0)
	var active := 0
	for light in lighting.lights:
		if light.visible and light.light_energy > 0.0: active += 1
	check(active == 2, "As duas luzes dos postes instanciados acendem à noite.")
	lighting.apply_sources(new_sources, focus, 0.0)
	active = 0
	for light in lighting.lights:
		if light.visible: active += 1
	check(active == 0, "Luzes dos postes instanciados apagam durante o dia.")
	lighting.free()

func _test_instanced_visibility(chunk: Node3D) -> void:
	var lamp: Node3D
	for child in chunk.get_children():
		if child.get_script() == PROP:
			lamp = child
			break
	var before := _geometry(chunk)
	var expected_hidden: Array[String] = before.duplicate()
	for part in lamp._lamp_originals:
		expected_hidden.erase(_piece(part.mesh, part.material_override, part.global_transform))
	check(not lamp._lamp_parts.is_empty(), "Visibilidade é verificada antes de desagrupar o poste.")
	lamp.hide()
	check_geometry(expected_hidden, _geometry(chunk), "Ocultar um poste remove suas três peças e preserva o vizinho.")
	lamp.show()
	check_geometry(before, _geometry(chunk), "Mostrar o poste restaura suas instâncias sem duplicar peças.")
	check(not lamp._lamp_parts.is_empty(), "Ocultar e mostrar conserva o poste no lote.")

func _test_recovery(chunk: Node3D) -> void:
	var lamp: Node3D
	for child in chunk.get_children():
		if child.get_script() == PROP:
			lamp = child
			break
	var before := _geometry(chunk)
	var item := {"root": weakref(lamp), "kind": "lamp", "state": "standing"}
	RECOVERY.capture(item)
	check(lamp._lamp_parts.is_empty(), "Captura restaura peças individuais antes de uma fratura.")
	check_geometry(before, _geometry(chunk), "Desagrupar um poste preserva a geometria do chunk.")
	FRAGILE._kill_light(item)
	check((lamp.get_node("StreetLampHead") as MeshInstance3D).material_override != preload("res://world/city_look/CityLookMaterials.gd").lamp_head(), "Impacto apaga o material luminoso do poste individual.")
	# Mesmo clone e particionamento usados no impacto forte, antes de lançar os corpos.
	var copy := lamp.duplicate(0) as Node3D
	copy.set_script(null)
	var shards := preload("res://gameplay/street_physics/PropFracture3D.gd").split(copy, 1)
	check(shards.size() == 3, "Poste desagrupado continua produzindo os três fragmentos do impacto forte.")
	for shard in shards: shard.free()
	copy.free()
	lamp.rotation.z += 0.4
	lamp.visible = false
	RECOVERY.restore(item)
	check_geometry(before, _geometry(chunk), "Recuperação restaura aparência e transform sem duplicar instâncias.")
	var other: Node3D
	for child in chunk.get_children():
		if child.get_script() == PROP and child != lamp: other = child
	other.position.x += 1.0
	other.force_update_transform()
	check(other._lamp_parts.is_empty(), "Movimento individual libera o poste do lote sem polling.")
