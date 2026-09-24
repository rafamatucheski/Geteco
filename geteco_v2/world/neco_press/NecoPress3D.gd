extends Node3D
class_name NecoPress3D

## Neco's Vehicle Crusher / Industrial Scrap Press Component (Geteco V2).
## Independent visual & kinematic presentation rig recreating the classic Geteco V1
## crusher geometry and multi-phase sequence with native 3D geometry and cached materials.
##
## ARCHITECTURAL CONSTRAINTS:
## - Visual presentation only: Does NOT delete entities, does NOT grant rewards,
##   does NOT modify save states, and does NOT decide scrap eligibility.
##   All reward, destruction, and economic logic belongs exclusively to GarageRewards.
## - The integrator supplies a visual vehicle node (or duplicate) to start_presentation().
## - Exposes physical collision volumes and bounding boxes for integration without internal damage hooks.
## - Zero decorative/descriptive signage on structure (per AGENTS.md).

signal presentation_started(vehicle_visual: Node3D)
signal phase_changed(new_phase: String)
signal presentation_completed(compacted_visual: Node3D)
signal presentation_cancelled()

enum Phase {
	IDLE,
	APPROACHING,  ## Ram moves forward along Z to align above vehicle
	CRUSHING,     ## Ram descends vertically along Y, squashing visual representation
	HOLDING,      ## Ram dwells under maximum downward pressure
	RETRACTING,   ## Ram ascends along Y and retracts back along -Z to resting position
	CANCELLED
}

# --- Geometric Dimensions (Local Space) ---
# Platform: 3.4m wide (X), 0.5m high (Y), 5.0m long (Z)
const PLATFORM_SIZE := Vector3(3.4, 0.5, 5.0)
const PLATFORM_CENTER := Vector3(0.0, 0.25, 0.0)
const RECEPTION_BED_SURFACE_Y := 0.50
const RECEPTION_CENTER := Vector3(0.0, RECEPTION_BED_SURFACE_Y, 0.0)
const RECEPTION_BOUNDS := Vector3(2.6, 2.0, 4.8)

# Ram Plate resting vs working positions
const RAM_RESTING_POS := Vector3(0.0, 2.9, -5.5)
const RAM_ALIGNED_POS := Vector3(0.0, 2.9, 0.0)
const RAM_CRUSHED_POS := Vector3(0.0, 0.90, 0.0)
const RAM_PLATE_SIZE := Vector3(2.9, 0.35, 4.5)

# --- Node References ---
var _ram_assembly: Node3D
var _ram_plate_mesh: MeshInstance3D
var _ram_body: AnimatableBody3D
var _ram_collision: CollisionShape3D
var _piston_left: MeshInstance3D
var _piston_right: MeshInstance3D
var _piston_rod_left: MeshInstance3D
var _piston_rod_right: MeshInstance3D

const ADMISSION_BOUNDS := AABB(Vector3(-2,0,-8.2),Vector3(4,5.2,11))
var _guard: StaticBody3D
var _current_phase: Phase = Phase.IDLE
var _active_tween: Tween
var _current_vehicle_visual: Node3D
var _original_vehicle_scale := Vector3.ONE

func _ready() -> void:
	_build_press_rig()
	add_to_group("native_neco_press")
	set_meta("admission_bounds",ADMISSION_BOUNDS)
	set_meta("presentation_duration",3.55)
	set_physics_process(false)

func _exit_tree() -> void:
	if is_instance_valid(_current_vehicle_visual) and is_active():
		_current_vehicle_visual.scale = _original_vehicle_scale
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

# ==============================================================================
# Presentation API (Public)
# ==============================================================================

## Begins the crushing visual sequence using the provided visual representation of a vehicle.
## The caller (e.g. GarageRewards / SalvageYard integrator) is responsible for providing
## the visual node to squash and deciding when to clean it up or replace it with scrap cubes.
func start_presentation(vehicle_visual: Node3D) -> bool:
	if _current_phase != Phase.IDLE:
		push_warning("NecoPress3D: Cannot start presentation while phase is %s." % _phase_to_string(_current_phase))
		return false
	if not is_instance_valid(vehicle_visual) or not is_inside_tree() or not is_admission_clear():
		push_warning("NecoPress3D: Cannot start presentation with null vehicle_visual.")
		return false

	_install_guard()
	set_physics_process(true)
	_current_vehicle_visual = vehicle_visual
	_original_vehicle_scale = vehicle_visual.scale
	_set_phase(Phase.APPROACHING)
	presentation_started.emit(vehicle_visual)

	_run_presentation_sequence()
	return true

