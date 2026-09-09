extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene = load("res://district/bairro1_v2/Bairro1V2.tscn")
	var b1 = scene.instantiate() as Bairro1V2
	b1.load_contributor_modules = true
	root.add_child(b1)
	
	for f in range(25):
		await process_frame
		
	var layout = b1.get_node_or_null("LayoutV2")
	var landmarks = b1.get_node_or_null("LandmarksV2")
	print("B1V2 Boot: Layout=", layout != null, " Landmarks=", landmarks != null)
	if layout:
		print("Layout markers:")
		for child in layout.find_child("Markers", true, false).get_children():
			print("  ", child.name, ": local=", child.position, " global=", child.global_position)
	if landmarks:
		print("Landmark positions:")
		for id in landmarks.get_all_landmarks():
			var lm = landmarks.get_landmark(id)
			print("  ", id, ": ", lm.name, " pos=", lm.position, " global=", lm.global_position)
	quit(0)
