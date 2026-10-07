extends SceneTree
## Gera `Ladder_Descend`: o `Fast_Ladder_Climb` do Dante tocado ao contrário (mãos e pés se alternam
## nos degraus do mesmo jeito, só que o corpo desce). O Quaternius/UAL não traz clipe de escada.
const OUT := "res://assets/animation_library/dante_ladder.res"
func _init() -> void:
	var dante: Node = (load("res://assets/dante.glb") as PackedScene).instantiate()
	root.add_child(dante)
	var ap := dante.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var src: Animation = ap.get_animation("Fast_Ladder_Climb")
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_NONE
	for t in src.get_track_count():
		var type := src.track_get_type(t)
		if type not in [Animation.TYPE_ROTATION_3D, Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D]: continue
		var n := out.add_track(type)
		out.track_set_path(n, src.track_get_path(t))
		out.track_set_interpolation_type(n, src.track_get_interpolation_type(t))
		for k in range(src.track_get_key_count(t) - 1, -1, -1):
			var time := src.length - src.track_get_key_time(t, k)
			var value: Variant = src.track_get_key_value(t, k)
			match type:
				Animation.TYPE_ROTATION_3D: out.rotation_track_insert_key(n, time, value)
				Animation.TYPE_POSITION_3D: out.position_track_insert_key(n, time, value)
				Animation.TYPE_SCALE_3D: out.scale_track_insert_key(n, time, value)
	var lib := AnimationLibrary.new()
	lib.add_animation("Ladder_Descend", out)
	print("LADDER saved=", ResourceSaver.save(lib, OUT), " tracks=", out.get_track_count(), "/", src.get_track_count(), " length=", out.length)
	quit()
