extends SceneTree
## Auditoria visual das peças de carroceria do tuning em todo carro compatível.
## Monta cada modelo como a vitrine da oficina (FleetCatalog.create + VehiclePaint +
## TuningAppearance), aplica as peças e grava imagens e um JSON por passada:
##   sport  : {"spoiler":"spoiler_sport"} — lateral (ortográfica de +X) e 3/4 traseira alta;
##   aero_a : saia com entradas + splitter + difusor de pista + asa GT (utilitário: estribo);
##   aero_b : saia esportiva + rabo de pato.
## As passadas aero gravam lateral, 3/4 dianteira baixa e 3/4 traseira baixa.
## O JSON traz bounds, interior (belt/roof/rear_top), a montagem do TuningAeroKit.spoiler_mount(), centro das
## lanternas/faróis (para conferir se +Z é a traseira), medidas do TuningAeroKit.body() e a
## caixa de cada peça montada, mais a contagem de triângulos com face virada para dentro.
## As peças na cor do carro saem num rosa de contraste: a auditoria é de encaixe, não de pintura.
## Precisa de janela (MultiMesh/visual erram no headless).
## Uso: tools/run_godot_locked.sh --path . --script res://tests/capture/capture_spoiler_audit.gd [-- passadas=sport,aero_a ids=a,b saida=rodada2 sem_imagens]
## Saída: res://evidence/spoiler-audit-20261027/
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PAINT := preload("res://runtime/VehiclePaint.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
const STREET := preload("res://gameplay/desert_cars/StreetPowertrainCatalog.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const ROOF := preload("res://gameplay/desert_cars/TuningSunroof.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const OUTPUT := "res://evidence/spoiler-audit-20261027/"
const TINT := Color("ff2fb0")
const PASSES := {
	"sport":{"car":{"spoiler":"spoiler_sport"},"utility":{},"views":["lateral","traseira34"]},
	"aero_a":{"car":{"skirts":"skirt_vented","front_lip":"lip_splitter","diffuser":"diffuser_race","spoiler":"spoiler_gt"},"utility":{"skirts":"skirt_step"},"views":["lateral","frente34_baixa","traseira34_baixa"]},
	"aero_b":{"car":{"skirts":"skirt_sport","spoiler":"spoiler_ducktail"},"utility":{},"views":["lateral","frente34_baixa","traseira34_baixa"]},
}
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	run.call_deferred()

static func candidate_ids() -> Array:
	var ids: Array = []
	for id in STREET.PROFILES.keys() + CARS.IDS + TUNING.SUNROOF_MODELS:
		if str(id) not in ids: ids.append(str(id))
	return ids

static func utility(id: String) -> bool:
	return str(STREET.PROFILES.get(id,{}).get("kind","")) == "utility" or id.contains("pickup") or id in ["desert_bison","digo_amarok_2014"]

## Só as peças que o catálogo deixa instalar neste carro.
static func parts_for(pass_name: String, id: String) -> Dictionary:
	var wanted: Dictionary = PASSES[pass_name].utility if utility(id) else PASSES[pass_name].car
	var result := {}
	for slot in wanted:
		if TUNING.compatible(wanted[slot],id): result[slot] = wanted[slot]
	return result

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("capture_spoiler_audit precisa de janela")
		quit(2)
		return
	var only: Array = []
	var passes: Array = PASSES.keys()
	var out_dir := ProjectSettings.globalize_path(OUTPUT)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("ids="): only = Array(arg.trim_prefix("ids=").split(","))
		elif arg.begins_with("passadas="): passes = Array(arg.trim_prefix("passadas=").split(","))
		# Subpasta por rodada (ex.: saida=rodada2), sempre dentro da pasta de evidência.
		elif arg.begins_with("saida="): out_dir = ProjectSettings.globalize_path(OUTPUT+arg.trim_prefix("saida=").trim_suffix("/")+"/")
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1280,720)
	_build_stage()
	var compat := {}
	for id in candidate_ids():
		compat[id] = {}
		for part in ["spoiler_sport","spoiler_gt","spoiler_ducktail","skirt_vented","skirt_sport","skirt_step","lip_splitter","diffuser_race","wheel_mesh","wheel_size_sport","taillights_amber","sunroof_glass"]:
			if TUNING.PARTS.has(part): compat[id][part] = TUNING.compatible(part,id)
	var report := {"generated":Time.get_datetime_string_from_system(),"compatibility":compat,"passes":{}}
	var failures := 0
	for pass_name in passes:
		var rows := {}
		for id in candidate_ids():
			if not only.is_empty() and id not in only: continue
			var parts := parts_for(pass_name,id)
			if parts.is_empty(): continue
			var row := await _audit(id,pass_name,parts,out_dir)
			rows[id] = row
			if row.has("error"): failures += 1
			print("SPOILER_AUDIT ",pass_name," ",id," ",JSON.stringify(row.get("summary",row.get("error",""))))
		report.passes[pass_name] = rows
	var file := FileAccess.open(out_dir+"spoiler_audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",false))
	file.close()
	print("SPOILER_AUDIT done failures=",failures," out=",out_dir)
	quit(1 if failures > 0 else 0)

