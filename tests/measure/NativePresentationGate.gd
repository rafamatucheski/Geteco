extends RefCounted
## Benchmark-only handshake. Windows wrapper owns native focus evidence.
var path := ""
var failure := ""
var accepted: Dictionary = {}
var _next_check := 0
var _next_heartbeat := 0
var _requested_usec := 0
var _last_heartbeat_unix := 0.0
var _heartbeat_deadline_usec := 0
var _transient_heartbeat_reads := 0
var _wait_usec := 30000000

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--native-presentation-gate="):
			path = arg.trim_prefix("--native-presentation-gate=")
		elif arg.begins_with("--native-focus-wait-seconds="):
			_wait_usec = int(clampf(float(arg.trim_prefix("--native-focus-wait-seconds=")),30.0,180.0)*1000000.0)

func _read(name: String) -> Dictionary:
	var filename := path.path_join(name+".json")
	var file := FileAccess.open(filename,FileAccess.READ)
	if file == null: return {}
	var text := file.get_as_text()
	file.close()
	var data: Variant = JSON.parse_string(text)
	return data if data is Dictionary else {}

func _write(name: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path.path_join(name+".json"),FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.close()
	return true

func wait_until_presented(tree: SceneTree) -> bool:
	if path.is_empty(): return true
	_requested_usec = Time.get_ticks_usec()
	if not _write("request",{"pid":OS.get_process_id(),"token":path.get_file(),"request_usec":_requested_usec}):
		failure = "native_presentation_request_write_failed"
		return false
	print("NATIVE_PRESENTATION_WAITING ",OS.get_process_id()," ",path," (",_wait_usec/1000000,"s deadline; native Windows foreground required)")
	while Time.get_ticks_usec()-_requested_usec < _wait_usec:
		var revoked := _read("revoked")
		if not revoked.is_empty():
			failure = "native_presentation_"+str(revoked.get("reason","revoked"))
			return false
		var grant := _read("accepted")
		if int(grant.get("pid",0)) == OS.get_process_id() and grant.get("token","") == path.get_file():
			accepted = grant
			failure = poll(Time.get_ticks_usec(),true)
			if not failure.is_empty(): return false
			print("NATIVE_PRESENTATION_ACCEPTED ",JSON.stringify(grant))
			return true
		await tree.create_timer(.1).timeout
	failure = "native_presentation_timeout"
	return false

func _observe_heartbeat(heartbeat: Dictionary, unix_now: float, now: int) -> void:
	if heartbeat.is_empty():
		_transient_heartbeat_reads += 1
	else:
		var timestamp := float(heartbeat.get("unix",0.0))
		var age := unix_now-timestamp
		if int(heartbeat.get("pid",0)) != OS.get_process_id() or heartbeat.get("token","") != path.get_file():
			failure = "native_presentation_observer_identity_mismatch"
			return
		if not is_finite(timestamp) or age < -.5:
			failure = "native_presentation_observer_future_or_invalid_timestamp"
			return
		if age > 3.0:
			failure = "native_presentation_observer_missing_or_stale"
			return
		if timestamp > _last_heartbeat_unix:
			_last_heartbeat_unix = timestamp
			# Re-reading the same file or a transient miss cannot renew this lease.
			_heartbeat_deadline_usec = now+int((3.0-maxf(age,0.0))*1000000.0)
	if _heartbeat_deadline_usec == 0 or now >= _heartbeat_deadline_usec:
		failure = "native_presentation_observer_missing_or_stale"

func poll(now: int, force := false) -> String:
	if path.is_empty(): return ""
	if not failure.is_empty(): return failure
	if not force and now < _next_check: return ""
	_next_check = now+100000
	var revoked := _read("revoked")
	if not revoked.is_empty():
		failure = "native_presentation_"+str(revoked.get("reason","revoked"))
	elif force or now >= _next_heartbeat:
		_next_heartbeat = now+1000000
		_observe_heartbeat(_read("heartbeat"),Time.get_unix_time_from_system(),now)
	elif _heartbeat_deadline_usec == 0 or now >= _heartbeat_deadline_usec:
		failure = "native_presentation_observer_missing_or_stale"
	return failure

func finish(now: int) -> String:
	if path.is_empty(): return ""
	var result := poll(now,true)
	if not _write("done",{"pid":OS.get_process_id(),"token":path.get_file(),"end_usec":now,"failure":result}):
		failure = "native_presentation_done_write_failed"
	return failure

func snapshot() -> Dictionary:
	return {"enabled":not path.is_empty(),"path":path,"accepted":accepted,"failure":failure,"request_usec":_requested_usec,
		"last_heartbeat_unix":_last_heartbeat_unix,"transient_heartbeat_reads":_transient_heartbeat_reads,
		"scope":"Exact-PID native Windows gate before warmup; wrapper samples presentation at100ms. First observed loss permanently invalidates the run. No focus recovery during warmup or sampling. Filesystem revocation checked at100ms, heartbeat at1s; observer timeout3s. Sampling cannot prove continuity between observations."}
