extends SceneTree
## Censo só leitura: ruas de origem e superfícies superiores quase coplanares amostradas.
## Entradas de lote na fila de exclusão ficam de fora; pares são candidatos,
## não defeitos automáticos (pintura, fundações e decks precisam de classificação).
const NATIVE := preload("res://world/regions/NativeRegion.gd")
const DESERT := preload("res://world/desert/DesertRegion.gd")
var cells := {}
var owners := {}
var pair_cells := {}
var mesh_count := 0
var serial := 0
var report := {}
var region_name := ""
var port_only := false
func _initialize() -> void: run.call_deferred()

func road_inventory(region: Node) -> Dictionary:
	var unique := {}
	var duplicates: Array = []
	var segments := {}
	var repeated: Array = []
	for road in region.roads:
		var points: Array[String] = []
		for p in road.points: points.append(str(p))
		var reverse := points.duplicate(); reverse.reverse()
		var forward_key := "|".join(points)
		var reverse_key := "|".join(reverse)
		var key := (forward_key if forward_key<reverse_key else reverse_key)+"/"+str(road.width)
		var id := str(road.get("id",unique.size()))
		if unique.has(key): duplicates.append([unique[key],id])
		else: unique[key]=id
		for i in range(points.size()-1):
			var a := points[i]; var b := points[i+1]
			var sk := (a+"/"+b if a<b else b+"/"+a)+"/"+str(road.width)
			if segments.has(sk): repeated.append([segments[sk],id,i])
			else: segments[sk]=id
	return {"road_records":region.roads.size(),"identical_whole_roads":duplicates,"repeated_segments":repeated,"record_cells":region.records.size()}

func label(node: Node,chunk: Node) -> String:
	var owner := node
	while owner!=chunk and owner!=null:
		if owner.get_script()!=null: return owner.get_script().resource_path.get_file()+"/"+str(node.name).split("#")[0]
		owner=owner.get_parent()
	return str(node.name)

func scan(chunk: Node3D) -> void:
	for node in chunk.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree(): continue
		var ancestor: Node=node
		var retired := false
		while ancestor!=null:
			if ancestor.is_queued_for_deletion(): retired=true; break
			ancestor=ancestor.get_parent()
		if retired: continue
		serial+=1
		var own := serial
		var sample_count := 0
		for surface in node.mesh.get_surface_count():
			var arrays: Array=node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var n := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,n,3):
				var a: Vector3=node.global_transform*vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3=node.global_transform*vertices[indices[i+1] if not indices.is_empty() else i+1]
				var c: Vector3=node.global_transform*vertices[indices[i+2] if not indices.is_empty() else i+2]
				var normal := (b-a).cross(c-a)
				if normal.length_squared()<.000001 or normal.normalized().y>-.8: continue
				if port_only and (minf(a.y,minf(b.y,c.y))<-.06 or maxf(a.y,maxf(b.y,c.y))>.3): continue
				var av:=Vector2(a.x,a.z); var bv:=Vector2(b.x,b.z); var cv:=Vector2(c.x,c.z)
				var low:=av.min(bv).min(cv); var high:=av.max(bv).max(cv)
				for x in range(floori(low.x),ceili(high.x)):
					for z in range(floori(low.y),ceili(high.y)):
						var p:=Vector2(x+.371,z+.613)
						if port_only and not Rect2(180,25,230,355).has_point(p): continue
						if not Geometry2D.point_is_inside_triangle(p,av,bv,cv): continue
						var height:=a.y-(normal.x*(p.x-a.x)+normal.z*(p.y-a.z))/normal.y
						var cell:=Vector2i(x,z)
						if not cells.has(cell): cells[cell]={}
						if not cells[cell].has(own): sample_count+=1
						cells[cell][own]=height
		if sample_count>0:
			mesh_count+=1
			owners[own]={"label":label(node,chunk),"path":str(node.get_path()),"samples_m2":sample_count}

func result() -> Dictionary:
	for cell in cells:
		var ids: Array=cells[cell].keys()
		for i in ids.size():
			for j in range(i+1,ids.size()):
				var delta: float=absf(cells[cell][ids[i]]-cells[cell][ids[j]])
				if delta>.035: continue
				var key:=str(mini(ids[i],ids[j]))+":"+str(maxi(ids[i],ids[j]))
				if not pair_cells.has(key): pair_cells[key]={"a":owners[ids[i]],"b":owners[ids[j]],"area_m2":0,"min_gap":delta,"max_gap":delta,"example":str(Vector3(cell.x+.371,cells[cell][ids[i]],cell.y+.613))}
				pair_cells[key].area_m2+=1
				pair_cells[key].min_gap=minf(pair_cells[key].min_gap,delta)
				pair_cells[key].max_gap=maxf(pair_cells[key].max_gap,delta)
	var pairs: Array=pair_cells.values()
	pairs.sort_custom(func(a,b): return a.area_m2>b.area_m2)
	return {"mesh_instances_with_upward_samples":mesh_count,"sampled_plan_area_m2":cells.size(),"near_coplanar_instance_pairs":pairs.size(),"pairs":pairs,"method":"1m grid; upper facing triangles; <=35mm vertical gap; excludes queued batching sources; pairs need semantic classification"}

func run() -> void:
	var selected := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--region="): selected=arg.trim_prefix("--region=")
	if not selected.is_empty() and FileAccess.file_exists("res://evidence/territory-ground-audit-20261014/census.json"):
		report=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/territory-ground-audit-20261014/census.json"))
	for id in ["harbor","mountain","desert"]:
		if not selected.is_empty() and id!=selected: continue
		var region: Node3D=DESERT.build_region() if id=="desert" else NATIVE.build_region(id)
		region.initial_prewarm_only=true
		root.add_child(region)
		region.set_process(false)
		region.prepare_data()
		var inventory:=road_inventory(region)
		print("TERRITORY_ROADS ",id," ",JSON.stringify(inventory))
		var keys: Dictionary={}
		if id=="harbor":
			for x in range(2,7):
				for z in range(0,6): keys[Vector2i(x,z)]=true
		elif id=="mountain":
			for entry in region.entries:
				if entry.id in ["ski_lodge","mountain_cabin","mountain_gas","mountain_bunker"]: keys[region._cell(entry.position)]=true
			keys[region._cell(region.spawn_position)]=true
			for entry in region.entries: print("MOUNTAIN_ENTRY ",entry.id," ",entry.position)
		else:
			for point in [Vector3(-180,0,-900),Vector3(-210,0,-920),Vector3(285,0,-750),Vector3(-965,0,-1262)]: keys[region._cell(point)]=true
		cells.clear(); owners.clear(); pair_cells.clear(); mesh_count=0; serial=0
		port_only=id=="harbor"
		for key in keys:
			if id=="desert": region._complete_focus_chunk(key)
			else: region._build_chunk(key)
			scan(region.chunks[key])
			print("GROUND_CELL ",id," ",key)
		var findings:=result()
		findings["chunks"]=keys.size()
		findings["roads"]=inventory
		report[id]=findings
		print("TERRITORY_GROUND ",id," meshes=",mesh_count," pairs=",findings.near_coplanar_instance_pairs)
		region.free()
		await process_frame
	DirAccess.make_dir_recursive_absolute("res://evidence/territory-ground-audit-20261014")
	FileAccess.open("res://evidence/territory-ground-audit-20261014/census.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	quit()
