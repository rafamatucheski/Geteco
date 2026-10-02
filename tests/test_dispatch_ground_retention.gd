extends SceneTree
## Contrato produção de retenção/admissão/poda; não mede FPS nem direção.
const PROD=preload("res://runtime/ProductionWorld.gd")
const CONTROLLER=preload("res://gameplay/dispatch/DispatchController.gd")
const UNIT=preload("res://gameplay/dispatch/DispatchUnit.gd")
const CONNECTION=preload("res://world/regions/WorldConnection3D.gd")
class DrivingProbe extends RefCounted:
	var car:CharacterBody3D
class WorldProbe extends Node3D:
	var production:Node
	var player:Node3D
	var dispatch:Node
	var driving:=DrivingProbe.new()
class CarProbe extends CharacterBody3D:
	var half_width:=1.0
	var half_length:=2.0
class RegionProbe extends "res://world/regions/NativeRegion.gd":
	func _ready()->void:pass
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print(("PASS " if ok else "FAIL ")+label)
	if not ok:failures.append(label)
func region(scene:Node3D,id:String)->RegionProbe:
	var value:=RegionProbe.new();value.region_id=id;value.prepare_data();value.prepared=true
	value.set_process(false);value.set_physics_process(false);scene.add_child(value)
	return value
func run()->void:
	var scene:=WorldProbe.new();root.add_child(scene)
	scene.player=Node3D.new();scene.player.position=Vector3(630,0,-285);scene.add_child(scene.player)
	var production:Node=PROD.new()
	# Contraprova usa snapshot imutável anterior, sem reverter o checkout.
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--ground-baseline-production="):
			production.free()
			var baseline:Script=load(arg.trim_prefix("--ground-baseline-production="))
			if baseline==null:push_error("Snapshot baseline não carregou");quit(2);return
			production=baseline.new()
	production.world=scene;production.traffic_routes=null
	production.state.set_location("mountain");production.set_process(false);production.set_physics_process(false)
	scene.production=production;scene.add_child(production)
	var harbor:=region(scene,"harbor");var mountain:=region(scene,"mountain")
	production.regions={"harbor":harbor,"mountain":mountain};production.region=mountain
	var controller:=CONTROLLER.new();controller.world=scene;controller.set_physics_process(false)
	controller.player_position_override=scene.player.position
	scene.dispatch=controller;scene.add_child(controller)
	var car:=CarProbe.new();car.position=Vector3(400,0,-285);car.rotation.y=-PI*.5;scene.add_child(car);car.set_physics_process(true)
	var unit:=UNIT.new();unit.vehicle=car;controller.units.append(unit)
	var key:Vector2i=harbor._cell(car.global_position)
	var last_id:=0;var builds:=0
	for cycle in 30:
		production._update_physical_residency(scene.player.position)
		controller._prepare_unit_ground(unit)
		if harbor.chunks.has(key):
			var id:int=harbor.chunks[key].get_instance_id()
			if id!=last_id:builds+=1
			last_id=id
	check(builds==1,"30 ciclos produtivos conservam uma construção da célula ativa: %d"%builds)
	await physics_frame
	var floor_query:=PhysicsRayQueryParameters3D.create(car.global_position+Vector3.UP,car.global_position-Vector3.UP,1)
	check(not scene.get_world_3d().direct_space_state.intersect_ray(floor_query).is_empty(),"célula retida preserva collider de apoio físico")
	check(harbor.chunks.has(key),"corpo ativo mantém chão fora do raio do foco")
	if production.has_method("_active_dispatch_support"):
		var support:Dictionary=production._active_dispatch_support()
		check(support.harbor.size()==2 and support.mountain.is_empty(),"retenção limita-se ao corpo e antecipação do dono residente")
		car.position.x=455
		support=production._active_dispatch_support()
		check(support.harbor.size()==1 and support.mountain.size()==1,"antecipação resolve dono distinto na costura")
		production._update_physical_residency(scene.player.position)
		check(not harbor.chunks.has(key),"sair da célula libera suporte e permite poda")
		var seam_key:Vector2i=harbor._cell(car.global_position)
		unit.suspended=true
		production._update_physical_residency(scene.player.position)
		controller._prepare_unit_ground(unit)
		check(not harbor.chunks.has(seam_key),"suspensão libera chão distante e não o reconstrói")
		car.hide();car.set_physics_process(false)
		controller.player_position_override=car.position+Vector3(105,0,0)
		production._update_physical_residency(controller.player_position_override)
		controller._prepare_unit_ground(unit)
		check(production._active_dispatch_support().harbor.size()==1 and harbor.chunks.has(seam_key),"retomada próxima admite apoio antes de mostrar ou reativar corpo")
		controller.player_position_override=scene.player.position
		production._update_physical_residency(scene.player.position)
		check(production._active_dispatch_support().harbor.is_empty() and not harbor.chunks.has(seam_key),"afastar da retomada libera novamente apoio provisório")
		car.show();car.set_physics_process(true)
		unit.suspended=false;unit.finished=true
		production._update_physical_residency(scene.player.position)
		controller._prepare_unit_ground(unit)
		check(production._active_dispatch_support().harbor.is_empty() and not harbor.chunks.has(seam_key),"unidade finalizada não retém nem admite chão")
		unit.finished=false;car.set_physics_process(false)
		check(production._active_dispatch_support().harbor.is_empty(),"corpo não físico não retém células")
		car.set_meta("awaiting_ground",true)
		check(production._active_dispatch_support().harbor.size()==1,"corpo aguardando seu chão preserva pedido de retomada")
		car.remove_meta("awaiting_ground");car.set_physics_process(true)
		production.regions.erase("harbor")
		check(production._active_dispatch_support().harbor.is_empty() and not production.regions.has("harbor"),"pedido não monta dono ausente")
		production.regions.harbor=harbor
		controller.units.clear()
		check(production._active_dispatch_support().harbor.is_empty(),"remoção da unidade não deixa registro de suporte")
	else:check(false,"contrato de suporte de despacho disponível")
	# The unit is fixture-owned; do not invoke gameplay teardown on the bare car.
	controller.units.clear()
	scene.free()
	print("%s DISPATCH_GROUND_RETENTION checks=%d builds=%d failures=%s"%["PASS" if failures.is_empty() else "FAIL",checks,builds,failures])
	quit(0 if failures.is_empty() else 1)
