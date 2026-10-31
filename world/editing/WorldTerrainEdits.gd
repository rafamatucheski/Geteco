@tool
extends RefCounted
## Campo de pincel imutável compartilhado por vértices do terreno, colisão e consultas de altura.
## Nada é aplicado ao mundo salvo até o editor salvar o documento explicitamente.
const CELL := 64.0
const MOTOCROSS_BOUNDS := Rect2(-247,-147,155,112)
const SURFACES := ["keep","grass","earth","sand","gravel","rock","snow","asphalt"]
var target := ""
var cells := {}
var brushes: Array[Dictionary] = []

static func new_brush(at: Vector2, surface_target := "") -> Dictionary:
	var chosen := surface_target if not surface_target.is_empty() else ("motocross" if MOTOCROSS_BOUNDS.has_point(at) else "mountain")
	return {"id":"terrain/%d_%d" % [Time.get_ticks_usec(),randi()],"type":"terrain","target":chosen,"position":[at.x,at.y],"rotation":0.0,"radius":12.0,"mode":"offset","height":0.0,"strength":1.0,"falloff":.5,"surface":"earth","affect_track":false,"order":int(Time.get_unix_time_from_system()*1000.0)}

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func validate_row(row: Dictionary) -> String:
	if not str(row.get("id","")).begins_with("terrain/"): return "Identidade do pincel de terreno inválida."
	if row.get("target","") not in ["motocross","mountain"]: return "Terreno sem gerador de altura editável."
	var at: Variant = row.get("position")
	if not at is Array or at.size() != 2 or not _number(at[0]) or not _number(at[1]) or absf(float(at[0])) > 10000 or absf(float(at[1])) > 10000: return "Centro do pincel inválido."
	if row.target == "motocross" and not MOTOCROSS_BOUNDS.has_point(Vector2(at[0],at[1])): return "O pincel deve ficar dentro do terreno do motocross."
	var minimum := 4.0 if row.target == "mountain" else 2.0
	if not _number(row.get("radius")) or float(row.radius) < minimum or float(row.radius) > 256: return "Raio do pincel: %.0f a 256 m." % minimum
	if row.get("mode","") not in ["offset","flatten"]: return "Modo de escultura inválido."
	if not _number(row.get("height")) or absf(float(row.height)) > 100: return "Altura do pincel: -100 a 100 m."
	if row.target == "motocross" and row.mode == "flatten" and float(row.height) < 0: return "A base do motocross fica na cota 0 m."
	if not _number(row.get("strength")) or float(row.strength) < 0 or float(row.strength) > 1: return "Força do pincel: 0 a 1."
	if not _number(row.get("falloff")) or float(row.falloff) < .05 or float(row.falloff) > 1: return "Suavidade da borda: 0,05 a 1."
	if row.get("surface","") not in SURFACES: return "Material de terreno inválido."
	if not row.get("affect_track",false) is bool: return "Opção de incluir pista inválida."
	if not _number(row.get("order",0)) or float(row.get("order",0)) < 0 or float(row.get("order",0)) > 9000000000000000: return "Ordem do pincel inválida."
	return ""

static func from_engine(area: String, surface_target: String) -> RefCounted:
	var source: Variant = Engine.get_meta("geteco_world_edit_document") if Engine.has_meta("geteco_world_edit_document") else null
	if not source is Dictionary:
		var loaded: Dictionary = load("res://world/editing/WorldEditData.gd").read_document()
		source = loaded.get("document",{})
	var result = load("res://world/editing/WorldTerrainEdits.gd").new()
	result.configure(source,surface_target,area)
	return result

func configure(document: Dictionary, surface_target: String, area: String) -> void:
	target = surface_target
	cells.clear()
	brushes.clear()
	for value in document.get("regions",{}).get(area,{}).values():
		if not value is Dictionary or value.get("type","") != "terrain" or value.get("target","") != target or value.get("deleted",false): continue
		if not validate_row(value).is_empty(): continue
		brushes.append(value.duplicate(true))
	brushes.sort_custom(func(a,b):
		var ao := int(a.get("order",0))
		var bo := int(b.get("order",0))
		return ao < bo if ao != bo else str(a.id) < str(b.id))
	for row in brushes:
		var at := Vector2(row.position[0],row.position[1])
		var radius := float(row.radius)
		row["center"] = at
		for x in range(floori((at.x-radius)/CELL),floori((at.x+radius)/CELL)+1):
			for z in range(floori((at.y-radius)/CELL),floori((at.y+radius)/CELL)+1):
				var key := Vector2i(x,z)
				if not cells.has(key): cells[key] = []
				cells[key].append(row)

