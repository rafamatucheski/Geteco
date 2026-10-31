extends SceneTree
const ROUTES := preload("res://runtime/regional/RegionalCoachRoute.gd")
const COACH := preload("res://runtime/regional/RegionalCoach.gd")
class Controller extends RefCounted:
	var state = preload("res://runtime/GameState.gd").new()
	var regions := {}
	func _build_region(id: String) -> Node3D:
		return preload("res://world/editing/EditableRegion.gd").build_region(id)
class LightWorld extends Node3D:
	var production := {"state":{"world_state":{"time":.9,"weather":0}}}
	var player: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	print("REGIONAL_COACH_NETWORK ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func run() -> void:
	var controller := Controller.new()
	check(not ROUTES.plan(controller,"harbor","desert").ok,"Desert requires final Harbor mission")
	controller.state.campaign.restore_snapshot(preload("res://tests/fixtures/NorthGatewayFixtures.gd").prefix(preload("res://data/campaign/HarborMissions.gd").ORDER.size()))
	for from in ["harbor","mountain","desert"]:
		for to in ["harbor","mountain","desert"]:
			if from==to: continue
			var plan := ROUTES.plan(controller,from,to)
			print("COACH_ROUTE ",from," -> ",to," ",plan.get("reason","")," gaps=",plan.get("start_gap",INF),"/",plan.get("end_gap",INF)," length=",plan.get("length",0))
			check(plan.get("ok",false),"Authored directed route "+from+" -> "+to)
			if not plan.get("ok",false): continue
			check(plan.get("native",false),"Route search executes C# "+from+" -> "+to)
			if to=="mountain":
				# As duas ruas de chegada continuam fisicamente avançando para o sul pela
				# bifurcação do gelo. O antigo gancho de faixa voltava quase um metro para o norte.
				var turn: float=plan.curve.get_closest_offset(Vector3(691,0,-413))
				var backwards := 0.0
				for step in 32:
					var before: Vector3=plan.curve.sample_baked(turn-4+step*.25,true)
					var after: Vector3=plan.curve.sample_baked(turn-4+(step+1)*.25,true)
					backwards=maxf(backwards,after.z-before.z)
				check(backwards<.03,"Ice access follows southbound road without reversing lane hook from "+from)
			if "--dump-approach" in OS.get_cmdline_user_args() and from=="harbor" and to=="mountain":
				var tail := []
				for offset in range(floori(plan.length)-100,ceili(plan.length),2):
					tail.append({"offset":offset,"point":str(plan.curve.sample_baked(offset,true))})
				var edges := []
				for index in range(maxi(0,plan.nodes.size()-8),plan.nodes.size()-1):
					var edge: Dictionary=ROUTES._graph._edge(plan.nodes[index],plan.nodes[index+1])
					edges.append({"from":edge.from,"to":edge.to,"a":str(ROUTES._graph.vertices[edge.from]),"b":str(ROUTES._graph.vertices[edge.to]),"width":edge.width,"id":edge.id})
				var geometry: Dictionary=ROUTES._graph._curve_geometry(plan.nodes,false)
				for index in range(maxi(0,geometry.points.size()-9),geometry.points.size()-1):
					print("COACH_GEOMETRY ",geometry.points[index]," -> ",geometry.points[index+1]," section=",geometry.sections[index].id)
				print("COACH_APPROACH_CURVE ",JSON.stringify({"tail":tail,"edges":edges}))
	var light_world := LightWorld.new()
	root.add_child(light_world)
	light_world.player=Node3D.new(); light_world.add_child(light_world.player)
	var bus := COACH.new()
	light_world.add_child(bus)
	check(bus.passengers.size()==6 and is_instance_valid(bus.driver),"Six seated passengers and driver exist")
	check(bus.passengers.all(func(person): return person.visible and person.sit_amount==1.0 and not person.is_processing()),"Seated rigs visible without individual frame loops")
	bus.traffic=true
	bus.equipment._refresh()
	check(bus.equipment.auto_lit and bus.equipment.npc_beam.visible and bus.equipment._budget_request().decal == null,"Shared heavy bus headlight illuminates at night")
	light_world.production.state.world_state.time=.5
	bus.equipment._refresh()
	check(not bus.equipment.auto_lit and not bus.equipment.npc_beam.visible,"Daylight switches off the night beam")
	check(bus.is_physics_processing() and bus.is_in_group("public_transport_vehicle") and preload("res://audio/VehicleEngineProfile.gd").family(bus.archetype)=="bus","Shared nearby engine mixer discovers the scheduled bus")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size=Vector3(8,5,.25)
	shape.shape=box; wall.add_child(shape); wall.position=Vector3(0,2,-5)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	check(bus.test_move(bus.global_transform,Vector3(0,0,-10)),"Coach hull sweeps against a real wall")
	check(not bus.test_move(bus.global_transform,Vector3(0,0,2)),"Unobstructed reverse space remains clear")
	var berth_route := Curve3D.new()
	berth_route.add_point(Vector3.ZERO); berth_route.add_point(Vector3(0,0,-100))
	bus.set_service_route(berth_route)
	bus.position=Vector3(0,0,-95.42); bus.route_distance=95.42
	check(bus.arrived(),"Stopped coach docks when front reaches berth despite a queue beyond")
	bus.speed=1.0
	check(not bus.arrived(),"Moving coach cannot finish docking")
	bus.speed=0.0; bus.position.x=20
	check(not bus.arrived(),"Route projection alone cannot admit a coach away from berth")
	bus.position=Vector3(0,0,-52); bus.route_distance=52
	check(not bus.arrived(),"Ice approach blockage 48 metres away cannot count as arrival")
	bus.free(); wall.free(); light_world.free()
	print("REGIONAL_COACH_NETWORK_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
