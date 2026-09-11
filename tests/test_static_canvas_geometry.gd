extends SceneTree
const GEOMETRY := preload("res://world/shared/roads/StaticCanvasGeometry.gd")
var failures := 0
func _initialize() -> void: call_deferred("_run")
func _art(canvas: Variant) -> void:
	canvas.draw_rect(Rect2(-50,-50,900,600),Color("243440"))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-20,15),Vector2(600,10),Vector2(580,300),Vector2(450,350),Vector2(40,300)]),Color("879766"))
	canvas.draw_rect(Rect2(280,30,270,250),Color(0.8,0.2,0.1,0.7))
	canvas.draw_line(Vector2(10,40),Vector2(610,270),Color("efedcc"),7,true)
	canvas.draw_circle(Vector2(510,220),55,Color("afcbd8"))
	canvas.draw_rect(Rect2(495,80,90,180),Color("303055"),false,5)
	canvas.draw_polyline(PackedVector2Array([Vector2(40,350),Vector2(100,180),Vector2(220,330)]),Color("beab43"),12,true)
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Comparação visual exige renderer real.")
		quit(1)
		return
	var viewports: Array[SubViewport] = []
	for i in 2:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640,400)
		viewport.world_2d = World2D.new()
		viewport.disable_3d = true
		viewport.msaa_2d = Viewport.MSAA_2X
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewports.append(viewport)
		var node := Node2D.new()
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; void fragment() { if (SCREEN_UV.x > 0.6 && SCREEN_UV.y < 0.4) discard; COLOR.rgb *= vec3(0.7, 0.9, 0.8); }"
		var material := ShaderMaterial.new()
		material.shader = shader
		node.material = material
		viewport.add_child(node)
		if i == 0: node.draw.connect(func(): _art(node))
		else:
			var geometry := GEOMETRY.new(node)
			geometry.begin()
			_art(geometry)
			geometry.flush()
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var reference := viewports[0].get_texture().get_image()
	var optimized := viewports[1].get_texture().get_image()
	var error := 0.0
	var different := 0
	for y in 400:
		for x in 640:
			var a := reference.get_pixel(x,y)
			var b := optimized.get_pixel(x,y)
			var delta := maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			error += delta
			if delta>0.15: different += 1
	var mean := error/(640*400)
	var ratio := float(different)/(640*400)
	if mean>0.015 or ratio>0.02: failures += 1
	var folder := "res://docs/measurements/aa-performance-0911/"
	reference.save_png(folder+"geometry-reference.png")
	optimized.save_png(folder+"geometry-optimized.png")
	for viewport in viewports: viewport.free()
	print("STATIC_CANVAS_GEOMETRY_RESULT mean_error=%f different_ratio=%f failures=%d" % [mean,ratio,failures])
	quit(0 if failures == 0 else 1)
