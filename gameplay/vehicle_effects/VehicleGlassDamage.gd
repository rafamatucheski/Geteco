extends Node
## Dano nos vidros só por evento e local da instância. Superfícies de carroceria/pintura nunca são escondidas nem editadas.
## Tiros racham o vidro (marca projetada) e só o BREAK_HITS-ésimo no mesmo painel o derruba.
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const REMNANTS := preload("res://gameplay/vehicle_effects/VehicleGlassRemnants.gd")
const NODE_NAME := "GlassDamage"
const MAX_RECORDS := 32
var vehicle: Node3D
var records: Array = []
var _parts: Dictionary = {}
var _applying := false
static var _missing: StandardMaterial3D

static func owner_for(car: Node3D, create := false) -> Node:
	var owner := car.get_node_or_null(NODE_NAME)
	if owner == null and create:
		owner = load("res://gameplay/vehicle_effects/VehicleGlassDamage.gd").new()
		owner.name = NODE_NAME
		owner.vehicle = car
		car.add_child(owner)
	return owner

static func valid_records(value: Variant) -> bool:
	if not value is Array or value.size() > MAX_RECORDS: return false
	for row in value:
		if not row is Dictionary: return false
		for key in ["point","direction"]:
			if not row.get(key) is Array or row[key].size() != 3: return false
			for number in row[key]:
				if typeof(number) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(number)) or absf(float(number)) > 64.0: return false
		if absf(Vector3(row.direction[0],row.direction[1],row.direction[2]).length()-1.0) > .01: return false
	return true

static func pristine_part(car: Node3D, part: MeshInstance3D) -> Mesh:
	var owner := owner_for(car)
	if owner != null and owner._parts.has(part) and part.mesh == owner._parts[part].applied:
		return owner._parts[part].base
	return part.mesh

static func geometry_changed(car: Node3D) -> void:
	var owner := owner_for(car)
	if owner != null: owner.reapply()

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func snapshot() -> Array: return records.duplicate(true)

func restore_records(value: Array) -> void:
	if not valid_records(value): return
	clear()
	if value.is_empty(): return
	_prepare_topology()
	records = value.duplicate(true)
	reapply()

func _prepare_topology() -> void:
	# Freeze cabin dimensions before removing a window; finish a pending door cut before
	# making holes, so later boarding cannot rebuild pristine glazing over those holes.
	INTERIOR.spec(vehicle)
	if vehicle.has_method("finish_doors"): vehicle.finish_doors()

static func _canonical(part: Node3D, car: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var cursor := part
	while cursor != null and cursor != car:
		var pose := cursor.transform
		if str(cursor.name) in ["DriverDoorL","DriverDoorR"]: pose.basis = Basis.IDENTITY
		result = pose * result
		cursor = cursor.get_parent() as Node3D
	return result

static func _hidden(part: MeshInstance3D, surface: int) -> bool:
	if not part.is_visible_in_tree(): return true
	var material := part.get_active_material(surface) as BaseMaterial3D
	return material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a < .01

static func _indices(arrays: Array) -> PackedInt32Array:
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if not indices.is_empty(): return indices
	indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	for i in indices.size(): indices[i] = i
	return indices

## Devolve a superfície renderizada mais próxima, incluindo pintura, rodas e lâmpadas que bloqueiam o tiro.
func contact(from: Vector3, to: Vector3) -> Dictionary:
	var nearest := INF
	var result: Dictionary = {}
	for part: MeshInstance3D in vehicle.visual.find_children("*","MeshInstance3D",true,false):
		if part.has_meta("vehicle_shadow_proxy"): continue
		if part.mesh == null or not part.is_visible_in_tree() or part.skeleton != NodePath(""): continue
		if part.name in ["RoofCut","WarmUp"] or "Interior" in str(part.get_path()) or "/WindshieldRain/" in str(part.get_path()): continue
		var inverse := part.global_transform.affine_inverse()
		var start := inverse * from
		var end := inverse * to
		if part.mesh.get_aabb().grow(.002).intersects_segment(start,end) == null: continue
		for surface in part.mesh.get_surface_count():
			if _hidden(part,surface) or part.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := _indices(arrays)
			for i in range(0,indices.size()-2,3):
				var point: Variant = Geometry3D.segment_intersects_triangle(start,end,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]])
				if point == null: continue
				var world_point := part.to_global(point)
				var distance := from.distance_squared_to(world_point)
				if distance >= nearest: continue
				nearest = distance
				result = {"part":part,"surface":surface,"triangle":i,"point":world_point,
					"glass":INTERIOR._is_glass(part,surface,part.get_active_material(surface))}
	return result