## Immediately stops the crushing sequence and safely restores the press to resting state.
## Does not delete the vehicle visual node; leaves state clean for reuse.
func cancel_presentation() -> void:
	if _current_phase == Phase.IDLE:
		return

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
		_active_tween = null

	# Cancellation is synchronous and owns no untracked recovery tween.
	if is_instance_valid(_current_vehicle_visual): _current_vehicle_visual.scale = _original_vehicle_scale
	_current_vehicle_visual = null
	_ram_assembly.position = RAM_RESTING_POS
	_release_guard()
	_set_phase(Phase.IDLE)
	presentation_cancelled.emit()

## Full swept volume (including the parked plate) in press-local coordinates.
func get_admission_bounds() -> AABB: return ADMISSION_BOUNDS
func get_admission_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY,ADMISSION_BOUNDS.get_center())
func is_admission_clear() -> bool:
	if not is_inside_tree(): return false
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = ADMISSION_BOUNDS.size
	query.shape = box
	query.transform = get_admission_transform()
	query.collision_mask = 6 # all native actors and actual vehicles, never the visual proxy
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
func _install_guard() -> void:
	_guard = StaticBody3D.new()
	_guard.name = "ActivePressSafetyGuard"
	_guard.collision_layer = 1
	_guard.collision_mask = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = ADMISSION_BOUNDS.size
	collision.shape = box
	collision.position = ADMISSION_BOUNDS.get_center()
	_guard.add_child(collision)
	add_child(_guard)
func _physics_process(_delta: float) -> void:
	# Teleport/save admission can bypass walls; cancel safely if any actor appears inside.
	if not is_instance_valid(_current_vehicle_visual) or not is_admission_clear(): cancel_presentation()

func _release_guard() -> void:
	set_physics_process(false)
	if is_instance_valid(_guard):
		_guard.collision_layer = 0
		_guard.queue_free()
	_guard = null

## Returns true if a presentation sequence is currently active.
func is_active() -> bool:
	return _current_phase != Phase.IDLE

## Returns the current presentation phase enum value.
func get_phase() -> Phase:
	return _current_phase

## Returns the human-readable string name of the current phase.
func get_current_phase() -> String:
	return _phase_to_string(_current_phase)

## Returns the local center coordinates of the vehicle reception bed.
func get_reception_center() -> Vector3:
	return RECEPTION_CENTER

## Returns the maximum allowable vehicle bounding volume [Width, Height, Length].
func get_reception_size() -> Vector3:
	return RECEPTION_BOUNDS

## Returns the global transform where a scrap vehicle should be staged.
## Forward direction of the bed points towards +Z (facing out through hazard teeth).
func get_reception_transform() -> Transform3D:
	var t := global_transform
	t.origin = global_transform * RECEPTION_CENTER
	return t

## Returns the current global AABB of the moving crusher plate.
func get_crusher_plate_aabb() -> AABB:
	if _ram_plate_mesh:
		return _ram_plate_mesh.global_transform * _ram_plate_mesh.get_aabb()
	return AABB(global_position + RAM_RESTING_POS - RAM_PLATE_SIZE * 0.5, RAM_PLATE_SIZE)

## Returns the AnimatableBody3D attached to the moving ram plate, allowing integrators
## to inspect collisions or configure collision layers/masks.
func get_crusher_plate_body() -> AnimatableBody3D:
	return _ram_body

# ==============================================================================
# Internal Sequence Execution
# ==============================================================================