func _build_stage() -> void:
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("5d6870")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("aab4bf")
	environment.environment.ambient_light_energy = .8
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,40,0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25,-140,0)
	fill.light_energy = .6
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40,40)
	ground.mesh = plane
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color("3b4146")
	ground.material_override = grey
	world.add_child(ground)
	camera = Camera3D.new()
	camera.near = .05
	camera.far = 100.0
	world.add_child(camera)
	camera.current = true

func _audit(id: String, pass_name: String, parts: Dictionary, out_dir: String) -> Dictionary:
	var model := FLEET.create(id)
	if model == null: return {"error":"FleetCatalog.create devolveu null"}
	world.add_child(model)
	var painter := PAINT.new()
	painter.bind(model,id)
	var paint := FLEET.default_paint(id,Color.WHITE)
	var appearance: RefCounted = preload("res://gameplay/desert_cars/TuningAppearance.gd").new()
	appearance.bind(model,painter)
	var kits: RefCounted = appearance._kits
	# Mesma leitura de TuningBodyKits._apply_spoiler (TuningAeroKit.spoiler_mount), antes das peças.
	var bounds := _bounds(model)
	var cabin: Dictionary = model.get_meta("vehicle_interior_spec",{})
	var mount: Dictionary = kits.aero.spoiler_mount()
	var hatch_branch := bool(mount.get("hatch",false))
	var row := {"parts":parts,"utility":utility(id),
		"bounds":{"position":_v(bounds.position),"end":_v(bounds.end),"size":_v(bounds.size)},
		"belt":cabin.get("belt",null),"roof":cabin.get("roof",null),"rear_top":cabin.get("rear_top",null),
		"hatch_branch":hatch_branch,
		"spoiler_z":snappedf(float(mount.get("z",0.0)),.001),"mount_height":snappedf(float(mount.get("y",0.0)),.001) if mount.has("y") else null,
		"mount_half_width":snappedf(float(mount.get("half_width",0.0)),.001),"roof_y":snappedf(float(mount.get("roof_y",0.0)),.001)}
	if pass_name == "sport":
		var lights := _lights(model)
		row["tail_center"] = _v(lights.tail) if lights.tail_count > 0 else null
		row["head_center"] = _v(lights.head) if lights.head_count > 0 else null
		var rear_plus_z = null
		if lights.tail_count > 0 and lights.head_count > 0: rear_plus_z = lights.tail.z > lights.head.z
		elif lights.tail_count > 0: rear_plus_z = lights.tail.z > bounds.get_center().z
		row["rear_is_plus_z"] = rear_plus_z
		var materials := {}
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.mesh == null: continue
			for surface in part.mesh.get_surface_count():
				var material := part.get_active_material(surface)
				if material != null: materials[material.resource_name] = true
		row["material_names"] = materials.keys()
	appearance.apply(parts,paint)
	# Contraste: só as peças na cor do carro (carbono e acabamento escuro ficam como são).
	if is_instance_valid(kits.spoiler): kits.spoiler.get_meta("paint_material").albedo_color = TINT
	for slot in kits.aero._paint_materials:
		for material in kits.aero._paint_materials[slot]: material.albedo_color = TINT
	if parts.has("spoiler") and not is_instance_valid(kits.spoiler):
		row["error"] = "aerofólio não foi montado"
	var mounted := {}
	if is_instance_valid(kits.spoiler): mounted["spoiler"] = _piece(kits.spoiler,model)
	for slot in kits.aero.nodes:
		if is_instance_valid(kits.aero.nodes[slot]): mounted[slot] = _piece(kits.aero.nodes[slot],model)
	for slot in parts:
		if slot != "spoiler" and not mounted.has(slot): mounted[slot] = {"missing":true}
	row["mounted"] = mounted
	if pass_name != "sport":
		var body: Dictionary = kits.aero.body()
		var snapped := {}
		# body() também guarda o perfil e os pontos da lata: só os números vão para o JSON.
		for key in body:
			if body[key] is float or body[key] is int: snapped[key] = snappedf(float(body[key]),.001)
		row["aero_body"] = snapped
		row["full_body"] = _full_body(model)
	var inverted := 0
	for slot in mounted: inverted += int(mounted[slot].get("inverted_triangles",0))
	row["summary"] = {"mount":row.mount_height,"z":row.spoiler_z,"hatch":hatch_branch,"inverted":inverted,"mounted":mounted.keys()}
	for view in PASSES[pass_name].views:
		if OS.get_cmdline_user_args().has("sem_imagens"): break
		_frame(view,bounds)
		await _save(out_dir+"%s_%s_%s.png" % [id,pass_name,view])
	world.remove_child(model)
	model.free()
	return row

