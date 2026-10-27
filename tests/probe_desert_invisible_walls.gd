extends SceneTree
## Sonda do relato "parede invisível no chão do deserto" (painel: bug-colisores-invisiveis-deserto-20261012).
## Monta a região do deserto de verdade, célula por célula (96 m), e compara a colisão com o que se vê:
## toda malha visível da célula vira um corpo num espaço físico à parte (só da sonda), e cada raio é lançado
## nos dois espaços.
## - chão: em grade, a altura da colisão contra a altura visível. Colisão acima do visual é obstáculo que não
##   aparece (a roda bate numa quina ou o carro anda no ar);
## - parede: raios horizontais a 0,3 m e 1,0 m acima do chão (roda/para-choque e peito do jogador). Batida na
##   colisão sem superfície visível logo atrás dela é parede invisível.
## Rodar com janela: em --headless o servidor de render falso não guarda as posições das MultiMesh (todas
## voltam na origem) e toda peça agrupada vira "parede invisível" falsa.
## - degrau (--steps): o casco do carro é uma caixa que não sobe degrau (Vehicle.gd não tem step-up). Em grade
##   fina, dois vizinhos com chão a alturas de 8 mm a 35 cm e uma face quase vertical entre eles travam o carro;
##   o relatório mostra quanto do degrau aparece no visual.
## Uso: "$GODOT" --path . --script res://tests/probe_desert_invisible_walls.gd -- [--step=1.0] [--steps] [--cells=x0,z0,x1,z1]
const REGION := preload("res://world/desert/DesertRegion.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const CELL := 96.0
const MASK := 7
## Folga entre colisão e visual: malhas de chão costumam ficar alguns centímetros acima do colisor.
const RISE_LIMIT := .08
const WALL_SLACK := .4
var region: Node3D
var step := 1.0
var walls := {}
var bumps := {}
var ledges := {}
var steps_mode := false
var total_rays := 0
var _shapes := {}
var _visual_space: RID
var _visual_bodies: Array[RID] = []

func _initialize() -> void:
	create_timer(5400).timeout.connect(func(): push_error("DESERT_WALLS timeout"); quit(3))
	_run.call_deferred()

func _run() -> void:
	var first := Vector2i(floori(LAYOUT.BOUNDS.position.x/CELL), floori(LAYOUT.BOUNDS.position.y/CELL))
	var last := Vector2i(floori(LAYOUT.BOUNDS.end.x/CELL), floori(LAYOUT.BOUNDS.end.y/CELL))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--step="): step = float(arg.trim_prefix("--step="))
		if arg == "--steps":
			steps_mode = true
			step = .5
		if arg.begins_with("--cells="):
			var v := arg.trim_prefix("--cells=").split(",")
			first = Vector2i(int(v[0]), int(v[1]))
			last = Vector2i(int(v[2]), int(v[3]))
	_visual_space = PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(_visual_space, true)
	var start := Vector3((first.x+.5)*CELL, 0, (first.y+.5)*CELL)
	region = REGION.build_region("desert", start)
	root.add_child(region)
	var began := Time.get_ticks_msec()
	var cells := 0
	for cz in range(first.y, last.y+1):
		for cx in range(first.x, last.x+1):
			var rect := Rect2(cx*CELL, cz*CELL, CELL, CELL)
			if not rect.intersects(LAYOUT.BOUNDS): continue
			region.set_focus(Vector3(rect.get_center().x, 0, rect.get_center().y), true)
			for frame in 1200:
				await physics_frame
				if region.is_streaming_idle(): break
			for frame in 3: await physics_frame
			var area := rect.intersection(LAYOUT.BOUNDS)
			_build_visual(area.grow(3.0))
			for frame in 2: await physics_frame
			if steps_mode: _scan_steps(area)
			else: _scan(area)
			_clear_visual()
			cells += 1
			if cells % 10 == 0: print("DESERT_WALLS progresso ", cells, " células, ", total_rays, " raios")
	_report(Time.get_ticks_msec()-began)
	region.free()
	PhysicsServer3D.free_rid(_visual_space)
	quit(0)

func _shape_for(mesh: Mesh) -> RID:
	if not _shapes.has(mesh):
		var shape := mesh.create_trimesh_shape()
		if shape != null: shape.backface_collision = true
		_shapes[mesh] = shape
	var cached: Shape3D = _shapes[mesh]
	return cached.get_rid() if cached != null else RID()

func _build_visual(area: Rect2) -> void:
	var stack: Array[Node] = [region]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if not (n is GeometryInstance3D) or not n.is_visible_in_tree(): continue
		if n.transparency > .5 or n.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY: continue
		var mesh: Mesh = null
		var transforms: Array[Transform3D] = []
		if n is MultiMeshInstance3D and n.multimesh != null and n.multimesh.mesh != null:
			mesh = n.multimesh.mesh
			var count: int = n.multimesh.visible_instance_count if n.multimesh.visible_instance_count >= 0 else n.multimesh.instance_count
			for i in count:
				var t: Transform3D = n.global_transform*n.multimesh.get_instance_transform(i)
				var box: AABB = t*mesh.get_aabb()
				if area.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)): transforms.append(t)
		elif n is MeshInstance3D and n.mesh != null:
			var box: AABB = n.global_transform*n.get_aabb()
			if not area.intersects(Rect2(box.position.x, box.position.z, box.size.x, box.size.z)): continue
			mesh = n.mesh
			transforms.append(n.global_transform)
		if mesh == null or transforms.is_empty(): continue
		var shape := _shape_for(mesh)
		if not shape.is_valid(): continue
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body, _visual_space)
		for t in transforms: PhysicsServer3D.body_add_shape(body, shape, t)
		_visual_bodies.append(body)

