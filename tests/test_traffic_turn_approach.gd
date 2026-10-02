extends SceneTree
const SIGNALS=preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const REGION=preload("res://world/editing/EditableRegion.gd")
const GRAPH=preload("res://gameplay/NativeTrafficRoutes.gd")
const VEHICLE=preload("res://scripts/Vehicle.gd")
var failures:=0
var checks:=0
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func run():
	var region=REGION.build_region("harbor");region.prepare_data()
	var graph=GRAPH.new();graph.configure(region.roads)
	var geometry=preload("res://world/urban_detail/HarborRoadGeometry3D.gd").new();geometry.configure(region.roads,false)
	SIGNALS.configure(graph,geometry.crossing_layout)
	var center=Vector3(188,0,78.125)
	var key=SIGNALS.key_of(center)
	# Reproduce the northbound outer lane turning west from Quay into Market.
	var route=graph.route_near(Vector3(193.25,0,100),1)
	check(route!=null,"Actual Quay to Market route exists")
	if route!=null:
		var item={}
		for junction in SIGNALS.along(route):
			if junction.key==key:item=junction
		check(not item.is_empty(),"Actual turn associates with Market/Quay controller")
		if not item.is_empty():
			SIGNALS.register_signal(center,7)
			var car=VEHICLE.new();car.route=route;car.half_length=2.45;car._sense_tick=false
			car.route_distance=float(item.get("stop_offset",item.offset-7))-car.half_length-1
			for phase in [2.0,17.6]:
				SIGNALS.owners.clear();car._release_junction()
				SIGNALS._phase_frame=Engine.get_process_frames();SIGNALS._phase_time=phase-SIGNALS._offset(center)
				var north_state=SIGNALS.signal_state(key,Vector3.FORWARD)
				var wait=car._junction_gate(route.get_baked_length(),bool(route.get_meta("traffic_open",false)))
				print("TURN_APPROACH state=",north_state," wait=",wait," item=",item)
				check(wait==(north_state=="red"),"Turning car obeys its arrival arm: "+north_state)
			car.free()
	region.free()
	print("TRAFFIC_TURN_APPROACH checks=",checks," failures=",failures)
	quit(1 if failures else 0)