func _frame(view: String, bounds: AABB) -> void:
	var center := bounds.get_center()
	if view == "lateral":
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(bounds.size.z,bounds.size.y*2.0)*1.08
		camera.position = Vector3(bounds.end.x+8.0,center.y,center.z)
		camera.look_at(center,Vector3.UP)
		return
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 34.0
	var focus: Vector3
	var direction: Vector3
	var distance := bounds.size.z*1.05+1.6
	match view:
		"traseira34":
			focus = Vector3(center.x,bounds.size.y*.55,center.z+bounds.size.z*.18)
			direction = Vector3(.80,.55,1.0)
			distance = bounds.size.z*1.25+2.2
		"frente34_baixa":
			focus = Vector3(center.x,bounds.size.y*.36,center.z-bounds.size.z*.14)
			direction = Vector3(.85,.16,-1.0)
		"traseira34_baixa":
			focus = Vector3(center.x,bounds.size.y*.36,center.z+bounds.size.z*.14)
			direction = Vector3(.85,.16,1.0)
	camera.position = focus+direction.normalized()*distance
	camera.look_at(focus,Vector3.UP)

func _save(path: String) -> void:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

static func _v(value: Vector3) -> Array:
	return [snappedf(value.x,.001),snappedf(value.y,.001),snappedf(value.z,.001)]

static func _bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var box: AABB = ROOF.relative_transform(part,model)*part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