func _run_presentation_sequence() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	_active_tween = create_tween()
	_active_tween.set_parallel(false)
	_active_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	# --- Phase 1: APPROACHING (0.65s) ---
	# Ram slides horizontally along +Z from resting pose (-5.5) to directly overhead (0.0)
	_active_tween.tween_property(_ram_assembly, "position", RAM_ALIGNED_POS, 0.65)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# Transition to CRUSHING
	_active_tween.tween_callback(func() -> void:
		_set_phase(Phase.CRUSHING)
	)

	# --- Phase 2: CRUSHING (1.10s) ---
	# Ram descends vertically along -Y from 2.9 down to 0.90
	_active_tween.tween_property(_ram_assembly,"position:y",RAM_CRUSHED_POS.y,1.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if is_instance_valid(_current_vehicle_visual):
		var compacted_scale := _original_vehicle_scale*Vector3(1.08,.16,1.04)
		_active_tween.parallel().tween_property(_current_vehicle_visual,"scale",compacted_scale,1.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# Transition to HOLDING
	_active_tween.tween_callback(func() -> void:
		_set_phase(Phase.HOLDING)
	)

	# --- Phase 3: HOLDING (0.35s) ---
	# Hold hydraulic pressure at maximum compaction
	_active_tween.tween_interval(0.35)

	# Transition to RETRACTING
	_active_tween.tween_callback(func() -> void:
		_set_phase(Phase.RETRACTING)
	)

	# --- Phase 4: RETRACTING (1.45s total) ---
	# Step 4a: Ascend vertically along +Y back to 2.9 (0.80s)
	_active_tween.tween_property(_ram_assembly, "position:y", RAM_ALIGNED_POS.y, 0.80)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Step 4b: Slide back horizontally along -Z to resting position (-5.5) (0.65s)
	_active_tween.tween_property(_ram_assembly, "position:z", RAM_RESTING_POS.z, 0.65)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# --- Sequence Complete ---
	_active_tween.tween_callback(func() -> void:
		var compacted_ref: Node3D = _current_vehicle_visual
		_release_guard()
		_set_phase(Phase.IDLE)
		_current_vehicle_visual = null
		presentation_completed.emit(compacted_ref)
	)

func _set_phase(p: Phase) -> void:
	_current_phase = p
	phase_changed.emit(_phase_to_string(p))

func _phase_to_string(p: Phase) -> String:
	match p:
		Phase.IDLE: return "IDLE"
		Phase.APPROACHING: return "APPROACHING"
		Phase.CRUSHING: return "CRUSHING"
		Phase.HOLDING: return "HOLDING"
		Phase.RETRACTING: return "RETRACTING"
		Phase.CANCELLED: return "CANCELLED"
	return "UNKNOWN"

# ==============================================================================
# Native Geometry Assembly (Recreating V1 geometry at V2 fidelity)
# ==============================================================================

func _build_press_rig() -> void:
	# 1. Base Platform (3.4m x 0.5m x 5.0m)
	_create_base_platform()

	# 2. Four Heavy Structural Columns (0.28m x 3.8m x 0.28m)
	_create_structural_columns()

	# 3. Gantry Guide Rails (0.28m x 0.4m x 9.7m) & Crossbeams
	_create_gantry_tracks()

	# 4. Hazard Teeth at Entrance (Threshold Marker)
	_create_hazard_threshold()

	# 5. External Hydraulic Pump Unit & Motor Housing
	_create_hydraulic_pump_unit()

	# 6. Moving Press Ram Assembly (Plate, Cylinders, Rods, Kinematic Body)
	_create_ram_assembly()

func _create_base_platform() -> void:
	var platform := MeshInstance3D.new()
	platform.name = "BasePlatform"
	var box := BoxMesh.new()
	box.size = PLATFORM_SIZE
	platform.mesh = box
	platform.material_override = NecoPressMaterials.platform_base()
	platform.position = PLATFORM_CENTER
	add_child(platform)

	# Platform Static Collision
	var static_body := StaticBody3D.new()
	static_body.name = "PlatformCollision"
	var col := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = PLATFORM_SIZE
	col.shape = col_box
	static_body.position = PLATFORM_CENTER
	static_body.add_child(col)
	add_child(static_body)

func _create_structural_columns() -> void:
	var col_x := 1.6
	var col_z := 2.2
	var col_height := 3.8
	var col_thickness := 0.28
	var col_positions := [
		Vector3(-col_x, col_height * 0.5, -col_z),
		Vector3(col_x, col_height * 0.5, -col_z),
		Vector3(-col_x, col_height * 0.5, col_z),
		Vector3(col_x, col_height * 0.5, col_z),
	]

	var col_mesh := BoxMesh.new()
	col_mesh.size = Vector3(col_thickness, col_height, col_thickness)
	var col_mat := NecoPressMaterials.frame_yellow()

	for i in range(col_positions.size()):
		var col_inst := MeshInstance3D.new()
		col_inst.name = "Column_%d" % i
		col_inst.mesh = col_mesh
		col_inst.material_override = col_mat
		col_inst.position = col_positions[i]
		add_child(col_inst)

		# Static collision for columns
		var col_body := StaticBody3D.new()
		col_body.name = "ColumnCollision_%d" % i
		var c_shape := CollisionShape3D.new()
		var c_box := BoxShape3D.new()
		c_box.size = col_mesh.size
		c_shape.shape = c_box
		col_body.position = col_positions[i]
		col_body.add_child(c_shape)
		add_child(col_body)

func _create_gantry_tracks() -> void:
	var rail_len := 9.7
	var rail_height := 0.40
	var rail_thick := 0.28
	var rail_y := 3.90
	var rail_z := -2.40  # Extends back to -7.25 to accommodate ram resting pose
	var rail_x := 1.60

	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(rail_thick, rail_height, rail_len)
	var rail_mat := NecoPressMaterials.gantry_steel()

	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.name = "GantryRail_%s" % ("Left" if side < 0.0 else "Right")
		rail.mesh = rail_mesh
		rail.material_override = rail_mat
		rail.position = Vector3(side * rail_x, rail_y, rail_z)
		add_child(rail)

	# Transverse crossbeams linking the rails (Front, Mid, Rear)
	var beam_len := (rail_x * 2.0) + rail_thick
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(beam_len, 0.30, 0.35)
	var beam_mat := NecoPressMaterials.frame_yellow()

	var beam_zs := [2.2, -0.5, -3.2, -6.8]
	for idx in range(beam_zs.size()):
		var beam := MeshInstance3D.new()
		beam.name = "Crossbeam_%d" % idx
		beam.mesh = beam_mesh
		beam.material_override = beam_mat
		beam.position = Vector3(0.0, rail_y + 0.15, beam_zs[idx])
		add_child(beam)

func _create_hazard_threshold() -> void:
	# 7 Hazard threshold teeth across front edge of platform (z = +2.45)
	var tooth_count := 7
	var span_x := 2.8
	var step_x := span_x / float(tooth_count - 1)
	var start_x := -span_x * 0.5
	var tooth_mat := NecoPressMaterials.hazard_yellow()

	var prism := PrismMesh.new()
	prism.size = Vector3(0.30, 0.20, 0.25)

	for i in range(tooth_count):
		var tooth := MeshInstance3D.new()
		tooth.name = "HazardTooth_%d" % i
		tooth.mesh = prism
		tooth.material_override = tooth_mat
		tooth.position = Vector3(start_x + (i * step_x), RECEPTION_BED_SURFACE_Y + 0.10, 2.40)
		add_child(tooth)

func _create_hydraulic_pump_unit() -> void:
	# Unit sits at side (X = 2.3, Y = 0.7, Z = -0.5)
	var pump_root := Node3D.new()
	pump_root.name = "HydraulicPumpStation"
	pump_root.position = Vector3(2.35, 0.70, -0.50)
	add_child(pump_root)

	# Main housing box (1.0m x 1.4m x 1.3m)
	var housing := MeshInstance3D.new()
	housing.name = "PumpHousing"
	var h_mesh := BoxMesh.new()
	h_mesh.size = Vector3(1.0, 1.4, 1.3)
	housing.mesh = h_mesh
	housing.material_override = NecoPressMaterials.pump_housing()
	pump_root.add_child(housing)

	# Motor cylinder on top of housing
	var motor := MeshInstance3D.new()
	motor.name = "ElectricMotor"
	var m_cyl := CylinderMesh.new()
	m_cyl.top_radius = 0.22
	m_cyl.bottom_radius = 0.22
	m_cyl.height = 0.65
	motor.mesh = m_cyl
	motor.material_override = NecoPressMaterials.dark_iron()
	motor.rotation_degrees = Vector3(0, 0, 90)
	motor.position = Vector3(0.0, 0.85, 0.15)
	pump_root.add_child(motor)

	# Pressure manifold & valve block
	var valve := MeshInstance3D.new()
	valve.name = "ValveBlock"
	var v_box := BoxMesh.new()
	v_box.size = Vector3(0.35, 0.35, 0.50)
	valve.mesh = v_box
	valve.material_override = NecoPressMaterials.dark_iron()
	valve.position = Vector3(-0.35, 0.45, -0.20)
	pump_root.add_child(valve)

	# High pressure rubber hose coupling running upwards to gantry
	var hose := MeshInstance3D.new()
	hose.name = "HydraulicHose"
	var h_cyl := CylinderMesh.new()
	h_cyl.top_radius = 0.04
	h_cyl.bottom_radius = 0.04
	h_cyl.height = 2.6
	hose.mesh = h_cyl
	hose.material_override = NecoPressMaterials.rubber_hose()
	hose.position = Vector3(-0.45, 1.4, -0.20)
	hose.rotation_degrees = Vector3(0, 0, -12)
	pump_root.add_child(hose)

	# Static collision for pump unit
	var p_body := StaticBody3D.new()
	p_body.name = "PumpCollision"
	var p_shape := CollisionShape3D.new()
	var p_box := BoxShape3D.new()
	p_box.size = Vector3(1.1, 1.5, 1.4)
	p_shape.shape = p_box
	p_body.add_child(p_shape)
	pump_root.add_child(p_body)

func _create_ram_assembly() -> void:
	_ram_assembly = Node3D.new()
	_ram_assembly.name = "RamAssembly"
	_ram_assembly.position = RAM_RESTING_POS
	add_child(_ram_assembly)

	# Main Pressing Plate (2.9m x 0.35m x 4.5m)
	_ram_plate_mesh = MeshInstance3D.new()
	_ram_plate_mesh.name = "PressPlate"
	var plate_box := BoxMesh.new()
	plate_box.size = RAM_PLATE_SIZE
	_ram_plate_mesh.mesh = plate_box
	_ram_plate_mesh.material_override = NecoPressMaterials.press_plate()
	_ram_assembly.add_child(_ram_plate_mesh)

	# Kinematic / Animatable Body attached to the moving ram plate
	_ram_body = AnimatableBody3D.new()
	_ram_body.name = "RamCollisionBody"
	_ram_body.sync_to_physics = false
	# Active swept-volume guard protects actors; moving plate never pushes/crushes them.
	_ram_body.collision_layer = 0
	_ram_body.collision_mask = 0
	_ram_collision = CollisionShape3D.new()
	var ram_box := BoxShape3D.new()
	ram_box.size = RAM_PLATE_SIZE
	_ram_collision.shape = ram_box
	_ram_body.add_child(_ram_collision)
	_ram_assembly.add_child(_ram_body)

	# Reinforcement I-beams on top of plate
	var rib_mesh := BoxMesh.new()
	rib_mesh.size = Vector3(2.8, 0.25, 0.20)
	var rib_mat := NecoPressMaterials.frame_yellow()
	for rz in [-1.5, -0.5, 0.5, 1.5]:
		var rib := MeshInstance3D.new()
		rib.name = "PlateRib_%s" % str(rz).replace(".", "_")
		rib.mesh = rib_mesh
		rib.material_override = rib_mat
		rib.position = Vector3(0.0, 0.25, rz)
		_ram_assembly.add_child(rib)

	# Dual Hydraulic Cylinders (Left & Right at X = ±1.4)
	var cyl_radius := 0.14
	var cyl_height := 1.30
	var cyl_mesh := CylinderMesh.new()
	cyl_mesh.top_radius = cyl_radius
	cyl_mesh.bottom_radius = cyl_radius
	cyl_mesh.height = cyl_height
	var cyl_mat := NecoPressMaterials.dark_iron()

	var rod_radius := 0.08
	var rod_height := 1.40
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = rod_radius
	rod_mesh.bottom_radius = rod_radius
	rod_mesh.height = rod_height
	var rod_mat := NecoPressMaterials.piston_chrome()

	for side in [-1.0, 1.0]:
		var side_name := "Left" if side < 0.0 else "Right"
		var cyl_root := Node3D.new()
		cyl_root.name = "HydraulicCylinder_%s" % side_name
		cyl_root.position = Vector3(side * 1.38, 0.75, 0.0)
		_ram_assembly.add_child(cyl_root)

		var cyl_inst := MeshInstance3D.new()
		cyl_inst.mesh = cyl_mesh
		cyl_inst.material_override = cyl_mat
		cyl_root.add_child(cyl_inst)

		var rod_inst := MeshInstance3D.new()
		rod_inst.mesh = rod_mesh
		rod_inst.material_override = rod_mat
		rod_inst.position = Vector3(0.0, 0.55, 0.0)
		cyl_root.add_child(rod_inst)
