class_name RuntimeWorkScheduler
extends RefCounted

## Gate global para fatias de trabalho que podem competir pelo mesmo frame.
## Trabalho barato não deve passar por aqui: a reserva é exclusiva de propósito,
## porque os produtores integrados já possuem budgets locais e o risco restante é
## a soma de várias fatias pesadas independentes.

const FRAME_BUDGET_USEC := 6000
const PRIORITY_BACKGROUND := 100
const PRIORITY_VISIBLE := 220
const PRIORITY_COLLISION := 320
const PRIORITY_NEAR_COLLISION := 420
const AGING_PRIORITY_PER_FRAME := 16
const MAX_TELEMETRY_RECORDS := 512

static var _context_root_id := 0
static var _next_request_id := 1
static var _pending: Dictionary = {}
static var _granted_frame := -1
static var _records: Array[Dictionary] = []
static var _cancelled_total := 0
static var _completed_total := 0
static var _over_budget_total := 0

static func reserve(owner: Object, producer: StringName, priority: int, expected_usec: int) -> Dictionary:
	if not is_instance_valid(owner):
		return {}
	var tree := _tree_for(owner)
	if tree == null or tree.root == null:
		return {}
	_ensure_context(tree)
	var request_id := _next_request_id
	_next_request_id += 1
	_pending[request_id] = {
		"id": request_id,
		"owner": weakref(owner),
		"owner_id": owner.get_instance_id(),
		"producer": producer,
		"priority": priority,
		"expected_usec": maxi(1, expected_usec),
		"queued_frame": Engine.get_process_frames(),
	}
	# Give every producer reached in this process frame a chance to enqueue.
	# This makes priority deterministic instead of depending on SceneTree order.
	await tree.process_frame
	while true:
		if not _same_context(tree):
			return {}
		_prune_invalid_requests()
		if not _pending.has(request_id):
			return {}
		var frame := Engine.get_process_frames()
		if _granted_frame != frame and _best_request_id(frame) == request_id:
			_granted_frame = frame
			var request: Dictionary = _pending[request_id]
			_pending.erase(request_id)
			var ticket := {
				"id": request_id,
				"producer": request.producer,
				"frame": frame,
				"priority": request.priority,
				"expected_usec": request.expected_usec,
				"waited_frames": maxi(0, frame - int(request.queued_frame)),
				"owner_id": request.owner_id,
			}
			_append_record({
				"id": request_id,
				"producer": String(request.producer),
				"frame": frame,
				"priority": request.priority,
				"expected_usec": request.expected_usec,
				"waited_frames": ticket.waited_frames,
				"owner_id": request.owner_id,
				"actual_usec": -1,
				"status": "granted",
			})
			return ticket
		await tree.process_frame
	return {}

static func complete(ticket: Dictionary, actual_usec: int) -> void:
	if ticket.is_empty():
		return
	var request_id := int(ticket.get("id", -1))
	for index in range(_records.size() - 1, -1, -1):
		var record: Dictionary = _records[index]
		if int(record.get("id", -2)) != request_id:
			continue
		if String(record.get("status", "")) != "granted":
			return
		record["actual_usec"] = maxi(0, actual_usec)
		record["status"] = "completed"
		record["over_budget"] = actual_usec > FRAME_BUDGET_USEC
		_records[index] = record
		_completed_total += 1
		if bool(record.over_budget):
			_over_budget_total += 1
		return

## Cancels only reservations that have not been granted yet. Matching the live
## object behind the WeakRef avoids relying on a potentially reused instance ID.
## An empty producer cancels every pending reservation owned by `owner`.
static func cancel_pending(owner: Object, producer: StringName = &"") -> int:
	if not is_instance_valid(owner):
		return 0
	var cancelled := 0
	for request_id_variant in _pending.keys():
		var request_id := int(request_id_variant)
		var request: Dictionary = _pending[request_id]
		var owner_ref := request.get("owner") as WeakRef
		if owner_ref == null or owner_ref.get_ref() != owner:
			continue
		if producer != &"" and StringName(request.get("producer", &"")) != producer:
			continue
		_cancel_request(request_id, request, &"explicit")
		cancelled += 1
	return cancelled

static func telemetry_snapshot() -> Dictionary:
	_prune_invalid_requests()
	return {
		"frame_budget_usec": FRAME_BUDGET_USEC,
		"granted_frame": _granted_frame,
		"pending": _pending.size(),
		"completed_total": _completed_total,
		"cancelled_total": _cancelled_total,
		"over_budget_total": _over_budget_total,
		"records": _records.duplicate(true),
	}

static func reset_for_tests() -> void:
	_context_root_id = 0
	_next_request_id = 1
	_pending.clear()
	_granted_frame = -1
	_records.clear()
	_cancelled_total = 0
	_completed_total = 0
	_over_budget_total = 0

static func _tree_for(owner: Object) -> SceneTree:
	if owner is Node:
		return (owner as Node).get_tree()
	return Engine.get_main_loop() as SceneTree

static func _ensure_context(tree: SceneTree) -> void:
	var root_id := tree.root.get_instance_id()
	if _context_root_id == root_id:
		return
	_context_root_id = root_id
	_next_request_id = 1
	_pending.clear()
	_granted_frame = -1
	_records.clear()
	_cancelled_total = 0
	_completed_total = 0
	_over_budget_total = 0

static func _same_context(tree: SceneTree) -> bool:
	return tree != null and tree.root != null and tree.root.get_instance_id() == _context_root_id

static func _owner_is_alive(request: Dictionary) -> bool:
	var owner_ref: WeakRef = request["owner"] as WeakRef
	var owner: Object = owner_ref.get_ref()
	if not is_instance_valid(owner):
		return false
	if owner is Node:
		return (owner as Node).is_inside_tree()
	return true

static func _prune_invalid_requests() -> void:
	for request_id in _pending.keys():
		var request: Dictionary = _pending[request_id]
		if _owner_is_alive(request):
			continue
		_cancel_request(int(request_id), request, &"owner_invalid")

static func _cancel_request(request_id: int, request: Dictionary, reason: StringName) -> void:
	_pending.erase(request_id)
	_cancelled_total += 1
	_append_record({
		"id": request_id,
		"producer": String(request.producer),
		"frame": Engine.get_process_frames(),
		"priority": request.priority,
		"expected_usec": request.expected_usec,
		"waited_frames": maxi(0, Engine.get_process_frames() - int(request.queued_frame)),
		"owner_id": request.owner_id,
		"actual_usec": 0,
		"status": "cancelled",
		"cancel_reason": String(reason),
	})

static func _best_request_id(frame: int) -> int:
	var best_id := -1
	var best_score := -2147483648
	for request_id_variant in _pending:
		var request_id := int(request_id_variant)
		var request: Dictionary = _pending[request_id]
		var waited := maxi(0, frame - int(request.queued_frame))
		var score := int(request.priority) + waited * AGING_PRIORITY_PER_FRAME
		if score > best_score or (score == best_score and (best_id < 0 or request_id < best_id)):
			best_score = score
			best_id = request_id
	return best_id

static func _append_record(record: Dictionary) -> void:
	_records.append(record)
	if _records.size() > MAX_TELEMETRY_RECORDS:
		_records.pop_front()
