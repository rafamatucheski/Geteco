extends SceneTree

const STYLE = preload("res://geodata/roads/BridgeSurfaceStyle.gd")
const NETWORK = preload("res://geodata/roads/UnifiedRoadNetwork2D.gd")
const CONNECTOR = preload("res://world/harbor/HarborMountainConnector.gd")
const MOUNTAIN_ROAD = preload("res://world/mountain_pass/MountainPassRoad.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(condition: bool, label: String) -> void:
	print(("PASS " if condition else "FAIL ") + label)
	if not condition:
		failures.append(label)


func _run() -> void:
	check(STYLE.ASPHALT == NETWORK.ROAD_COLOR, "bridge asphalt uses the city road palette")
	check(STYLE.SHOULDER == NETWORK.SIDEWALK_COLOR, "bridge shoulder uses the city road palette")
	check(STYLE.LANE == NETWORK.LANE_COLOR, "bridge lane marking uses the city road palette")
	check(STYLE.DASH_LENGTH == NETWORK.DASH_LENGTH and STYLE.DASH_GAP == NETWORK.DASH_GAP, "bridge dash cadence matches the city road network")

	var gap := CONNECTOR._inner_gap_polygon()
	var gap_bounds := Rect2(gap[0], Vector2.ZERO)
	for point in gap:
		gap_bounds = gap_bounds.expand(point)
	check(gap.size() == 26, "transition gap follows both authored carriageway edges")
	check(gap_bounds.size.x <= 201.0 and gap_bounds.size.y < 40.0, "transition fill is a narrow seam instead of a deck-wide rectangle")

	var transition_rails := CONNECTOR.transition_guardrail_segments()
	check(transition_rails.size() == 2, "transition has guardrails on both outside edges")
	for index in transition_rails.size():
		var rail := transition_rails[index]
		check(rail[0].x == CONNECTOR.TAPER_START_X and rail[-1].x == 7300.0, "transition guardrail is continuous from the straight deck to the abutment")
		check(rail[0].y == [-4725.0, -4395.0][index], "transition guardrail joins the existing outside edge without a lateral gap")

	var mountain_road = MOUNTAIN_ROAD.new()
	mountain_road._build_curve()
	mountain_road.junctions.road_curve = mountain_road.curve
	mountain_road.junctions.half_road = mountain_road.road_width * 0.5
	mountain_road._precompute_centerlines()
	check(not mountain_road._cached_bridge_centerline_dashes.is_empty(), "mountain bridge publishes dashed center markings")
	check(mountain_road._cached_bridge_centerline_dashes[0].is_equal_approx(mountain_road.smooth_points[0]), "yellow marking starts at the mountain seam, outside the divided approach")
	check(not mountain_road._cached_centerlines_low.is_empty(), "mountain road retains its double centerline after the bridge")
	var first_double := mountain_road._cached_centerlines_low[0] as PackedVector2Array
	check(first_double[0].x >= 4640.0, "double centerline starts at the bridge abutment, not inside the deck")
	mountain_road.free()
	print("BRIDGE_SURFACE_STANDARD failures=", failures)
	quit(0 if failures.is_empty() else 1)
