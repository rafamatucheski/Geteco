extends SceneTree
## Independent frozen D3 builders recreate the entire geometry/collision hierarchy.
## Rendered 2+2 remains required for performance; this process owns no game save.
const BOX_BATCH := preload("res://runtime/transit/StaticBoxBatch.gd")
const TUNNEL := preload("res://gameplay/urban_v1/SecretTunnel3D.gd")
const TUNNEL_OLD := preload("res://tests/fixtures/startup_box_original/SecretTunnel3D.gd")
const DRESSING := preload("res://gameplay/urban_v1/VerticeSiteDressing.gd")
const DRESSING_OLD := preload("res://tests/fixtures/startup_box_original/VerticeSiteDressing.gd")
const HOMES := preload("res://gameplay/urban_v1/TruckersVillageHomes.gd")
const HOMES_OLD := preload("res://tests/fixtures/startup_box_original/TruckersVillageHomes.gd")
const VILLAGE := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
var checks := 0
var failures := 0
var geometry_errors: Array[String] = []
var compared_meshes := 0
var compared_vertices := 0
var compared_indices := 0

class VillageStub extends Node3D:
	var solids: Array[StaticBody3D] = []
	var placements: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RESIDUAL_BOX_GEOMETRY: "+label)

func same_arrays(expected: Array, actual: Array) -> bool:
	if expected.size()!=actual.size(): return false
	for field in expected.size():
		if typeof(expected[field])!=typeof(actual[field]): return false
		if expected[field]==null: continue
		if expected[field].size()!=actual[field].size(): return false
		if field==Mesh.ARRAY_INDEX:
			if expected[field]!=actual[field]: return false
			continue
		for index in expected[field].size():
			var a = expected[field][index]
			var b = actual[field][index]
			if typeof(a)==TYPE_FLOAT:
				# Native normal/tangent encoding quantizes committed attributes.
				if absf(a-b)>.002: return false
			elif typeof(a) in [TYPE_VECTOR2,TYPE_VECTOR3,TYPE_VECTOR4]:
				if a.distance_to(b)>.002: return false
			elif a!=b: return false
	return true

func same_mesh(a: Mesh, b: Mesh) -> bool:
	if (a==null)!=(b==null): return false
	if a==null: return true
	if a.get_class()!=b.get_class() or a.get_surface_count()!=b.get_surface_count(): return false
	if a.get_aabb().position.distance_to(b.get_aabb().position)>.0001 or a.get_aabb().size.distance_to(b.get_aabb().size)>.0001: return false
	for surface in a.get_surface_count():
		# These two methods are bound on ArrayMesh, not PrimitiveMesh in 4.7.2.
		if a is ArrayMesh:
			if a.surface_get_primitive_type(surface)!=b.surface_get_primitive_type(surface): return false
			if a.surface_get_format(surface)!=b.surface_get_format(surface): return false
		else:
			for property in a.get_property_list():
				if property.usage & PROPERTY_USAGE_STORAGE and not property.name in ["script","resource_name","resource_local_to_scene","resource_path","resource_scene_unique_id"]:
					if a.get(property.name)!=b.get(property.name): return false
		var old := a.surface_get_arrays(surface)
		var candidate := b.surface_get_arrays(surface)
		if not same_arrays(old,candidate): return false
		if a is ArrayMesh:
			compared_meshes += 1
			compared_vertices += old[Mesh.ARRAY_VERTEX].size()
			if old[Mesh.ARRAY_INDEX]!=null: compared_indices += old[Mesh.ARRAY_INDEX].size()
	return true

func material_signature(material: Material) -> Dictionary:
	var result := {}
	if material==null: return result
	for property in material.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and not property.name in ["script","resource_name","resource_local_to_scene","resource_path","resource_scene_unique_id"]:
			result[property.name]=material.get(property.name)
	return result

func compare_tree(a: Node, b: Node, path: String) -> bool:
	var ok := a.get_class()==b.get_class() and a.get_child_count()==b.get_child_count()
	if a is Node3D:
		ok = ok and a.transform==b.transform and a.visible==b.visible
	if a is GeometryInstance3D:
		ok = ok and a.layers==b.layers and a.cast_shadow==b.cast_shadow and material_signature(a.material_override)==material_signature(b.material_override)
	if a is MeshInstance3D:
		ok = ok and same_mesh(a.mesh,b.mesh)
	if a is CollisionObject3D:
		ok = ok and a.collision_layer==b.collision_layer and a.collision_mask==b.collision_mask
	if a is CollisionShape3D:
		ok = ok and a.disabled==b.disabled and a.shape.get_class()==b.shape.get_class()
		for property in a.shape.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and not property.name in ["script","resource_name","resource_local_to_scene","resource_path","resource_scene_unique_id"]:
				ok = ok and a.shape.get(property.name)==b.shape.get(property.name)
	if a is Light3D:
		ok = ok and a.light_color==b.light_color and a.light_energy==b.light_energy and a.shadow_enabled==b.shadow_enabled
	if a is Timer:
		ok = ok and a.wait_time==b.wait_time and a.one_shot==b.one_shot and a.autostart==b.autostart
	if a is Camera3D:
		ok = ok and a.projection==b.projection and a.size==b.size and a.fov==b.fov and a.cull_mask==b.cull_mask
	if a.has_meta("interior_solid_id") or b.has_meta("interior_solid_id"):
		ok = ok and a.get_meta("interior_solid_id",null)==b.get_meta("interior_solid_id",null)
	if not ok and geometry_errors.size()<12: geometry_errors.append(path)
	if a.get_child_count()!=b.get_child_count(): return false
	for index in a.get_child_count():
		ok = compare_tree(a.get_child(index),b.get_child(index),path+"/"+str(index)) and ok
	return ok

