extends SceneTree
const SIGNALS=preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func visible_state(mesh:MultiMesh,index:int)->String:
	var color=mesh.get_instance_color(index)
	return "green" if color.g>.85 else ("amber" if color.g>.3 else "red")
func _initialize():
	# RendererDummy does not retain MultiMesh instance colors for readback.
	if DisplayServer.get_name()=="headless":
		print("TRAFFIC_SIGNAL_VISUAL_SYNC requires a rendered run")
		quit(2);return
	var graph={"vertices":[Vector3.ZERO,Vector3(30,0,0),Vector3(-30,0,0),Vector3(0,0,30),Vector3(0,0,-30)],"edges":{0:[{"to":1},{"to":2},{"to":3},{"to":4}]}}
	SIGNALS.configure(graph)
	SIGNALS.register_signal(Vector3.ZERO,7)
	var mesh=MultiMesh.new()
	mesh.transform_format=MultiMesh.TRANSFORM_3D
	mesh.use_colors=true
	mesh.mesh=BoxMesh.new()
	mesh.instance_count=2
	SIGNALS.register_lens(mesh,0,Vector3.ZERO,Vector3.RIGHT)
	SIGNALS.register_lens(mesh,1,Vector3.ZERO,Vector3.BACK)
	# Pin the frame clock only in this fixture; no sleeping or production test hook.
	SIGNALS._phase_frame=Engine.get_process_frames()
	for sample in [[0.0,"green","red"],[10.999,"green","red"],[11.01,"amber","red"],[14.01,"red","red"],[15.61,"red","green"],[26.61,"red","amber"],[29.61,"red","red"],[31.21,"green","red"]]:
		SIGNALS._phase_time=sample[0]
		SIGNALS.update_lenses()
		check(visible_state(mesh,0)==sample[1] and visible_state(mesh,1)==sample[2],"Visible phase immediately follows boundary at "+str(sample[0]))
		check(SIGNALS.signal_state(Vector3i.ZERO,Vector3.RIGHT)==sample[1] and SIGNALS.signal_state(Vector3i.ZERO,Vector3.BACK)==sample[2],"Drivers see the same phase at "+str(sample[0]))
	# A newly streamed lens must initialize even while every existing phase is stable.
	var streamed=MultiMesh.new()
	streamed.transform_format=MultiMesh.TRANSFORM_3D
	streamed.use_colors=true
	streamed.mesh=BoxMesh.new()
	streamed.instance_count=1
	SIGNALS.register_lens(streamed,0,Vector3.ZERO,Vector3.BACK)
	SIGNALS.update_lenses()
	check(visible_state(streamed,0)=="red","Newly streamed signal initializes during stable phase")
	# Changing the graph's axis invalidates the visual association immediately.
	SIGNALS.configure(graph)
	SIGNALS.axes[Vector3i.ZERO]=Vector2.DOWN
	SIGNALS.update_lenses()
	check(visible_state(mesh,0)=="red" and visible_state(mesh,1)=="green","Graph rebuild refreshes lens axis before next phase boundary")
	print("TRAFFIC_SIGNAL_VISUAL_SYNC checks=",checks," failures=",failures)
	quit(1 if failures else 0)
