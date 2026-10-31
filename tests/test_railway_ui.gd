extends SceneTree
## Só contrato de UI. A suíte de runtime exercita à parte o Main/física reais.
const UI := preload("res://ui/railway/RailwayUI.gd")

class TransitDouble extends Node:
	signal station_requested(origin_id: String, stations: Array)
	signal station_menu_closed
	signal trip_started(state: Dictionary)
	signal trip_updated(state: Dictionary)
	signal trip_finished(station_id: String)
	signal notice(message: String)
	var requests: Array[Dictionary] = []
	var close_count := 0
	var skip_count := 0
	var camera_mode := 0
	func travel_to(id: String, instant: bool) -> bool:
		requests.append({"id": id, "instant": instant})
		return true
	func close_station_menu() -> void:
		close_count += 1
		station_menu_closed.emit()
	func skip_trip() -> void:
		skip_count += 1
	func set_camera_mode(mode: int) -> void:
		camera_mode = mode

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("RAILWAY_UI ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func run() -> void:
	var transit := TransitDouble.new()
	root.add_child(transit)
	var ui := UI.new()
	root.add_child(ui)
	ui.configure(transit)
	var stations: Array = [
		{"id": "harbor", "name": "Porto", "available": true},
		{"id": "mountain", "name": "Montanha", "available": true, "duration_seconds": 94},
		{"id": "desert", "name": "Deserto", "available": false, "locked_reason": "Conclua a última missão da cidade 1."},
	]
	transit.station_requested.emit("harbor", stations)
	await process_frame
	check(ui.is_station_open(), "station signal opens selector")
	check(ui.station_buttons.size() == 2 and not ui.station_buttons.has("harbor"), "origin cannot be selected as its own destination")
	check(ui.selected_id == "mountain" and not ui._board.disabled and not ui._fast.disabled, "first available destination supports both travel modes")
	check(ui._status.text.contains("1:34"), "journey duration displayed in minutes and seconds")
	ui.station_buttons.desert.grab_focus()
	check(ui.selected_id == "desert" and not ui.station_buttons.desert.disabled, "locked station remains reachable by keyboard and controller")
	check(ui._status.text == stations[2].locked_reason and ui._board.disabled and ui._fast.disabled, "locked station explains campaign gate and prevents both actions")
	ui._request_travel(false)
	ui._request_travel(true)
	check(transit.requests.is_empty(), "locked travel never calls runtime")
	ui.select_destination("missing_station")
	ui._request_travel(false)
	check(transit.requests.is_empty() and ui._board.disabled, "unknown destination cannot be submitted")
	ui.select_destination("mountain")
	ui._board.pressed.emit()
	ui._fast.pressed.emit()
	check(transit.requests == [{"id": "mountain", "instant": false}, {"id": "mountain", "instant": true}], "buttons preserve scenic versus fast travel choice")
	transit.notice.emit("Destino indisponível")
	check(ui._status.text == "Destino indisponível" and ui.is_station_open(), "runtime refusal stays in selector with actionable feedback")
	var trip := {"origin_id": "harbor", "destination_id": "mountain", "origin_name": "Porto", "destination_name": "Montanha", "progress": 0.25, "remaining_seconds": 72.0, "camera_mode": 0}
	transit.trip_started.emit(trip)
	await process_frame
	check(not ui.is_station_open() and ui._journey_panel.visible, "boarding replaces selector with compact journey HUD")
	check(ui._journey_title.text.contains("Porto") and ui._journey_title.text.contains("Montanha"), "journey shows departure and chosen destination")
	check(is_equal_approx(ui._progress.value, 0.25) and ui._journey_time.text == "1:12", "runtime progress and remaining duration reach HUD")
	check(ui.find_children("InteriorView", "", true, false).is_empty() and ui.find_children("ExteriorView", "", true, false).is_empty(), "single external view needs no camera toggle buttons")
	check(ui._skip.has_focus(), "controller focus goes directly to the remaining journey action")
	ui._skip.pressed.emit()
	check(transit.skip_count == 1, "skip button asks runtime to finish ride")
	trip.progress = 2.0
	trip.remaining_seconds = -1.0
	transit.trip_updated.emit(trip)
	check(is_equal_approx(ui._progress.value, 1.0) and ui._journey_time.text == "0:00", "late update cannot display invalid percentage or negative time")
	transit.trip_finished.emit("mountain")
	check(not ui._journey_panel.visible, "arrival clears journey HUD")
	ui._request_skip()
	check(transit.skip_count == 1, "hidden journey cannot skip a new transition")
	transit.station_requested.emit("mountain", stations)
	await process_frame
	check(ui.station_buttons.has("harbor") and not ui.station_buttons.has("mountain"), "arrival station menu offers return trip and omits current station")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	ui._unhandled_input(cancel)
	check(not ui.is_station_open() and transit.close_count == 1, "Escape/controller cancel returns lock ownership to runtime once")
	transit.station_requested.emit("harbor", stations)
	transit.station_menu_closed.emit()
	check(not ui.is_station_open() and transit.close_count == 1, "external cancellation closes UI without recursive runtime callback")
	ui.configure(transit)
	transit.station_requested.emit("harbor", [])
	await process_frame
	check(ui.station_buttons.is_empty() and ui._board.disabled and ui._fast.disabled, "empty destination list is safely cancellable")
	check(ui._close.has_focus(), "empty menu preserves usable controller focus")
	check(transit.station_requested.get_connections().size() == 1, "reconfiguration does not duplicate signal connections")
	ui.queue_free()
	transit.queue_free()
	await process_frame
	print("RAILWAY_UI_RESULT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
