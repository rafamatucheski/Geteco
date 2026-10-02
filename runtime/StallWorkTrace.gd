extends RefCounted
## Cronometragem opt-in do descarte. Sem StallLog ativo, não guarda eventos.
## Os tempos são aninhados: não somar pai e filho para estimar o custo do quadro.
const MAX_EVENTS := 256
static var enabled := false
static var events: Array[Dictionary] = []
static var dropped := 0

static func begin() -> int:
	return Time.get_ticks_usec() if enabled else 0

static func finish(label: String, began: int, details: Dictionary = {}) -> void:
	if began == 0 or not enabled: return
	var ended := Time.get_ticks_usec()
	if events.size() >= MAX_EVENTS:
		dropped += 1
		return
	events.append({"label": label, "start_usec": began, "end_usec": ended,
		"ms": snappedf(float(ended - began) / 1000.0, 0.001),
		"process_frame": Engine.get_process_frames(), "details": details})

static func finish_slow(label: String, began: int, minimum_usec: int = 10000, source: Node = null) -> void:
	if began == 0 or not enabled: return
	var ended := Time.get_ticks_usec()
	if ended - began < minimum_usec: return
	# Um pico não pode desaparecer atrás dos eventos rápidos de um quadro.
	if events.size() >= MAX_EVENTS:
		for i in events.size():
			if float(events[i].get("ms", 0.0)) < float(minimum_usec) / 1000.0:
				events.remove_at(i)
				dropped += 1
				break
		if events.size() >= MAX_EVENTS:
			dropped += 1
			return
	var details := {}
	if is_instance_valid(source):
		details = {"name": str(source.name), "class": source.get_class(), "id": source.get_instance_id()}
		if source is Node3D: details["position"] = str(source.global_position)
		if "archetype" in source: details["archetype"] = str(source.get("archetype"))
		if "traffic" in source: details["traffic"] = source.get("traffic")
		if "health" in source: details["health"] = source.get("health")
	events.append({"label": label, "start_usec": began, "end_usec": ended,
		"ms": float(ended-began)/1000.0, "process_frame": Engine.get_process_frames(), "details": details})

static func take() -> Array[Dictionary]:
	var result := events
	events = []
	if dropped > 0:
		result.append({"label": "trace.events_dropped", "count": dropped})
		dropped = 0
	return result