func cylinder_contract() -> void:
	# Actual builders use mixed cylinders/boxes, tapered radii and low radial counts.
	for params in [[8,0,1.0,1.0,true,true],[8,1,0.0,1.0,true,true],[10,1,.4,.4,true,true],[12,1,.1,.4,true,false],[16,4,.4,0.0,false,true],[32,6,.2,.3,false,false]]:
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments=params[0]
		cylinder.rings=params[1]
		cylinder.top_radius=params[2]
		cylinder.bottom_radius=params[3]
		cylinder.cap_top=params[4]
		cylinder.cap_bottom=params[5]
		var old := SurfaceTool.new()
		var candidate := SurfaceTool.new()
		old.begin(Mesh.PRIMITIVE_TRIANGLES)
		candidate.begin(Mesh.PRIMITIVE_TRIANGLES)
		var offset := 0
		for mesh in [BoxMesh.new(),cylinder,BoxMesh.new()]:
			old.append_from(mesh,0,Transform3D.IDENTITY)
			offset=BOX_BATCH.append_from(candidate,mesh,0,Transform3D.IDENTITY,offset)
		var expected := old.commit_to_arrays()
		var actual := candidate.commit_to_arrays()
		check(offset==actual[Mesh.ARRAY_VERTEX].size() and same_arrays(expected,actual),"Mixed offset/arrays for Cylinder params "+str(params))

func run() -> void:
	for frame in 2: await process_frame
	cylinder_contract()
	var old_stage := Node3D.new()
	var new_stage := Node3D.new()
	root.add_child(old_stage)
	root.add_child(new_stage)
	var dressing_old = DRESSING_OLD.new()
	var dressing = DRESSING.new()
	old_stage.add_child(dressing_old)
	new_stage.add_child(dressing)
	check(compare_tree(dressing_old,dressing,"Vertice"),"Complete Vertice hierarchy: arrays/format/materials/collision/transform")
	check(dressing.placements==dressing_old.placements and dressing.solids.size()==dressing_old.solids.size(),"Vertice physical placements/count conserved")
	var tunnel_old = TUNNEL_OLD.new()
	var tunnel = TUNNEL.new()
	old_stage.add_child(tunnel_old)
	new_stage.add_child(tunnel)
	tunnel_old.configure(null)
	tunnel.configure(null)
	check(compare_tree(tunnel_old,tunnel,"Tunnel"),"Complete Tunnel hierarchy including original manual puddle batches")
	check(tunnel.solids.size()==tunnel_old.solids.size() and tunnel.rats.size()==tunnel_old.rats.size() and tunnel.lights.size()==tunnel_old.lights.size(),"Tunnel population/solids/lights conserved")
	check(tunnel._rng.state==tunnel_old._rng.state and tunnel.sealed_open==tunnel_old.sealed_open and tunnel.vault_open==tunnel_old.vault_open and not tunnel.is_processing(),"Tunnel RNG, gate state and initial suspension conserved")
	for color in TUNNEL.MANUAL_BATCH_COLORS:
		var a = tunnel_old.get_node("TunnelBatch_"+color)
		var b = tunnel.get_node("TunnelBatch_"+color)
		check(a.mesh.surface_get_arrays(0)==b.mesh.surface_get_arrays(0) and a.mesh.surface_get_format(0)==b.mesh.surface_get_format(0),"Manual mixed palette "+color+" exact, original indices/attributes/format")
	var village_old := VillageStub.new()
	var village := VillageStub.new()
	old_stage.add_child(village_old)
	new_stage.add_child(village)
	var homes_old = HOMES_OLD.new()
	var homes = HOMES.new()
	village_old.add_child(homes_old)
	village.add_child(homes)
	homes_old.build(village_old,VILLAGE.HOME_LAYOUT)
	homes.build(village,VILLAGE.HOME_LAYOUT)
	check(compare_tree(homes_old,homes,"Homes"),"All six homes: arrays/format/materials/collision/transform")
	check(homes.homes.size()==6 and homes.solids.size()==homes_old.solids.size() and homes.furniture.size()==homes_old.furniture.size(),"Homes/population/furniture/solids counts conserved")
	check(homes.occupant_points==homes_old.occupant_points and homes.doorway_points==homes_old.doorway_points and homes.outside_points==homes_old.outside_points and homes.loot_points==homes_old.loot_points and village.placements==village_old.placements,"Same home spawn/access/loot/physical placement coordinates")
	check(compared_meshes>=300 and compared_vertices>50000 and compared_indices>50000,"Whole builders covered hundreds of committed meshes and original indices")
	print("RESIDUAL_BOX_GEOMETRY coverage meshes=",compared_meshes," vertices=",compared_vertices," indices=",compared_indices," mismatches=",geometry_errors)
	old_stage.free()
	new_stage.free()
	print("RESIDUAL_BOX_GEOMETRY ",checks-failures,"/",checks)
	quit(0 if failures==0 else 1)
