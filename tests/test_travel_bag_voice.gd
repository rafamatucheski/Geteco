extends SceneTree
const DIALOGUE = preload("res://systems/campaign/OriginalDialogue.gd")
const VOICE = preload("res://audio/ExpressiveVoice.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var dialogue = DIALOGUE.new()
	for subtitles in ["pt","en"]:
		var line: Dictionary = dialogue.lines("cobra_race_clue",subtitles)[0]
		for language in ["pt_BR","en"]:
			checks += 1
			var take: AudioStream = VOICE.recorded_line(line.message,"maciota",language)
			var ok: bool = take != null and take.get_length()>5 and take.get_meta("voice_language","")==language
			print("TRAVEL_BAG_VOICE ","PASS " if ok else "FAIL ",subtitles,"/",language)
			if not ok: failures += 1
	print("TRAVEL_BAG_VOICE_RESULT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