## Caixa da peça no espaço do modelo e triângulos de malha gerada cuja face da frente
## (horário no Godot) aponta para dentro da própria peça: esses somem vistos de fora.
## O centro de referência é por lado (x<0 e x>0) quando a malha tem as duas metades.
static func _piece(node: Node3D, model: Node3D) -> Dictionary:
	var box := AABB()
	var first := true
	var inverted := 0
	var triangles := 0
	for part: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var xf := ROOF.relative_transform(part,model)
		var aabb: AABB = xf*part.mesh.get_aabb()
		box = aabb if first else box.merge(aabb)
		first = false
		if part.mesh is PrimitiveMesh: continue
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			var split := part.mesh.get_aabb().position.x < -.2 and part.mesh.get_aabb().end.x > .2
			var sums := {-1:Vector3.ZERO,1:Vector3.ZERO,0:Vector3.ZERO}
			var counts := {-1:0,1:0,0:0}
			for i in range(0,count,3):
				var c := Vector3.ZERO
				for j in 3: c += vertices[indices[i+j] if not indices.is_empty() else i+j]
				c /= 3.0
				var key := (1 if c.x > 0 else -1) if split else 0
				sums[key] += c
				counts[key] += 1
			for i in range(0,count,3):
				var a: Vector3 = vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = vertices[indices[i+1] if not indices.is_empty() else i+1]
				var c: Vector3 = vertices[indices[i+2] if not indices.is_empty() else i+2]
				var centre := (a+b+c)/3.0
				var key := (1 if centre.x > 0 else -1) if split else 0
				var reference: Vector3 = sums[key]/maxi(1,counts[key])
				triangles += 1
				if (b-a).cross(c-a).dot(centre-reference) > 0.0: inverted += 1
	return {"aabb_position":_v(box.position),"aabb_end":_v(box.end),"generated_triangles":triangles,"inverted_triangles":inverted}

## Carroceria inteira (qualquer material, sem rodas nem peças do tuning): ponta e fundo de
## frente/traseira. O TuningAeroKit mede só a pintura; para-choque de outro material fica de fora.
static func _full_body(model: Node3D) -> Dictionary:
	var points := PackedVector3Array()
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center") or not part.is_visible_in_tree(): continue
		if str(model.get_path_to(part)).contains("Tuning") or part.name in ["Interior","InteriorAlpha"]: continue
		var xf := ROOF.relative_transform(part,model)
		for surface in part.mesh.get_surface_count():
			var arrays := MESH_ARRAYS.arrays_of(part.mesh,surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
			for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]: points.append(xf*v)
	var nose := INF
	var tail := -INF
	for p in points:
		nose = minf(nose,p.z)
		tail = maxf(tail,p.z)
	var front_bottom := INF
	var rear_bottom := INF
	for p in points:
		if p.z < nose+.35: front_bottom = minf(front_bottom,p.y)
		if p.z > tail-.35: rear_bottom = minf(rear_bottom,p.y)
	return {"nose":snappedf(nose,.001),"tail":snappedf(tail,.001),"front_bottom_y":snappedf(front_bottom,.001),"rear_bottom_y":snappedf(rear_bottom,.001)}

## Centro médio (no espaço do modelo) dos vértices das lentes traseiras e dianteiras.
static func _lights(model: Node3D) -> Dictionary:
	var sums := {"tail":Vector3.ZERO,"head":Vector3.ZERO}
	var counts := {"tail":0,"head":0}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var xf := ROOF.relative_transform(part,model)
		for surface in part.mesh.get_surface_count():
			var role := ROLES.key(part,surface)
			var material := part.get_active_material(surface)
			var name := material.resource_name if material != null else ""
			var kind := ""
			if ROLES.is_tail_lens(role) or ROLES.is_tail_lens(name): kind = "tail"
			elif ROLES.is_headlight_lens(role) or ROLES.is_headlight_lens(name): kind = "head"
			if kind.is_empty(): continue
			var arrays := MESH_ARRAYS.arrays_of(part.mesh,surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null: continue
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				sums[kind] += xf*vertex
				counts[kind] += 1
	return {"tail":sums.tail/maxi(1,counts.tail),"head":sums.head/maxi(1,counts.head),"tail_count":counts.tail,"head_count":counts.head}
