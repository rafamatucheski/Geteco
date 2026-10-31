extends SceneTree
## Só infraestrutura de benchmark: sem pedidos de janela nem cena de jogo.
const GATE := preload("res://tests/measure/NativePresentationGate.gd")
var checks := 0
var failures: Array[String] = []
var test_path := ""

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture() -> RefCounted:
	var gate := GATE.new()
	gate.path = test_path
	return gate

func beat(timestamp := 100.0) -> Dictionary:
	return {"pid":OS.get_process_id(),"token":test_path.get_file(),"unix":timestamp}

func _initialize() -> void:
	test_path = OS.get_user_data_dir().path_join("native-gate-test-%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(test_path)
	var gate := fixture()
	gate._observe_heartbeat(beat(),100.1,1000000)
	check(gate.failure.is_empty(),"fresh matching heartbeat accepted")
	var original_deadline: int = gate._heartbeat_deadline_usec
	gate._observe_heartbeat(gate._read("heartbeat"),101.0,1900000)
	check(gate.failure.is_empty(),"transient missing file preserves valid heartbeat")
	var file := FileAccess.open(test_path.path_join("heartbeat.json"),FileAccess.WRITE)
	file.store_string("{\"pid\":")
	file.close()
	gate._observe_heartbeat(gate._read("heartbeat"),102.0,2900000)
	check(gate.failure.is_empty(),"transient incomplete JSON preserves valid heartbeat")
	check(gate._heartbeat_deadline_usec == original_deadline,"missing and incomplete reads never renew lease")
	gate._observe_heartbeat(beat(),102.8,3700000)
	check(gate._heartbeat_deadline_usec == original_deadline,"same heartbeat never renews lease")
	gate._observe_heartbeat({},103.0,original_deadline)
	check(not gate.failure.is_empty(),"missing observer expires at original three-second deadline")
	gate = fixture()
	gate._observe_heartbeat({},100.0,1000000)
	check(not gate.failure.is_empty(),"missing first heartbeat cannot grant grace")
	for invalid_kind in ["pid","token","future","stale","nonfinite"]:
		gate = fixture()
		gate._observe_heartbeat(beat(),100.1,1000000)
		var invalid := beat()
		match invalid_kind:
			"pid": invalid.pid = OS.get_process_id()+1
			"token": invalid.token = "other-run"
			"future": invalid.unix = 100.700001
			"stale": invalid.unix = 96.0
			"nonfinite": invalid.unix = NAN
		gate._observe_heartbeat(invalid,100.2,1100000)
		check(not gate.failure.is_empty(),"invalid %s rejected despite cached valid heartbeat" % invalid_kind)
	gate = fixture()
	gate._observe_heartbeat(beat(100.4),100.1,1000000)
	check(gate.failure.is_empty() and gate._heartbeat_deadline_usec == 4000000,"clock quantization tolerance never grants more than three seconds")
	gate = fixture()
	gate._observe_heartbeat(beat(),100.1,1000000)
	gate._observe_heartbeat(beat(101.0),101.1,2000000)
	check(gate.failure.is_empty() and gate._heartbeat_deadline_usec > original_deadline,"newer valid heartbeat advances lease")
	gate._next_heartbeat = 9000000
	check(not gate.poll(gate._heartbeat_deadline_usec).is_empty(),"deadline enforced between scheduled heartbeat reads")
	DirAccess.remove_absolute(test_path.path_join("heartbeat.json"))
	DirAccess.remove_absolute(test_path)
	print("NATIVE_PRESENTATION_GATE checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
