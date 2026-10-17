extends Node
## Immutable authored banks. Disk decoding runs off the game thread; publication
## happens only after the worker has finished. No PCM synthesis runs in gameplay.
const CATALOG := preload("res://audio/FleetEngineDesign.gd")
const ROOT := "res://audio/engine_design/"
static var _cache: Dictionary = {}
static var _worker: Node
static var _enabled := "--legacy-engine-design" not in OS.get_cmdline_user_args()
var _pending: Array[String] = []
var _thread: Thread
var _current := ""

static func enabled() -> bool:
	return _enabled

static func is_ready(profile_id: String) -> bool:
	return _cache.has(profile_id) and not _cache[profile_id].is_empty()

static func bank(profile_id: String, state := "loaded") -> Array[AudioStreamWAV]:
	var result: Array[AudioStreamWAV] = []
	if is_ready(profile_id): result.assign(_cache[profile_id].get(state, []))
	return result

static func effect(profile_id: String, effect_name: String) -> AudioStreamWAV:
	return _cache.get(profile_id, {}).get(effect_name) as AudioStreamWAV

static func prewarm(tree: SceneTree) -> void:
	if not enabled(): return
	if not is_instance_valid(_worker):
		var pending: Array[String] = []
		for id in CATALOG.all_profile_ids():
			if not _cache.has(id): pending.append(id)
		if pending.is_empty(): return
		var worker := load("res://audio/EngineDesignBanks.gd").new() as Node
		worker.set("_pending", pending)
		_worker = worker
		tree.root.add_child(worker)
	while is_instance_valid(_worker): await tree.process_frame

func _process(_delta: float) -> void:
	if _thread != null:
		if _thread.is_alive(): return
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		_cache[_current] = result
		if result.is_empty(): push_error("Engine design bank incomplete: " + _current)
		return
	if _pending.is_empty():
		_worker = null
		queue_free()
		return
	_current = _pending.pop_front()
	_thread = Thread.new()
	var error := _thread.start(_read_profile.bind(_current))
	if error != OK:
		_thread = null
		_cache[_current] = {}
		push_error("Unable to prepare engine bank: " + _current)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()
	_thread = null
	if _worker == self: _worker = null

static func _read(path: String, looped: bool) -> AudioStreamWAV:
	# ResourceLoader supports exported remaps. Raw source loading also allows
	# a fresh developer checkout to work before the editor imports the WAVs.
	var stream: AudioStreamWAV
	if ResourceLoader.exists(path):
		var source := load(path) as AudioStreamWAV
		if source != null: stream = source.duplicate() as AudioStreamWAV
	if stream == null and FileAccess.file_exists(path):
		stream = AudioStreamWAV.load_from_file(path, {"compress/mode": 0})
	if stream == null: return null
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate) - 8
	else: stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream

static func _read_profile(id: String) -> Dictionary:
	var result: Dictionary = {"loaded": [], "coast": []}
	for state: String in ["loaded", "coast"]:
		var prefix := "engine" if state == "loaded" else "coast"
		for index in 7:
			var stream := _read(ROOT + "%s/%s_%s_%d.wav" % [id, prefix, id, index], true)
			if stream == null: return {}
			result[state].append(stream)
	var meta: Dictionary = CATALOG.metadata(id)
	if bool(meta.get("turbo", false)):
		result.turbo_spool = _read(ROOT + id + "/turbo_spool.wav", true)
		if result.turbo_spool == null: return {}
	if bool(meta.get("bypass_valve", false)):
		result.bypass_release = _read(ROOT + id + "/bypass_release.wav", false)
		if result.bypass_release == null: return {}
	return result
