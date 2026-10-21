extends SceneTree
## Identidade, geometria física e cancelamento do cache de registros/trechos.
const REGION := preload("res://world/regions/NativeRegion.gd")
class RegionProbe extends "res://world/regions/NativeRegion.gd":
	func _ready() -> void: pass

var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("STREAM_REUSE_TEST ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	var owner := RegionProbe.new()
	root.add_child(owner)
	owner.set_process(false)
	var record := {"kind":"harbor_route_zone","zone_id":"rodoviaria","position":Vector3(106.25,0,70.625)}
	var chunk := Node3D.new()
	owner.add_child(chunk)
	var job := {}
	check(not owner._step_record_build(chunk,record,job,0),"zona fria cede depois de uma peça")
	check(chunk.get_child_count()==0,"zona parcial não publica colisões nem aparência")
	while not owner._step_record_build(chunk,record,job,1000): await process_frame
	var key: String=owner._record_cache_key(record)
	var zone: Node3D=owner._record_cache[key][0]
	var bodies := zone.find_children("*","StaticBody3D",true,false).size()
	check(bodies>0,"zona completa mantém colisão real do mobiliário")
	await physics_frame
	await physics_frame
	var query:=PhysicsRayQueryParameters3D.create(Vector3(98.5,3,71),Vector3(98.5,-1,71),1)
	check(not owner.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"banco bloqueia fisicamente antes do descarregamento")
	owner._detach_cached_records(chunk)
	check(zone.get_parent()==null,"zona fica guardada sem depender do chunk")
	chunk.free()
	for cycle in 3:
		chunk=Node3D.new()
		owner.add_child(chunk)
		check(owner._step_record_build(chunk,record,{},0),"retorno não refaz peças")
		check(chunk.get_child(0)==zone,"retorno preserva a mesma instância")
		check(zone.find_children("*","StaticBody3D",true,false).size()==bodies,"retorno não duplica colisores")
		await physics_frame
		await physics_frame
		check(not owner.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),"retorno restaura colisão física")
		owner._detach_cached_records(chunk)
		chunk.free()
	var pending := {}
	var other:=record.duplicate()
	other.zone_id="delegacia"
	other.position=Vector3(67.5,0,132.5)
	chunk=Node3D.new()
	owner.add_child(chunk)
	owner._step_record_build(chunk,other,pending,0)
	var partial: WeakRef=weakref(pending.route_zone.root)
	owner._cancel_record_build(pending)
	check(partial.get_ref()==null and pending.is_empty(),"cancelamento libera a zona parcial")
	var warmed:=Node3D.new()
	owner.add_child(warmed)
	var warm_body:=StaticBody3D.new()
	var warm_shape:=CollisionShape3D.new()
	warm_shape.shape=BoxShape3D.new()
	warm_body.add_child(warm_shape)
	warmed.add_child(warm_body)
	warmed.position=Vector3(200,0,0)
	var warm_query:=PhysicsRayQueryParameters3D.create(Vector3(200,3,0),Vector3(200,-3,0),1)
	warmed.set_meta("warm_tunnel_key",Vector2i(3,0))
	owner._keep_warm_tunnel_chunk(warmed)
	check(not warmed.visible and not warmed.can_process(),"trecho guardado fica invisível e suspenso")
	await physics_frame
	await physics_frame
	check(owner.get_world_3d().direct_space_state.intersect_ray(warm_query).is_empty(),"trecho oculto não deixa colisão fantasma")
	var unrelated_chunk:=Node3D.new()
	owner.add_child(unrelated_chunk)
	var unrelated: Dictionary={"key":Vector2i(99,99),"chunk":unrelated_chunk,"stage":4}
	owner.build_jobs.append(unrelated)
	owner._ensure_chunk_surfaces(Vector2i(3,0))
	check(owner.chunks[Vector2i(3,0)]==warmed and warmed.visible,"visita reaproveita trecho completo do túnel")
	check(owner.build_jobs.size()==1 and owner.build_jobs[0]==unrelated,"reuso não remove nem reordena trabalho de outro trecho")
	owner.build_jobs.clear()
	await physics_frame
	await physics_frame
	check(not owner.get_world_3d().direct_space_state.intersect_ray(warm_query).is_empty(),"trecho reativado recupera sua colisão")
	owner.chunks.erase(Vector2i(3,0))
	owner._retire_chunk(warmed)
	check(owner._warm_tunnel_chunks.has(Vector2i(3,0)),"saída preserva trecho para nova visita")
	owner.free()
	await process_frame
	print("NATIVE_STREAM_REUSE checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