func _bucket(point: Vector2) -> Array:
	return cells.get(Vector2i(floori(point.x/CELL),floori(point.y/CELL)),[])

func weight(row: Dictionary, point: Vector2) -> float:
	var distance := point.distance_to(row.center)
	var radius := float(row.radius)
	if distance >= radius: return 0.0
	var result := (1.0-smoothstep(radius*(1.0-float(row.falloff)),radius,distance))*float(row.strength)
	if target == "motocross":
		var edge := minf(minf(point.x-MOTOCROSS_BOUNDS.position.x,MOTOCROSS_BOUNDS.end.x-point.x),minf(point.y-MOTOCROSS_BOUNDS.position.y,MOTOCROSS_BOUNDS.end.y-point.y))
		result *= smoothstep(0.0,4.0,edge)
	return result

func height_at(point: Vector2, original: float, track_only := false) -> float:
	if cells.is_empty(): return original
	var height := original
	for row: Dictionary in _bucket(point):
		if track_only and not row.get("affect_track",false): continue
		if row.mode == "offset" and is_zero_approx(float(row.height)): continue
		var blend := weight(row,point)
		if blend <= 0: continue
		height = lerpf(height,float(row.height),blend) if row.mode == "flatten" else height+float(row.height)*blend
	if target == "motocross": return maxf(.002,height)
	return clampf(height,-1000.0,1000.0)

func paint_weights(point: Vector2, track_only := false) -> PackedFloat32Array:
	var result := PackedFloat32Array([0,0,0,0,0,0,0])
	for row: Dictionary in _bucket(point):
		if row.surface == "keep" or (track_only and not row.get("affect_track",false)): continue
		var blend := weight(row,point)
		if blend <= 0: continue
		for i in result.size(): result[i] *= 1.0-blend
		result[SURFACES.find(str(row.surface))-1] += blend
	return result

func has_paint_in(rect: Rect2, track_only := false) -> bool:
	for row in brushes:
		if row.surface == "keep" or float(row.strength) <= 0 or (track_only and not row.get("affect_track",false)): continue
		var at: Vector2 = row.center
		if at.distance_to(at.clamp(rect.position,rect.end)) < float(row.radius): return true
	return false

## Dados só de CPU: seguro para a tarefa de WorkerThreadPool do MountainTerrain3D.
func paint_maps(rect: Rect2, spacing := 2.0, track_only := false) -> Dictionary:
	if not has_paint_in(rect,track_only): return {}
	var columns := maxi(2,ceili(rect.size.x/spacing)+1)
	var rows := maxi(2,ceili(rect.size.y/spacing)+1)
	var a := PackedByteArray()
	var b := PackedByteArray()
	a.resize(columns*rows*4)
	b.resize(columns*rows*4)
	for z in rows:
		for x in columns:
			var point := rect.position+Vector2(float(x)/(columns-1),float(z)/(rows-1))*rect.size
			var values := paint_weights(point,track_only)
			var offset := (z*columns+x)*4
			for i in 4: a[offset+i] = clampi(roundi(values[i]*255.0),0,255)
			for i in 3: b[offset+i] = clampi(roundi(values[i+4]*255.0),0,255)
	return {"size":Vector2i(columns,rows),"a":a,"b":b,"origin":rect.position,"extent":rect.size}

static func bind_paint(material: ShaderMaterial, maps: Dictionary) -> void:
	material.set_shader_parameter("editor_terrain_paint_enabled",not maps.is_empty())
	if maps.is_empty(): return
	var size: Vector2i = maps.size
	material.set_shader_parameter("editor_terrain_paint_a",ImageTexture.create_from_image(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,maps.a)))
	material.set_shader_parameter("editor_terrain_paint_b",ImageTexture.create_from_image(Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,maps.b)))
	material.set_shader_parameter("editor_terrain_paint_origin",maps.origin)
	material.set_shader_parameter("editor_terrain_paint_extent",maps.extent)
	material.set_shader_parameter("editor_terrain_paint_size",Vector2(size))
	material.set_shader_parameter("editor_terrain_grass",preload("res://assets/materials/woodland/woodland.png"))
	material.set_shader_parameter("editor_terrain_earth",preload("res://assets/materials/woodland/earth.png"))
