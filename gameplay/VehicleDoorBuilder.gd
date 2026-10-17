extends RefCounted
## Recorta a porta do motorista do casco assado de QUALQUER carro da frota.
##
## Os modelos de `assets/fleet` são fotografias achatadas: a porta é só um pedaço da lataria,
## sem dobradiça. A folha "substituta" que existia antes era uma placa solta que aparecia ao
## lado da porta fechada (que continuava no casco): a porta parecia voar e o vão nunca abria.
## Aqui a folha é feita dos MESMOS triângulos da lataria e do vidro, recortados pelo vão da
## porta (`VehicleDoorSpecs`), e o casco perde essa região. Fechada, nada muda na imagem;
## aberta, há um vão real por onde o corpo entra.
##
## Só roda no veículo que está sendo embarcado (ou cujo motorista sai), como o cupê: o
## trânsito continua com as malhas compartilhadas.

const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const SPECS := preload("res://data/catalogs/VehicleDoorSpecs.gd")

const X := 0
const Y := 1
const Z := 2
## Só lataria voltada para o lado entra no recorte; tetos e assoalhos do casco ficam.
const SIDE_FACING := .35
## Espessura da folha: o cartão interno fica este tanto para dentro da lataria.
const THICKNESS := .075
## Histograma da última medição da lataria (cm → área), para o teste de frota explicar uma
## medição estranha.
static var last_bins: Dictionary = {}

## Resultado de `cut`. `leaf[side]` é {material: {pos, nrm, uv, col, key}}; `inner[side]` o
## mesmo para o cartão interno; `skin` é o x medido da lataria (positivo).
class Result:
	var leaf := {-1: {}, 1: {}}
	var inner := {-1: {}, 1: {}}
	var skin := 0.0
	var moved_parts: Array[MeshInstance3D] = []
	var cut_parts := 0
	var triangles := 0
	## Trocas de malha pendentes: [peça, malha original, malha recortada]. O recorte é calculado
	## aos poucos (vários quadros) e só aplicado de uma vez, senão o carro apareceria com a
	## porta faltando no meio do trabalho.
	var swaps: Array = []

	## Aplica o recorte à cena. Peça cuja malha mudou no meio do caminho (outro módulo mexeu)
	## fica como está: melhor uma folha duplicada que o teto do outro módulo desfeito.
	func apply() -> void:
		for swap in swaps:
			var part: MeshInstance3D = swap[0]
			if is_instance_valid(part) and (part.mesh == swap[1] or (swap.size()>3 and part.get_meta("body_dents_rest_mesh",null)==swap[3])): part.mesh = swap[2]
		for part in moved_parts:
			if is_instance_valid(part): part.visible = false
		swaps = []

## Trabalho de recorte em andamento (`begin` / `step`). Serve para preparar a porta enquanto o
## jogador ainda caminha até o carro, sem um pico de quadro no primeiro F.
class Job:
	var spec: Dictionary
	var result := Result.new()
	var parts: Array[MeshInstance3D] = []
	var transforms: Array[Transform3D] = []
	var index := 0
	var finished := false
	var work: Dictionary = {}
	var triangles_processed := 0

static func _parts(visual: Node3D) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null or part.mesh.get_surface_count() == 0: continue
		if part.get_meta("door_cut_exempt", false): continue
		if part.has_meta("wheel_center") or part.has_meta("heavy_detail") or not part.visible: continue
		# Interior e teto recortado são do módulo do piloto (VehicleInterior); a folha nunca os leva.
		if part.name in ["TaxiLivery", "Interior", "RoofCut"] or part.get_parent() is Skeleton3D: continue
		parts.append(part)
	return parts

