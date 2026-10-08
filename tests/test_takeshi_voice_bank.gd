extends SceneTree
const VOICE := preload("res://audio/ExpressiveVoice.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var production: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://audio/mission_voices/takeshi_drag/production.json"))
	if not production is Dictionary or not production.get("complete",false):
		push_error("TAKESHI_VOICE production is incomplete")
		quit(1)
		return
	var count := 0
	for row in production.lines:
		var key: String = VOICE.recording_key(str(row.text),"takeshi")
		if key!=str(row.key): failures.append("Exact dialogue key: "+str(row.id))
		var stream: AudioStream = VOICE.recorded_line(str(row.text),"takeshi","pt_BR")
		if not stream is AudioStreamWAV:
			failures.append("Imported exact recording: "+str(row.id))
			continue
		if stream.get_length()<.7 or stream.get_length()>28: failures.append("Complete bounded duration: "+str(row.id))
		if stream.mix_rate!=24000: failures.append("Native voice sample rate: "+str(row.id))
		if stream.get_meta("voice_language","")!="pt_BR": failures.append("Portuguese voice selection: "+str(row.id))
		count+=1
	if count!=6: failures.append("All six dialogue branches have imported speech")
	print("TAKESHI_VOICE_BANK takes=",count," failures=",failures)
	quit(0 if failures.is_empty() else 1)