func _clear_visual() -> void:
	for body in _visual_bodies: PhysicsServer3D.free_rid(body)
	_visual_bodies.clear()

func _owner_label(hit: Dictionary) -> String:
	var body: Object = hit.collider
	if body == null: return "?"
	var path := str((body as Node).get_path()) if body is Node else str(body)
	path = path.get_slice("/root/", 1)
	var shape_name := ""
	if body is CollisionObject3D:
		var owner: Object = body.shape_owner_get_owner(body.shape_find_owner(hit.shape))
		if owner is CollisionShape3D and owner.shape != null: shape_name = " " + owner.shape.get_class()
	# Agrupa instâncias numeradas do mesmo tipo (Chunk_3_-9/Rock@12 → Chunk/Rock).
	var regex := RegEx.create_from_string("[_@-]?-?\\d+")
	return regex.sub(path, "", true) + shape_name + " [" + body.get_class() + "]"

func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	total_rays += 1
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK)
	q.hit_back_faces = true
	return space.intersect_ray(q)

func _scan(area: Rect2) -> void:
	var space := region.get_world_3d().direct_space_state
	var visual := PhysicsServer3D.space_get_direct_state(_visual_space)
	var nx := int(area.size.x/step)
	var nz := int(area.size.y/step)
	for iz in nz+1:
		for ix in nx+1:
			var x := area.position.x + ix*step
			var z := area.position.y + iz*step
			var down := _ray(space, Vector3(x, 80, z), Vector3(x, -80, z))
			if down.is_empty(): continue
			var ground: Vector3 = down.position
			var seen := _ray(visual, Vector3(x, 80, z), Vector3(x, -80, z))
			var seen_y: float = seen.position.y if not seen.is_empty() else -INF
			var rise := ground.y-seen_y
			if rise > RISE_LIMIT: _add(bumps, _owner_label(down), ground, minf(rise, 99.0))
			for lift in [.3, 1.0]:
				for dir in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
					var from: Vector3 = ground + Vector3.UP*lift
					var hit := _ray(space, from, from+dir*step)
					if hit.is_empty() or absf(hit.normal.y) > .5: continue
					var distance := from.distance_to(hit.position)
					var behind := _ray(visual, from, from+dir*(distance+WALL_SLACK))
					if not behind.is_empty(): continue
					_add(walls, _owner_label(hit), hit.position, lift)

func _scan_steps(area: Rect2) -> void:
	var space := region.get_world_3d().direct_space_state
	var visual := PhysicsServer3D.space_get_direct_state(_visual_space)
	var nx := int(area.size.x/step)
	var nz := int(area.size.y/step)
	var physical := PackedFloat32Array()
	var seen := PackedFloat32Array()
	physical.resize((nx+1)*(nz+1))
	seen.resize((nx+1)*(nz+1))
	for iz in nz+1:
		for ix in nx+1:
			var x := area.position.x + ix*step
			var z := area.position.y + iz*step
			var hit := _ray(space, Vector3(x, 80, z), Vector3(x, -80, z))
			var look := _ray(visual, Vector3(x, 80, z), Vector3(x, -80, z))
			physical[iz*(nx+1)+ix] = hit.position.y if not hit.is_empty() else NAN
			seen[iz*(nx+1)+ix] = look.position.y if not look.is_empty() else NAN
	for iz in nz+1:
		for ix in nx+1:
			var index := iz*(nx+1)+ix
			for next in [index+1 if ix < nx else -1, index+nx+1 if iz < nz else -1]:
				if next < 0 or is_nan(physical[index]) or is_nan(physical[next]): continue
				var rise := absf(physical[next]-physical[index])
				if rise < .008 or rise > .35: continue
				var low: int = index if physical[index] < physical[next] else next
				var high: int = next if low == index else index
				var a := Vector3(area.position.x+(low%(nx+1))*step, physical[low]+.004, area.position.y+(low/(nx+1))*step)
				var b := Vector3(area.position.x+(high%(nx+1))*step, physical[low]+.004, area.position.y+(high/(nx+1))*step)
				var face := _ray(space, a, b)
				if face.is_empty() or face.normal.y > .7: continue
				var shown: float = absf(seen[next]-seen[index]) if not is_nan(seen[next]) and not is_nan(seen[index]) else 0.0
				# Degrau que também aparece no visual (meio-fio, soleira) não é invisível.
				if shown > rise*.6: continue
				_add(ledges, _owner_label(face), face.position, rise)

func _add(table: Dictionary, key: String, p: Vector3, value := 0.0) -> void:
	if not table.has(key): table[key] = {"count": 0, "samples": [], "max": 0.0}
	var entry: Dictionary = table[key]
	entry.count += 1
	entry.max = maxf(entry.max, value)
	if entry.samples.size() < 8:
		var far := true
		for s: Vector3 in entry.samples:
			if s.distance_to(p) < 12.0: far = false; break
		if far: entry.samples.append(p.snapped(Vector3.ONE*.1))

func _report(ms: int) -> void:
	for title in ["PAREDE", "RESSALTO", "DEGRAU"]:
		var table: Dictionary = walls if title == "PAREDE" else (bumps if title == "RESSALTO" else ledges)
		var keys := table.keys()
		keys.sort_custom(func(a, b): return table[a].count > table[b].count)
		for key in keys:
			var entry: Dictionary = table[key]
			var extra := (" altura até %.1fm" % entry.max) if title == "PAREDE" else (" maior=%.3fm" % entry.max)
			print("%s %d%s %s em %s" % [title, entry.count, extra, key, entry.samples])
	print("DESERT_WALLS_DONE paredes=%d ressaltos=%d degraus=%d raios=%d em %.1f s" % [walls.size(), bumps.size(), ledges.size(), total_rays, ms/1000.0])
