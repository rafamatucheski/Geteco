extends SceneTree
const LOGISTICS := preload("res://gameplay/urban_v1/PortLogistics.gd")
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	var cargo := LOGISTICS.new()
	cargo.session = {"weather":{"time_of_day":.9},"activities":{"_data":{"day":4,"day_clock":50.0}}}
	for i in 3: cargo.work_trucks.append({"respawn_at":-1.0,"deliveries":0,"phase":"approach"})
	var start := cargo.game_seconds()
	cargo.session.weather.time_of_day = .1
	check(is_equal_approx(cargo.game_seconds()-start,120),"Midnight wraps forward by the two tenths of a visible day")
	var before := cargo.game_seconds()
	cargo.session.activities._data.day += 4
	check(is_equal_approx(cargo.game_seconds(),before),"Tow quota calendar cannot prematurely respawn a truck")
	cargo.work_trucks[0].respawn_at = before+600
	for step in 3:
		cargo.session.weather.time_of_day = fposmod(cargo.session.weather.time_of_day+.25,1.0)
		check(cargo.game_seconds()<cargo.work_trucks[0].respawn_at,"No respawn after only %d game hours"%((step+1)*6))
	var saved := cargo.snapshot()
	check(LOGISTICS.validate_snapshot(saved),"Clock and deadline serialize together")
	var restored := LOGISTICS.new()
	restored.session = cargo.session
	for i in 3: restored.work_trucks.append({"respawn_at":-1.0,"deliveries":0,"phase":"approach"})
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(saved))),"Clock survives save restoration")
	check(is_equal_approx(restored.game_seconds(),cargo.game_seconds()),"Reload neither advances nor resets cooldown")
	restored.session.weather.time_of_day = fposmod(restored.session.weather.time_of_day+.25,1.0)
	check(is_equal_approx(restored.game_seconds(),restored.work_trucks[0].respawn_at),"Exactly 24 visible hours exhaust the deadline, including sleep-style jumps")
	var invalid := saved.duplicate(true)
	invalid.clock_phase = 1.0
	check(not LOGISTICS.validate_snapshot(invalid),"Invalid clock phase rejected")
	cargo.free()
	restored.free()
	print("PORT_LOGISTICS_CLOCK failures=",failures)
	quit(0 if failures.is_empty() else 1)
