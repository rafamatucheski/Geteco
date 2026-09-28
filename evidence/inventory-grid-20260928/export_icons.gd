extends SceneTree
func _initialize() -> void:
	var catalog=preload("res://ui/v1/WeaponIcon3D.gd").ICON_DATA
	for id in ["pistol","hunting_rifle"]:
		var source: Dictionary=catalog[id]
		var image:=Image.new()
		var bytes:=Marshalls.base64_to_raw(source.data)
		if source.ext=="svg": image.load_svg_from_buffer(bytes)
		else: image.load_png_from_buffer(bytes)
		image=image.get_region(image.get_used_rect().grow(2).intersection(Rect2i(Vector2i.ZERO,image.get_size())))
		image.save_png("C:/Users/rafae/.codex/visualizations/2026/09/28/01a0e8c3-7584-76e3-a3e5-9cb4ff43e218/"+id+".png")
	quit()