## Vidro atingido (26/10/2026): os primeiros tiros num painel só racham (marca projetada, Decal, sem
## mexer na malha nem criar shader); no BREAK_HITS-ésimo o painel cai inteiro, como antes. Antes o
## primeiro tiro já tirava o vidro todo e a janela sumia de uma vez. Cada registro conta para o painel
## que ele cruza na malha intacta da peça, então salvar e carregar refaz o mesmo estado.
const BREAK_HITS := 3
## A janela da viatura tem faces externa/interna separadas por 2 cm.
## São um painel físico; outra janela além desta espessura fica intacta.
const PANE_LAYER_THICKNESS := .03
const CRACK_SIZE := .42
const CRACK_NAME := "GlassCrack"
static var _crack_texture: ImageTexture
var _cracks: Dictionary = {}

func shoot(from: Vector3, to: Vector3) -> Dictionary:
	if records.size() >= MAX_RECORDS or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to) < .0001: return {}
	_prepare_topology()
	var hit := contact(from,to)
	if hit.is_empty() or not hit.glass: return {}
	var part: MeshInstance3D = hit.part
	var canonical := _canonical(part,vehicle)
	var point := canonical * part.to_local(hit.point)
	var direction := (canonical.basis * (part.global_basis.inverse() * from.direction_to(to))).normalized()
	var row := {"point":[point.x,point.y,point.z],"direction":[direction.x,direction.y,direction.z]}
	records.append(row)
	_rebuild(part)
	# Painel que caiu neste tiro: o mesmo raio não acha mais esse vidro no ponto do impacto.
	var after := contact(from,to)
	var shattered: bool = after.is_empty() or after.part != part or not after.glass or after.point.distance_to(hit.point) > .05
	if shattered: _refresh_rain()
	return {"point":hit.point,"normal":-from.direction_to(to),"material":"glass","shattered":shattered}

## Refaz uma peça a partir da malha intacta com todos os registros (rachaduras e painéis caídos).
func _rebuild(part: MeshInstance3D) -> void:
	if _parts.has(part):
		var entry: Dictionary = _parts[part]
		if part.mesh == entry.applied: part.mesh = entry.base
		for surface in entry.overrides:
			if int(surface) < part.mesh.get_surface_count(): part.set_surface_override_material(surface,entry.overrides[surface])
		_parts.erase(part)
	if batch_reapply: _reapply_part(part)
	else: _reapply_part_per_record(part)