static func _transforms(visual: Node3D, parts: Array[MeshInstance3D]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var to_visual := visual.global_transform.affine_inverse() if visual.is_inside_tree() else Transform3D.IDENTITY
	for part in parts: result.append((to_visual * part.global_transform) if visual.is_inside_tree() else part.transform)
	return result

## Só mede a lataria (não altera nada): o teste de portas confere a tabela contra isto.
static func measure(visual: Node3D, spec: Dictionary) -> float:
	var parts := _parts(visual)
	return _measure_skin(parts, _transforms(visual, parts), spec)

static func begin(visual: Node3D, spec: Dictionary, forced_skin := -1.0) -> Job:
	var job := Job.new()
	job.spec = spec
	job.parts = _parts(visual)
	job.transforms = _transforms(visual, job.parts)
	job.result.skin = forced_skin if forced_skin >= 0.0 else _measure_skin(job.parts, job.transforms, spec)
	return job

## Budget checks run between setup, <=16-triangle batches and upload stages.
## Native surface upload remains indivisible; this is a soft time budget.
const TRIANGLES_PER_BATCH := 16
static func step(job: Job, budget_usec: int) -> bool:
	if job.finished: return true
	var deadline := Time.get_ticks_usec() + budget_usec
	while job.index < job.parts.size():
		if job.work.is_empty():
			var part := job.parts[job.index]
			if is_instance_valid(part) and part.mesh != null:
				job.work = _begin_part(part, job.transforms[job.index], job.spec, job.result)
			if job.work.is_empty(): job.index += 1
		elif _advance_part(job.work, job):
			job.work = {}
			job.index += 1
		if job.index < job.parts.size() and Time.get_ticks_usec() >= deadline: return false
	job.finished = true
	return true

static func cut(visual: Node3D, spec: Dictionary, forced_skin := -1.0) -> Result:
	var job := begin(visual, spec, forced_skin)
	step(job, 1 << 40)
	job.result.apply()
	return job.result

## x da lataria: a coluna (1 cm) com mais área de face lateral dentro do vão. Retrovisores e
## maçanetas somem no voto; a saia da carroceria idem.
static func _measure_skin(parts: Array[MeshInstance3D], transforms: Array[Transform3D], spec: Dictionary) -> float:
	var area_by_bin := {}
	var band := {"zf": spec.zf, "zr": spec.zr, "sill": spec.sill, "top": spec.belt}
	for part_index in parts.size():
		var part := parts[part_index]
		var xf: Transform3D = transforms[part_index]
		var box: AABB = xf * part.mesh.get_aabb()
		if box.end.z < spec.zf or box.position.z > spec.zr or box.end.y < spec.sill or box.position.y > spec.top: continue
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()

			var has_index := not indices.is_empty()
			var count := indices.size() if has_index else vertices.size()
			for i in range(0, count, 3):
				var a: Vector3 = xf * vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = xf * vertices[indices[i + 1] if not indices.is_empty() else i + 1]
				var c: Vector3 = xf * vertices[indices[i + 2] if not indices.is_empty() else i + 2]
				var normal := (b - a).cross(c - a)
				var area := normal.length() * .5
				if area < .0001: continue
				normal = normal / (area * 2.0)
				if absf(normal.x) < .9: continue
				# Triângulos grandes (lateral inteira do casco) têm o centro fora do vão: o que
				# vale é a parte que cai dentro da faixa do painel, abaixo da cintura.
				var clipped: Array = _clip_box([[a, Vector3.ZERO, Vector2.ZERO, Color.WHITE], [b, Vector3.ZERO, Vector2.ZERO, Color.WHITE], [c, Vector3.ZERO, Vector2.ZERO, Color.WHITE]], band)[0]
				if clipped.size() < 3: continue
				var x_sum := 0.0
				var inside_area := 0.0
				for k in range(1, clipped.size() - 1):
					inside_area += ((clipped[k][0] - clipped[0][0]) as Vector3).cross((clipped[k + 1][0] - clipped[0][0]) as Vector3).length() * .5
				for vertex in clipped: x_sum += (vertex[0] as Vector3).x
				var x_mean: float = x_sum / clipped.size()
				if absf(x_mean) < .3 or inside_area < .0001: continue
				var bin := int(round(absf(x_mean) * 100.0))
				area_by_bin[bin] = float(area_by_bin.get(bin, 0.0)) + inside_area
	last_bins = area_by_bin
	# O enrolamento dos triângulos não é confiável (caixas de dentro para fora, vidro de face
	# dupla), então valem as duas orientações: a lataria é a coluna mais externa que ainda
	# tem área relevante (parede grossa: face de fora e de dentro; vale a de fora).
	var largest := 0.0
	for bin in area_by_bin: largest = maxf(largest, float(area_by_bin[bin]))
	var best := -1
	for bin in area_by_bin:
		if float(area_by_bin[bin]) >= largest * .3 and bin > best: best = bin
	return float(best) / 100.0 if best > 0 else 0.0

static func _cut_part(part: MeshInstance3D, xf: Transform3D, spec: Dictionary, result: Result) -> void:
	var work := _begin_part(part, xf, spec, result)
	while not work.is_empty():
		if _advance_part(work): return

static func _begin_part(part: MeshInstance3D, xf: Transform3D, spec: Dictionary, destination: Result) -> Dictionary:
	var mesh: Mesh = part.get_meta("body_dents_rest_mesh",part.mesh)
	var box: AABB = xf * mesh.get_aabb()
	if box.end.z < spec.zf or box.position.z > spec.zr or box.end.y < spec.sill or box.position.y > spec.top: return {}
	var reaches_left := box.position.x < -.25
	var reaches_right := box.end.x > .25
	if not reaches_left and not reaches_right: return {}
	var collect_side := 0
	for side in [-1, 1]:
		if (side < 0 and not reaches_left) or (side > 0 and not reaches_right): continue
		var inside: bool = box.position.z >= spec.zf - .02 and box.end.z <= spec.zr + .02 and box.position.y >= spec.sill - .02 and box.end.y <= spec.top + .02
		var on_side: bool = box.position.x > .2 if side > 0 else box.end.x < -.2
		if inside and on_side and box.size.x < .6:
			collect_side = side
			break
	var active_materials: Array[Material] = []
	for surface in mesh.get_surface_count(): active_materials.append(part.get_active_material(surface))
	return {"part": part, "mesh": mesh, "expected_mesh":part.mesh, "xf": xf, "inverse": xf.affine_inverse(), "spec": spec, "result": Result.new(), "destination": destination, "collect_side": collect_side, "materials": active_materials, "stage": "surface", "surface": 0, "triangle": 0, "changed": false, "rebuilt": [], "replacement": null, "upload_surface": 0}

static func _advance_part(work: Dictionary, job: Job = null) -> bool:
	# A freed source has no presentation to replace. Keep partial contribution
	# private until commit so its half-built leaf cannot survive that source.
	if not is_instance_valid(work.part): return true
	var mesh: Mesh = work.mesh
	if work.stage == "surface":
		if int(work.surface) >= mesh.get_surface_count():
			work.stage = "part"
		else:
			_begin_surface(work)
			work.stage = "triangles"
	elif work.stage == "triangles":
		var processed := _triangle_batch(work)
		if job != null: job.triangles_processed += processed
		if int(work.triangle) >= int(work.count): work.stage = "surface_finish"
	elif work.stage == "surface_finish":
		if int(work.collect_side) == 0: _finish_surface(work)
		work.surface = int(work.surface) + 1
		work.stage = "surface"
	elif work.stage == "part":
		if int(work.collect_side) != 0:
			work.result.moved_parts.append(work.part)
			_merge_part(work)
			return true
		if not bool(work.changed):
			_merge_part(work)
			return true
		work.result.cut_parts += 1
		work.replacement = ArrayMesh.new()
		work.stage = "upload"
	elif work.stage == "upload":
		var surface := int(work.upload_surface)
		var arrays: Array = work.rebuilt[surface] if work.rebuilt[surface] != null else mesh.surface_get_arrays(surface)
		work.replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		work.replacement.surface_set_material(surface, mesh.surface_get_material(surface))
		preload("res://gameplay/VehicleInterior.gd").inherit_glass(mesh, work.replacement, surface, arrays)
		work.upload_surface = surface + 1
		if int(work.upload_surface) >= mesh.get_surface_count():
			work.result.swaps.append([work.part, work.expected_mesh, work.replacement,mesh])
			_merge_part(work)
			return true
	return false

static func _begin_surface(work: Dictionary) -> void:
	var mesh: Mesh = work.mesh
	var arrays := mesh.surface_get_arrays(int(work.surface))
	work.vertices = arrays[Mesh.ARRAY_VERTEX]
	work.indices = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	work.normals = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	work.uvs = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	work.colors = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	work.has_index = not (work.indices as PackedInt32Array).is_empty()
	work.count = (work.indices as PackedInt32Array).size() if work.has_index else (work.vertices as PackedVector3Array).size()
	work.material = work.materials[int(work.surface)]
	work.kept = PackedInt32Array()
	work.extra_vertices = PackedVector3Array()
	work.extra_normals = PackedVector3Array()
	work.extra_uvs = PackedVector2Array()
	work.extra_colors = PackedColorArray()
	work.surface_changed = false
	work.triangle = 0

static func _triangle_batch(work: Dictionary) -> int:
	var part: MeshInstance3D = work.part
	var xf: Transform3D = work.xf
	var inverse: Transform3D = work.inverse
	var spec: Dictionary = work.spec
	var result: Result = work.result
	var surface := int(work.surface)
	var vertices: PackedVector3Array = work.vertices
	var indices: PackedInt32Array = work.indices
	var has_index: bool = work.has_index
	var normals: PackedVector3Array = work.normals
	var uvs: PackedVector2Array = work.uvs
	var colors: PackedColorArray = work.colors
	var material: Material = work.material
	var first := int(work.triangle)
	var last := mini(int(work.count), first + TRIANGLES_PER_BATCH * 3)
	if int(work.collect_side) != 0:
		for i in range(first, last, 3):
			var polygon: Array = []
			for k in 3:
				var index: int = indices[i + k] if has_index else i + k
				polygon.append([xf * vertices[index], _n(normals, index, Vector3.UP, xf), _uv(uvs, index), _c(colors, index)])
			_add_leaf(result, int(work.collect_side), material, part, surface, polygon, false)
		work.triangle = last
		return int((last - first) / 3.0)
	# Transfer accumulated packed buffers into locals before appending. Leaving
	# a second owner in the state would detach the full prefix on every batch.
	var kept: PackedInt32Array = work.kept
	var extra_vertices: PackedVector3Array = work.extra_vertices
	var extra_normals: PackedVector3Array = work.extra_normals
	var extra_uvs: PackedVector2Array = work.extra_uvs
	var extra_colors: PackedColorArray = work.extra_colors
	work.kept = PackedInt32Array()
	work.extra_vertices = PackedVector3Array()
	work.extra_normals = PackedVector3Array()
	work.extra_uvs = PackedVector2Array()
	work.extra_colors = PackedColorArray()
	var surface_changed: bool = work.surface_changed
	var changed: bool = work.changed
	for i in range(first, last, 3):
		var ia: int = indices[i] if has_index else i
		var ib: int = indices[i + 1] if has_index else i + 1
		var ic: int = indices[i + 2] if has_index else i + 2
		var pa: Vector3 = xf * vertices[ia]
		var pb: Vector3 = xf * vertices[ib]
		var pc: Vector3 = xf * vertices[ic]
		var center := (pa + pb + pc) / 3.0
		var normal := (pb - pa).cross(pc - pa).normalized()
		var side := -1 if center.x < 0.0 else 1
		# Qualquer sentido de enrolamento: o vidro de face dupla e as paredes internas do casco
		# oco também pertencem ao vão; a folha leva a face com o enrolamento que ela tinha.
		var candidate: bool = absf(normal.x) >= SIDE_FACING and absf(center.x) > .25
		if candidate:
			var low := minf(pa.z, minf(pb.z, pc.z))
			var high := maxf(pa.z, maxf(pb.z, pc.z))
			var bottom := minf(pa.y, minf(pb.y, pc.y))
			var top := maxf(pa.y, maxf(pb.y, pc.y))
			candidate = high > spec.zf and low < spec.zr and top > spec.sill and bottom < spec.top
		if not candidate:
			kept.append_array(PackedInt32Array([ia, ib, ic]))
			continue
		var polygon: Array = [
			[pa, _n(normals, ia, normal, xf), _uv(uvs, ia), _c(colors, ia)],
			[pb, _n(normals, ib, normal, xf), _uv(uvs, ib), _c(colors, ib)],
			[pc, _n(normals, ic, normal, xf), _uv(uvs, ic), _c(colors, ic)]]
		var pieces := _clip_box(polygon, spec)
		var inside: Array = pieces[0]
		var remainder: Array = pieces[1]
		if inside.is_empty():
			kept.append_array(PackedInt32Array([ia, ib, ic]))
			continue
		surface_changed = true
		changed = true
		result.triangles += 1
		_add_leaf(result, side, material, part, surface, inside, false)
		# Cartão interno só das faces bem voltadas para fora (lataria), não de quinas.
		if normal.x * side >= .85 or (normal.x * side >= SIDE_FACING and _is_glass(part, surface, material)):
			_add_leaf(result, side, material, part, surface, inside, true)
		for fragment in remainder:
			var base := vertices.size() + extra_vertices.size()
			for vertex in fragment:
				extra_vertices.append(inverse * (vertex[0] as Vector3))
				extra_normals.append(((inverse.basis * (vertex[1] as Vector3))).normalized())
				extra_uvs.append(vertex[2])
				extra_colors.append(vertex[3])
			# Triângulo em leque; fragmentos já são convexos e saem com o mesmo sentido.
			for k in range(1, fragment.size() - 1):
				kept.append_array(PackedInt32Array([base, base + k, base + k + 1]))

	work.kept = kept
	work.extra_vertices = extra_vertices
	work.extra_normals = extra_normals
	work.extra_uvs = extra_uvs
	work.extra_colors = extra_colors
	work.surface_changed = surface_changed
	work.changed = changed
	work.triangle = last
	return int((last - first) / 3.0)

static func _finish_surface(work: Dictionary) -> void:
	var rebuilt: Array = work.rebuilt
	var surface_changed: bool = work.surface_changed
	var vertices: PackedVector3Array = work.vertices
	var normals: PackedVector3Array = work.normals
	var uvs: PackedVector2Array = work.uvs
	var colors: PackedColorArray = work.colors
	var kept: PackedInt32Array = work.kept
	var extra_vertices: PackedVector3Array = work.extra_vertices
	var extra_normals: PackedVector3Array = work.extra_normals
	var extra_uvs: PackedVector2Array = work.extra_uvs
	var extra_colors: PackedColorArray = work.extra_colors
	if not surface_changed:
		rebuilt.append(null)
		return
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	var new_vertices := vertices.duplicate()
	new_vertices.append_array(extra_vertices)
	out[Mesh.ARRAY_VERTEX] = new_vertices
	var new_normals := normals.duplicate()
	if new_normals.size() != vertices.size():
		new_normals = PackedVector3Array()
		new_normals.resize(vertices.size())
	new_normals.append_array(extra_normals)
	out[Mesh.ARRAY_NORMAL] = new_normals
	var new_uvs := uvs.duplicate()
	if new_uvs.size() != vertices.size():
		new_uvs = PackedVector2Array()
		new_uvs.resize(vertices.size())
	new_uvs.append_array(extra_uvs)
	out[Mesh.ARRAY_TEX_UV] = new_uvs
	if not colors.is_empty():
		var new_colors := colors.duplicate()
		new_colors.append_array(extra_colors)
		out[Mesh.ARRAY_COLOR] = new_colors
	if kept.is_empty():
		# Superfície esvaziada: um triângulo degenerado mantém o índice (materiais e chaves
		# por superfície são posicionais).
		kept = PackedInt32Array([0, 0, 0])
	out[Mesh.ARRAY_INDEX] = kept
	rebuilt.append(out)

static func _merge_part(work: Dictionary) -> void:
	var source: Result = work.result
	var destination: Result = work.destination
	destination.cut_parts += source.cut_parts
	destination.triangles += source.triangles
	destination.moved_parts.append_array(source.moved_parts)
	destination.swaps.append_array(source.swaps)
	for side in [-1, 1]:
		for kind in ["leaf", "inner"]:
			var source_bucket: Dictionary = source.get(kind)[side]
			var destination_bucket: Dictionary = destination.get(kind)[side]
			for material in source_bucket:
				var added: Dictionary = source_bucket[material]
				if not destination_bucket.has(material):
					destination_bucket[material] = added
					continue
				var group: Dictionary = destination_bucket[material]
				var positions: PackedVector3Array = group.pos
				var normals: PackedVector3Array = group.nrm
				var uvs: PackedVector2Array = group.uv
				var colors: PackedColorArray = group.col
				positions.append_array(added.pos)
				normals.append_array(added.nrm)
				uvs.append_array(added.uv)
				colors.append_array(added.col)
				group.pos = positions
				group.nrm = normals
				group.uv = uvs
				group.col = colors

static func _collect_all(part: MeshInstance3D, surface: int, arrays: Array, xf: Transform3D, side: int, result: Result) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var material: Material = part.get_active_material(surface)
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in range(0, count, 3):
		var polygon: Array = []
		for k in 3:
			var index: int = indices[i + k] if not indices.is_empty() else i + k
			polygon.append([xf * vertices[index], _n(normals, index, Vector3.UP, xf), _uv(uvs, index), _c(colors, index)])
		_add_leaf(result, side, material, part, surface, polygon, false)

static func _n(normals: PackedVector3Array, index: int, fallback: Vector3, xf: Transform3D) -> Vector3:
	if index < normals.size(): return (xf.basis * normals[index]).normalized()
	return fallback

static func _uv(uvs: PackedVector2Array, index: int) -> Vector2:
	return uvs[index] if index < uvs.size() else Vector2.ZERO

static func _c(colors: PackedColorArray, index: int) -> Color:
	return colors[index] if index < colors.size() else Color.WHITE

static func _is_glass(part: MeshInstance3D, surface: int, material: Material) -> bool:
	var key := ROLES.key(part, surface)
	return "glass" in key or "windshield" in key or key == "window" or (material != null and material.resource_name == "glass")

## Acumula o polígono (fan) no grupo do material. `inner` gera o cartão: sentido invertido e
## deslocado para dentro; o vidro reaproveita o próprio material.
static func _add_leaf(result: Result, side: int, material: Material, part: MeshInstance3D, surface: int, polygon: Array, inner: bool) -> void:
	var bucket: Dictionary = result.inner[side] if inner else result.leaf[side]
	var use_material: Material = material
	var key := ROLES.key(part, surface)
	if inner:
		if material != null and material is BaseMaterial3D and (material as BaseMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED: return
		if not _is_glass(part, surface, material):
			use_material = null # material do cartão é escolhido na montagem
			key = "card"
	if not bucket.has(use_material):
		bucket[use_material] = {"pos": PackedVector3Array(), "nrm": PackedVector3Array(), "uv": PackedVector2Array(), "col": PackedColorArray(), "key": key}
	var group: Dictionary = bucket[use_material]
	# Arrays empacotados guardados em Dictionary são copiados ao ler: escrever de volta.
	var positions: PackedVector3Array = group.pos
	var normals: PackedVector3Array = group.nrm
	var uvs: PackedVector2Array = group.uv
	var colors: PackedColorArray = group.col
	var shift := Vector3(-float(side) * THICKNESS, 0.0, 0.0) if inner else Vector3.ZERO
	for k in range(1, polygon.size() - 1):
		var order := [0, k + 1, k] if inner else [0, k, k + 1]
		for index in order:
			var vertex: Array = polygon[index]
			positions.append((vertex[0] as Vector3) + shift)
			normals.append(-(vertex[1] as Vector3) if inner else vertex[1])
			uvs.append(vertex[2])
			colors.append(vertex[3])
	group.pos = positions
	group.nrm = normals
	group.uv = uvs
	group.col = colors

## Recorta um polígono convexo pelo prisma do vão (z, y). Devolve [dentro, restos]: `dentro`
## é um polígono (ou vazio) e `restos`, polígonos convexos que juntos completam o triângulo.
static func _clip_box(polygon: Array, spec: Dictionary) -> Array:
	var remainder: Array = []
	var current := polygon
	# Ordem: frente, trás, rodapé, teto.
	var planes := [[Z, spec.zf, true], [Z, spec.zr, false], [Y, spec.sill, true], [Y, spec.top, false]]
	for plane in planes:
		var parts := _split(current, plane[0], plane[1])
		var above: Array = parts[0]
		var below: Array = parts[1]
		var keep: Array = above if plane[2] else below
		var drop: Array = below if plane[2] else above
		if drop.size() >= 3: remainder.append(drop)
		current = keep
		if current.size() < 3: return [[], [polygon]]
	return [current, remainder]

static func _split(polygon: Array, axis: int, value: float) -> Array:
	var above: Array = []
	var below: Array = []
	var count := polygon.size()
	for i in count:
		var a: Array = polygon[i]
		var b: Array = polygon[(i + 1) % count]
		var da: float = (a[0] as Vector3)[axis] - value
		var db: float = (b[0] as Vector3)[axis] - value
		if da >= 0.0: above.append(a)
		else: below.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var t := da / (da - db)
			var mid := [(a[0] as Vector3).lerp(b[0], t), ((a[1] as Vector3).lerp(b[1], t)).normalized(), (a[2] as Vector2).lerp(b[2], t), (a[3] as Color).lerp(b[3], t)]
			above.append(mid)
			below.append(mid)
	return [above, below]

## Junta um dicionário de grupos num ArrayMesh de várias superfícies (uma por material) com
## os vértices deslocados por `offset`. Devolve também as chaves de material por superfície,
## no mesmo formato que a lataria usa (`*_surface_material_keys`) para dano e pintura.
static func to_mesh(groups: Dictionary, offset: Vector3, card_material: Material) -> Array:
	var mesh := ArrayMesh.new()
	var keys: Array = []
	for material in groups:
		var group: Dictionary = groups[material]
		var positions: PackedVector3Array = group.pos
		if positions.is_empty(): continue
		var shifted := PackedVector3Array()
		shifted.resize(positions.size())
		for i in positions.size(): shifted[i] = positions[i] - offset
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = shifted
		arrays[Mesh.ARRAY_NORMAL] = group.nrm
		arrays[Mesh.ARRAY_TEX_UV] = group.uv
		var uses_color := false
		for c in (group.col as PackedColorArray):
			if not c.is_equal_approx(Color.WHITE):
				uses_color = true
				break
		if uses_color: arrays[Mesh.ARRAY_COLOR] = group.col
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, card_material if material == null else material)
		keys.append(group.key)
	return [mesh, keys]
