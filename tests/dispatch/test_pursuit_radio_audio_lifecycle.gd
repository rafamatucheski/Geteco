extends SceneTree
## Ownership of threaded audio loads, including idle/stop, sharing and immediate unload.
const RADIO := preload("res://gameplay/dispatch/PursuitRadioAudio.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func voice() -> Node:
	var radio := RADIO.new()
	root.add_child(radio)
	return radio
func wait_loaded(radios: Array) -> void:
	for frame in 180:
		await process_frame
		if radios.all(func(radio): return radio._requested.is_empty()): return
func paths_owned(radios: Array) -> Array:
	var paths: Array = []
	for radio in radios:
		for path in radio._requested.values():
			if not paths.has(path): paths.append(path)
	return paths
func released(paths: Array) -> bool:
	return paths.all(func(path): return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
func run() -> void:
	var settings: Node = root.get_node("V2Settings")
	var old_language: String = settings.voice_language
	settings.voice_language = "en" # Only the two squelches exist for this language in the bank.
	var first := voice()
	var second := voice()
	var paths := paths_owned([first,second])
	check(not paths.is_empty(),"both radio owners create real threaded audio requests")
	first.stop()
	second.stop()
	check(first.is_processing() and second.is_processing(),"stop keeps pending loader collection active")
	await wait_loaded([first,second])
	check(first._requested.is_empty() and second._requested.is_empty(),"idle owners collect completed loads without speaking")
	check(first._streams.size() == paths.size() and second._streams.size() == paths.size(),"shared requests retain playback streams for both owners")
	check(released(paths),"every owned loader handle is collected exactly once")
	check(not first._player.playing and not second._player.playing,"preloading and stop never start a radio line")
	first._prepare("pt")
	check(not first._requested.values().any(func(path): return path in paths),"language change does not request already retained squelches")
	first.free()
	second.free()
	for cycle in 3:
		var immediate := voice()
		var immediate_paths := paths_owned([immediate])
		check(not immediate_paths.is_empty(),"immediate unload cycle%d owns requests" % cycle)
		immediate.free()
		check(released(immediate_paths),"immediate unload cycle%d releases requests before next frame" % cycle)
	var leaving := voice()
	var staying := voice()
	var shared_paths := paths_owned([leaving,staying])
	leaving.free()
	await wait_loaded([staying])
	check(staying._requested.is_empty() and staying._streams.size() == shared_paths.size(),"unloading one owner preserves the other radio's playback bank")
	staying.free()
	check(released(shared_paths),"last shared owner leaves no pending handles")
	settings.voice_language = old_language
	print("PURSUIT_RADIO_LIFECYCLE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