## Triângulos conectados, soldados por posição, identificam um vidro mesmo em superfícies combinadas.
func _remove_panel(part: MeshInstance3D, surface: int, triangle: int) -> void:
	var original := part.mesh
	var arrays := INTERIOR.contact_arrays(original,surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := _indices(arrays)
	var triangles: Dictionary = {}
	for i in range(0,indices.size()-2,3):
		for j in 3:
			var point := vertices[indices[i+j]]
			var key := Vector3i(roundi(point.x*1000.0),roundi(point.y*1000.0),roundi(point.z*1000.0))
			if not triangles.has(key): triangles[key] = []
			triangles[key].append(i)
	var removed: Dictionary = {triangle:true}
	var queue: Array[int] = [triangle]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in 3:
			var point := vertices[indices[i+j]]
			var key := Vector3i(roundi(point.x*1000.0),roundi(point.y*1000.0),roundi(point.z*1000.0))
			for neighbor in triangles[key]:
				if removed.has(neighbor): continue
				removed[neighbor] = true
				queue.append(neighbor)
	var kept := PackedInt32Array()
	for i in range(0,indices.size()-2,3):
		if not removed.has(i):
			kept.append(indices[i]); kept.append(indices[i+1]); kept.append(indices[i+2])
	var entry: Dictionary = _parts.get(part,{"base":original,"applied":original,"overrides":{}})
	if part.mesh != entry.applied: entry.base = original
	if not entry.overrides.has(surface): entry.overrides[surface] = part.get_surface_override_material(surface)
	if kept.is_empty():
		if _missing == null:
			_missing = StandardMaterial3D.new()
			_missing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_missing.albedo_color = Color(0,0,0,0)
		part.set_surface_override_material(surface,_missing)
	else:
		var replacement := ArrayMesh.new()
		for other in original.get_surface_count():
			var changed := INTERIOR.contact_arrays(original,other).duplicate()
			if other == surface: changed[Mesh.ARRAY_INDEX] = kept
			replacement.add_surface_from_arrays(original.surface_get_primitive_type(other),changed)
			replacement.surface_set_material(other,original.surface_get_material(other))
			INTERIOR.inherit_glass(original,replacement,other,changed)
		part.mesh = replacement
	entry.applied = part.mesh
	_parts[part] = entry

func reapply() -> void:
	if _applying or records.is_empty() or not is_instance_valid(vehicle): return
	_applying = true
	for part: MeshInstance3D in vehicle.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.is_visible_in_tree(): continue
		if _parts.has(part) and part.mesh == _parts[part].applied: continue
		if batch_reapply: _reapply_part(part)
		else: _reapply_part_per_record(part)
	_applying = false
	_refresh_rain()

## GETECO_GLASS_BATCH_REAPPLY=0 volta ao caminho antigo, um _remove_panel por registro (A/B).
static var batch_reapply := OS.get_environment("GETECO_GLASS_BATCH_REAPPLY") != "0"

func _reapply_part_per_record(part: MeshInstance3D) -> void:
	var inverse := _canonical(part,vehicle).affine_inverse()
	for row in records:
		var point := Vector3(row.point[0],row.point[1],row.point[2])
		var direction := Vector3(row.direction[0],row.direction[1],row.direction[2])
		var start := inverse * (point-direction*.08)
		var end := inverse * (point+direction*.08)
		for surface in part.mesh.get_surface_count():
			if _hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
			var arrays := INTERIOR.contact_arrays(part.mesh,surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := _indices(arrays)
			for i in range(0,indices.size()-2,3):
				if Geometry3D.segment_intersects_triangle(start,end,vertices[indices[i]],vertices[indices[i+1]],vertices[indices[i+2]]) != null:
					_remove_panel(part,surface,i)
					break

## Todos os registros de uma vez numa peça (24/10). Antes cada registro que acertava vidro chamava
## _remove_panel, que remontava o mapa de vizinhança do vidro e a malha INTEIRA da peça: depois de um
## amassado (malha nova, geometry_changed) um carro com 10 tiros remontava a lataria 10 vezes no mesmo
## quadro (vehicle.dents.apply 8–20 ms no estresse a quente, 6ª rodada). Mesmo resultado: cada registro, em
## ordem, tira o painel do 1º triângulo ainda presente que ele cruza em cada superfície de vidro; o mapa de
## vizinhança sai uma vez por superfície e a malha é remontada uma vez no fim.
func _reapply_part(part: MeshInstance3D) -> void:
	var original := part.mesh
	var inverse := _canonical(part,vehicle).affine_inverse()
	var segments: Array = []
	for row in records:
		var point := Vector3(row.point[0],row.point[1],row.point[2])
		var direction := Vector3(row.direction[0],row.direction[1],row.direction[2])
		segments.append([inverse * (point-direction*.08), inverse * (point+direction*.08)])
	var removed_by_surface: Dictionary = {}
	var cracks: Array = []
	var crack_records: Dictionary = {}
	var scale_basis := part.global_basis
	for surface in original.get_surface_count():
		if _hidden(part,surface) or not INTERIOR._is_glass(part,surface,part.get_active_material(surface)): continue
		var arrays := INTERIOR.contact_arrays(original,surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty(): continue
		var indices := _indices(arrays)
		var bounds := AABB(vertices[0],Vector3.ZERO)
		for vertex in vertices: bounds = bounds.expand(vertex)
		bounds = bounds.grow(.002)
		var welded: Dictionary = {}
		var pane_of: Dictionary = {}
		var panes: Dictionary = {}
		var hits: Dictionary = {}
		for record_index in segments.size():
			var segment: Array = segments[record_index]
			if bounds.intersects_segment(segment[0],segment[1]) == null: continue
			var contacts: Array = []
			var nearest := INF
			var contact_point := Vector3.ZERO
			var contact_normal := Vector3.ZERO
			for i in range(0,indices.size()-2,3):
				var a := vertices[indices[i]]
				var b := vertices[indices[i+1]]
				var c := vertices[indices[i+2]]
				var at: Variant = Geometry3D.segment_intersects_triangle(segment[0],segment[1],a,b,c)
				if at == null: continue
				contacts.append([i,at])
				var distance: float = (scale_basis * (at - (segment[0] + segment[1]) * .5)).length_squared()
				if distance < nearest:
					nearest = distance
					contact_point = at
					contact_normal = _authored_normal(arrays,indices,i)
			# Alguns modelos têm lâminas próximas e desconectadas na mesma janela.
			# Elas quebram juntas; a janela oposta não recebe o mesmo tiro salvo.
			var hit_panes: Dictionary = {}
			for contact_hit in contacts:
				var i: int = contact_hit[0]
				var at: Vector3 = contact_hit[1]
				if (scale_basis * (at - contact_point)).length_squared() > PANE_LAYER_THICKNESS * PANE_LAYER_THICKNESS: continue
				var layer_normal := _authored_normal(arrays,indices,i)
				if layer_normal.length_squared() > .5 and contact_normal.length_squared() > .5:
					var normal_basis := scale_basis.inverse().transposed()
					if absf((normal_basis * layer_normal).normalized().dot((normal_basis * contact_normal).normalized())) < .95: continue
				if welded.is_empty(): welded = _welded(vertices,indices)
				if not pane_of.has(i):
					var pane: Dictionary = {}
					_flood(i,vertices,indices,welded,pane)
					var seed: int = pane.keys().min()
					for triangle in pane: pane_of[triangle] = seed
					panes[seed] = pane
				var key: int = pane_of[i]
				if hit_panes.has(key): continue
				hit_panes[key] = true
				if not hits.has(key): hits[key] = []
				# A marca olha para o lado do atirador: o Decal some numa face virada contra ele.
				var a := vertices[indices[i]]
				var b := vertices[indices[i+1]]
				var c := vertices[indices[i+2]]
				var normal := (b-a).cross(c-a).normalized()
				if normal.dot(segment[1]-segment[0]) > 0.0: normal = -normal
				# O winding horário da frota não define a normal usada na iluminação.
				# Havendo normal autorada, a projeção acompanha a face renderizada.
				var authored := layer_normal
				if authored.length_squared() > .5: normal = authored
				hits[key].append([at,normal,record_index])
		var removed: Dictionary = {}
		for key in hits:
			if hits[key].size() >= BREAK_HITS: removed.merge(panes[key])
			else:
				for hit in hits[key]:
					if not crack_records.has(hit[2]):
						cracks.append(hit)
						crack_records[hit[2]] = true
		if not removed.is_empty(): removed_by_surface[surface] = removed
	_set_cracks(part,cracks)
	if removed_by_surface.is_empty(): return
	var entry: Dictionary = _parts.get(part,{"base":original,"applied":original,"overrides":{}})
	if part.mesh != entry.applied: entry.base = original
	var kept_by_surface: Dictionary = {}
	var arrays_by_surface: Dictionary = {}
	var remnant_starts: Dictionary = {}
	for surface in removed_by_surface:
		if not entry.overrides.has(surface): entry.overrides[surface] = part.get_surface_override_material(surface)
		var indices := _indices(INTERIOR.contact_arrays(original,surface))
		var removed: Dictionary = removed_by_surface[surface]
		var kept := PackedInt32Array()
		for i in range(0,indices.size()-2,3):
			if not removed.has(i):
				kept.append(indices[i]); kept.append(indices[i+1]); kept.append(indices[i+2])
		var remnant_start := kept.size()
		var changed := REMNANTS.build(INTERIOR.contact_arrays(original,surface),kept,removed,part.global_basis,segments)
		kept = changed[Mesh.ARRAY_INDEX]
		if kept.size() > remnant_start: remnant_starts[surface] = remnant_start
		if kept.is_empty():
			if _missing == null:
				_missing = StandardMaterial3D.new()
				_missing.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_missing.albedo_color = Color(0,0,0,0)
			part.set_surface_override_material(surface,_missing)
		else:
			kept_by_surface[surface] = kept
			arrays_by_surface[surface] = changed
	if not kept_by_surface.is_empty():
		var replacement := ArrayMesh.new()
		for other in original.get_surface_count():
			var changed: Array = arrays_by_surface.get(other,INTERIOR.contact_arrays(original,other).duplicate())
			if kept_by_surface.has(other): changed[Mesh.ARRAY_INDEX] = kept_by_surface[other]
			replacement.add_surface_from_arrays(original.surface_get_primitive_type(other),changed)
			replacement.surface_set_material(other,original.surface_get_material(other))
			INTERIOR.inherit_glass(original,replacement,other,changed)
		replacement.set_meta("glass_remnant_starts",remnant_starts)
		part.mesh = replacement
	entry.applied = part.mesh
	_parts[part] = entry

static func _weld_key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x*1000.0),roundi(point.y*1000.0),roundi(point.z*1000.0))

static func _authored_normal(arrays: Array, indices: PackedInt32Array, triangle: int) -> Vector3:
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if normals.size() != vertices.size(): return Vector3.ZERO
	var normal := normals[indices[triangle]] + normals[indices[triangle + 1]] + normals[indices[triangle + 2]]
	return normal.normalized() if normal.is_finite() and normal.length_squared() > .00000001 else Vector3.ZERO

static func _welded(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var triangles: Dictionary = {}
	for i in range(0,indices.size()-2,3):
		for j in 3:
			var key := _weld_key(vertices[indices[i+j]])
			if not triangles.has(key): triangles[key] = []
			triangles[key].append(i)
	return triangles

## Painel = triângulos ligados por vértice soldado, a partir de `seed`, somados a `removed`.
static func _flood(seed: int, vertices: PackedVector3Array, indices: PackedInt32Array, welded: Dictionary, removed: Dictionary) -> void:
	removed[seed] = true
	var queue: Array[int] = [seed]
	while not queue.is_empty():
		var i: int = queue.pop_back()
		for j in 3:
			for neighbor in welded[_weld_key(vertices[indices[i+j]])]:
				if removed.has(neighbor): continue
				removed[neighbor] = true
				queue.append(neighbor)

## Uma marca de rachadura por tiro que não derrubou o painel: Decal filho da peça (acompanha a porta),
## em metros no mundo (a base ortonormal tira a escala da peça). Não é malha, então quem percorre as
## malhas do carro (amassado, chuva, cabine, sangue) não a enxerga.
func _set_cracks(part: MeshInstance3D, cracks: Array) -> void:
	for old in _cracks.get(part,[]):
		if is_instance_valid(old): old.queue_free()
	_cracks.erase(part)
	if cracks.is_empty(): return
	# Carro restaurado do save antes de entrar na árvore: as marcas entram junto com ele.
	if not part.is_inside_tree():
		part.tree_entered.connect(_set_cracks.bind(part,cracks),CONNECT_ONE_SHOT)
		return
	var nodes: Array = []
	for index in cracks.size():
		var normal: Vector3 = (part.global_basis.inverse().transposed() * (cracks[index][1] as Vector3)).normalized()
		if not normal.is_finite() or normal.length_squared() < .5: continue
		var side := normal.cross(Vector3.UP if absf(normal.y) < .9 else Vector3.RIGHT).normalized()
		side = side.rotated(normal,float(index) * 2.39996)
		var decal := Decal.new()
		decal.name = CRACK_NAME
		decal.texture_albedo = crack_texture()
		decal.size = Vector3(CRACK_SIZE,.08,CRACK_SIZE)
		decal.normal_fade = .4
		decal.upper_fade = .15
		decal.lower_fade = .15
		part.add_child(decal)
		decal.global_transform = Transform3D(Basis(side,normal,side.cross(normal)).orthonormalized(),part.to_global(cracks[index][0]))
		nodes.append(decal)
	_cracks[part] = nodes

## Estrela de trincas branca com furo escuro no meio, desenhada uma vez (sob a cortina pelo
## pré-aquecimento dos materiais de veículo; o primeiro tiro não paga isso).
static func crack_texture() -> ImageTexture:
	if _crack_texture != null: return _crack_texture
	const SIZE := 256
	var image := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	image.fill(Color(1,1,1,0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 26102026
	var center := Vector2(SIZE,SIZE) * .5
	var spokes: Array = []
	var count := 11
	for i in count:
		var heading := TAU * (float(i) + rng.randf_range(-.3,.3)) / count
		var reach := SIZE * rng.randf_range(.36,.49)
		var points: Array = [center]
		var length := 0.0
		while length < reach:
			heading += rng.randf_range(-.18,.18)
			length += rng.randf_range(10,18)
			points.append(center + Vector2.from_angle(heading) * length)
		spokes.append(points)
		for k in points.size() - 1:
			_crack_line(image,points[k],points[k + 1],lerpf(.95,.35,float(k) / points.size()),1.6 if k < 2 else 1.0)
	# Anéis ligando os raios, como no vidro laminado.
	for ring in [.32,.62]:
		for i in count:
			var a: Array = spokes[i]
			var b: Array = spokes[(i + 1) % count]
			var ia := mini(int(a.size() * ring),a.size() - 1)
			var ib := mini(int(b.size() * ring),b.size() - 1)
			_crack_line(image,a[ia],b[ib],.55 if ring < .5 else .35,1.0)
	for y in range(-7,8):
		for x in range(-7,8):
			var d := Vector2(x,y).length()
			if d <= 7.0: image.set_pixel(int(center.x) + x,int(center.y) + y,Color(.08,.09,.1,clampf(1.6 - d / 5.0,0,1)))
	image.generate_mipmaps()
	_crack_texture = ImageTexture.create_from_image(image)
	return _crack_texture

static func _crack_line(image: Image, a: Vector2, b: Vector2, alpha: float, width: float) -> void:
	var steps := maxi(1,ceili(a.distance_to(b)))
	for s in steps + 1:
		var p := a.lerp(b,float(s) / steps)
		for dy in range(-1,2):
			for dx in range(-1,2):
				var q := Vector2i(int(p.x) + dx,int(p.y) + dy)
				if q.x < 0 or q.y < 0 or q.x >= image.get_width() or q.y >= image.get_height(): continue
				var cover := clampf(width - Vector2(q).distance_to(p) + .5,0,1) * alpha
				if cover <= 0.0: continue
				var old := image.get_pixelv(q)
				image.set_pixelv(q,Color(.94,.97,1.0,maxf(old.a,cover)))

func clear() -> void:
	records.clear()
	for part in _cracks.keys(): _set_cracks(part,[])
	for part: MeshInstance3D in _parts:
		if not is_instance_valid(part): continue
		var entry: Dictionary = _parts[part]
		if part.mesh == entry.applied: part.mesh = entry.base
		for surface in entry.overrides:
			if int(surface) < part.mesh.get_surface_count(): part.set_surface_override_material(surface,entry.overrides[surface])
	_parts.clear()
	_refresh_rain()

func _refresh_rain() -> void:
	var effects: Node = vehicle.get("effects")
	if is_instance_valid(effects) and effects.get("windshield_rain") != null:
		effects.windshield_rain.refresh_geometry()
