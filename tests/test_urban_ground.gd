extends SceneTree
const GROUND := preload("res://world/harbor/UrbanGround.gd")
class Pavement extends Node2D:
	var overlap := true
	func _draw() -> void:
		GROUND.paint(self,Rect2(0,0,512,256),Color("b5ac95"),"stone")
		if overlap: GROUND.paint(self,Rect2(137,0,241,256),Color("b5ac95"),"stone")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	if DisplayServer.get_name()=="headless":
		push_error("Urban material comparison requires a renderer")
		quit(2)
		return
	root.size=Vector2i(512,256)
	root.content_scale_size=root.size
	var paving := Pavement.new()
	root.add_child(paving)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var joined := root.get_texture().get_image()
	paving.overlap=false
	paving.queue_redraw()
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var plain := root.get_texture().get_image()
	var maximum := 0.0
	for y in range(4,250,3):
		for x in range(132,384):
			var a := joined.get_pixel(x,y)
			var b := plain.get_pixel(x,y)
			maximum=maxf(maximum,Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length())
	print("URBAN_GROUND overlap RGB difference=",maximum)
	quit(0 if maximum<.01 else 1)
