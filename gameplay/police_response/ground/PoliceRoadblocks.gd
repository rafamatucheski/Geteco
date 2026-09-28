extends RefCounted
## Bounded response: at most two physical roadblocks, one placement attempt per
## 18 seconds and three candidates checked. All positions come from road graph.
const BLOCK := preload("res://gameplay/police_response/ground/PoliceRoadblock.gd")
const MAX_AGE := 75.0
var controller: Node3D
var blocks: Array[Node3D] = []
var placement_clock := 10.0
var sample_clock := 0.0

func configure(owner: Node3D) -> void:
	controller = owner

func clear() -> void:
	for block in blocks:
		if is_instance_valid(block): block.queue_free()
	blocks.clear()
	placement_clock = 10.0

func tick(delta: float) -> void:
	var gameplay: Node3D = controller.gameplay
	var exterior: bool = controller.player_position_override == Vector3.INF and gameplay.state.weapons_allowed()
	var pursuit: bool = gameplay.stars >= 3 and gameplay.last_known_valid and exterior
	var surrendered: bool = gameplay.has_method("police_surrendering") and gameplay.police_surrendering()
	var target: Node3D = gameplay.pursuit_target() if pursuit and not surrendered else null
	var car: CharacterBody3D = target as CharacterBody3D if is_instance_valid(target) and "horizontal_velocity" in target else null
	sample_clock -= delta
	var sample := sample_clock <= 0.0
	if sample: sample_clock = .10
	for block in blocks.duplicate():
		if not is_instance_valid(block):
			blocks.erase(block)
			continue
		block.age += delta
		if not pursuit or surrendered or block.age >= MAX_AGE: block.set_armed(false)
		if (not pursuit or block.age >= MAX_AGE) and controller.is_unseen(block.global_position):
			blocks.erase(block)
			block.queue_free()
			continue
		if sample:
			if block.sample_target(car,pursuit and not surrendered and block.age < MAX_AGE):
				controller.emit_dispatch_event("tires_punctured",{"point":block.global_position})
	placement_clock = maxf(0.0,placement_clock-delta)
	var limit := 2 if gameplay.stars >= 5 else 1
	if not pursuit or surrendered or blocks.size() >= limit or placement_clock > 0.0: return
	placement_clock = 18.0
	try_place(gameplay.last_known)

func try_place(anchor: Vector3) -> Node3D:
	if controller.player_position_override != Vector3.INF or not controller.gameplay.state.weapons_allowed(): return null
	var candidates: Array = controller.router.spawn_candidates(anchor,38.0,95.0,14.0)
	var checked := 0
	for candidate in candidates:
		var edge: Dictionary = candidate.edge
		var yaw: float = candidate.yaw
		var direction := Vector3(-sin(yaw),0,-cos(yaw))
		var point: Vector3 = candidate.point-controller.routes._lane_offset(direction,edge)
		var width := clampf(float(edge.width)-.45,6.0,14.0)
		if float(edge.width) < 6.4 or controller.is_visible_to_player(point): continue
		var near_existing := false
		for other in blocks:
			if other.global_position.distance_to(point) < 35.0: near_existing = true
		if near_existing: continue
		checked += 1
		if checked > 3: break
		# Clearance is checked over the complete formation, including the strip.
		if not controller._space_clear(Vector3(width,1.15,2.0),point,yaw,controller.no_exclusions): continue
		var plan: Dictionary = controller.router.plan(anchor,candidate.point)
		if not plan.ok or plan.length > 180.0: continue
		var block := BLOCK.new()
		block.name = "PoliceRoadblock"
		controller.add_child(block)
		block.global_position = point+Vector3.UP*.025
		block.rotation.y = yaw
		block.build(width)
		blocks.append(block)
		controller.emit_dispatch_event("roadblock_deployed",{"point":point,"width":width})
		return block
	return null
