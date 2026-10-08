extends SceneTree
## Camera response over the authored quarry heightfield; rendered route is separate.
const CAMERA := preload("res://world/desert/DesertTerrainCamera.gd")
const TERRAIN := preload("res://world/mining/MiningExterior.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var rows := []
	var falling_frames := 0
	var unstable_frames := 0
	for heading in [0.0, PI*.5, PI, -PI*.5]:
		var camera := CAMERA.new()
		var focus := Vector3(-180, .08, -1878)
		var height := focus.y
		var velocity := 0.0
		var pitches: Array[float] = []
		var last_sign := 0
		var reversals := 0
		var last_falling := false
		for frame in 900:
			var t := float(frame)/60.0
			var at := Vector3(-180, height, -1878+t*6.0)
			var floor_y := TERRAIN.surface_height(Vector2(at.x,at.z))+.08
			velocity -= 18.0/60.0
			height=maxf(floor_y,height+velocity/60.0)
			if height<=floor_y: velocity=0.0
			at.y=height
			focus=at if frame==0 else Vector3(at.x,lerpf(focus.y,at.y,1-exp(-10.0/60.0)),at.z)
			camera.offset_for(focus,Vector3(0,25.3,25.3).rotated(Vector3.UP,heading),1.0/60.0,frame==0,true,Vector2(43,24),.1,at,.8,Vector3(0,0,6),velocity < -1.0)
			var pitch: float=camera.diagnostics().pitch_degrees
			var falling := velocity < -1.0
			if falling and last_falling and not pitches.is_empty():
				falling_frames+=1
				if pitch < pitches[-1]-.025: unstable_frames+=1
			last_falling=falling
			if not pitches.is_empty():
				var difference:=pitch-pitches[-1]
				var sign_now:=signi(int(signf(difference))) if absf(difference)>.025 else 0
				if sign_now!=0:
					if last_sign!=0 and sign_now!=last_sign: reversals+=1
					last_sign=sign_now
			pitches.append(pitch)
		rows.append({"heading":heading,"reversals":reversals,"pitches":pitches})
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): out=arg.trim_prefix("--output=")
	if not out.is_empty(): FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify(rows))
	for row in rows: print("MINING_CAMERA_PROBE heading=",row.heading," reversals=",row.reversals)
	print("MINING_CAMERA_STABILITY falling_frames=",falling_frames," unstable_frames=",unstable_frames)
	quit(0 if falling_frames>100 and unstable_frames==0 else 1)
