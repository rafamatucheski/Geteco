class_name AnimatedPedestrian3D
extends CharacterBody2D

## Primitive meshes are immutable after construction. Reusing them across
## citizens avoids recreating/uploading the same body parts for every rig;
## materials and transforms remain owned by each actor.
static var _primitive_mesh_cache: Dictionary = {}
static var _ambient_rig_template: Node3D
static var _presentation_material_templates: Dictionary = {}
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")

enum DistrictTheme {
	ALL_MIXED,       # 0: Mistura orgÃ¢nica de todos os distritos
	CITY_DOWNTOWN,   # 1: Bairro Urbano Central (Executivos, UniversitÃ¡rios, Casual)
	WINTER_SNOW,     # 2: Bairro de Frio (Parkas com pele felpuda, gorros de lÃ£, cachecÃ³is)
	DESERT_BADLANDS, # 3: Bairro de Deserto (Cowboys, chapÃ©u de aba larga, bandanas, couro)
	FOREST_WOODS,    # 4: Bairro de Floresta (Lenhadores flanela xadrez, mochilas de trilha, rangers)
	BEACH_COASTAL    # 5: Bairro Praiano / Lazer (Camisas floridas havaianas, bermudas, surfistas)
}

enum Archetype {
	# Bairro da Cidade (Downtown)
	CITY_EXECUTIVE,
	CITY_CASUAL,
	CITY_STUDENT_BACKPACK,
	CITY_POLICE_OFFICER,
	CITY_JOGGER,
	CITY_GANGSTER,
	CITY_TOURIST,
	CITY_ELDERLY,
	
	# Bairro de Frio (Winter Snow)
	WINTER_PARKA_FUR,
	WINTER_BEANIE_SCARF,
	WINTER_SKI_PUFFER,
	WINTER_EARMUFFS_COAT,
	
	# Bairro de Deserto (Desert Badlands)
	DESERT_COWBOY_HAT,
	DESERT_NOMAD_BANDANA,
	DESERT_BIKER_LEATHER,
	DESERT_RANCHER_STRAW,
	
	# Bairro de Floresta (Forest Woods)
	FOREST_LUMBERJACK_PLAID,
	FOREST_HIKER_BACKPACK,
	FOREST_PARK_RANGER,
	FOREST_CABIN_HUNTER,
	
	# Bairro Praiano (Beach Coastal)
	BEACH_HAWAIIAN_FLORAL,
	BEACH_SURFER_SUMMER,
	BEACH_FITNESS_RUNNER,
	BEACH_CASUAL_RESORT
}

@export var district_theme: DistrictTheme = DistrictTheme.ALL_MIXED
@export var base_walk_speed: float = 52.0
## -1 chooses from the district pool. A non-negative value selects a stable
## index from that theme's pool before the 3D model is built.
@export var archetype_override: int = -1
## Disable this for city-route pedestrians: runner clothing remains available,
## but ambient citizens only sprint after panic or during active combat.
@export var ambient_running_enabled: bool = true

var archetype: Archetype
var walk_target: Vector2 = Vector2.ZERO
var walk_timer: float = 0.0
var stride_freq_mult: float = 1.0
var gait: RefCounted
var _gait_last_position := Vector2.ZERO
var _gait_position_valid := false
var walk_dir: Vector2 = Vector2.RIGHT
var is_scared: bool = false
var panic_timer: float = 0.0
var danger_response := preload("res://characters/PedestrianDanger.gd").new()
enum CivilianReaction { FLEE, CALL_POLICE, FIGHT, ARMED }
## A stable tendency for this citizen. -1 rolls on the first witnessed player attack.
var civilian_reaction_profile := -1
var civilian_reaction := CivilianReaction.FLEE
var civilian_reaction_time := 0.0
var civilian_call_progress := 0.0
var civilian_call_started := false
var civilian_called_police := false
var civilian_threat: Node2D
var civilian_sight_timer := 0.0
var civilian_has_sight := false
var _horn_escape_target := Vector2.ZERO
var _horn_escape_time := 0.0
var panic_recovery := 0.0
@export var max_health: int = 40
var health: int = 40
var is_dead: bool = false
var fall_presentation := preload("res://characters/CharacterFallPresentation.gd").new()
## Knocked down but alive (survivable vehicle impact, see get_run_over()) --
## frozen on the ground waiting for an ambulance. Shared medical care gives
## nonfatal injuries one hospital day and critical injuries two days.
var is_incapacitated: bool = false

# Escala e Porte FÃ­sico Ãšnicos (Silhuetas reais variadas)
var body_height_scale: float = 1.0
var body_width_scale: float = 1.0
enum BodyType { AVERAGE, SLIM, HEAVY, TALL, SHORT }
@export var body_type_override: int = -1
@export_enum("AleatÃ³rio", "Homem", "Mulher") var appearance_gender := 0
@export var appearance_seed := -1
@export var hair_style_override := -1
## -1 selects a stable facial-hair style from identity; 0 is clean shaven.
@export_range(-1,5,1) var beard_style_override := -1
var body_type: BodyType = BodyType.AVERAGE
# Height, torso width, torso depth, limb thickness. Clothing is independent.
const BODY_PROPORTIONS := [
	Vector4(1.0, 1.0, 1.0, 1.0),
	Vector4(1.02, 0.72, 0.78, 0.72),
	Vector4(1.0, 1.35, 1.24, 1.16),
	Vector4(1.12, 0.88, 0.90, 0.90),
	Vector4(0.86, 1.03, 1.0, 1.0),
]

# SubViewport 3D
var viewport: SubViewport
var _presentation_world_origin := Vector3.ZERO
var _presentation_shared_world := false
var _presentation_atlas_active := false
var _presentation_atlas_region := Rect2()
var _atlas_visibility_reported := false
var _atlas_reported_visible := false
var _atlas_reported_hz := 0.0
signal presentation_ready
var defer_presentation := false
## Ambient population may use a complete physical low-detail rig. Mission and
## combat actors keep the authored accessory rig below.
@export var ambient_low_lod := false
## Ambient authored citizens may share a batched atlas while retaining the
## complete clothing/accessory rig. This avoids allocating and initializing a
## separate SubViewport/World3D for every late population materialization.
@export var ambient_presentation_atlas := false
var _presentation_fallback: Polygon2D
var _presentation_building := false
var _presentation_stage_max_usec := 0
var _presentation_stage_count := 0
const PRESENTATION_SIZE := Vector2i(104, 104)
const SLEEP_PRESENTATION_SIZE := Vector2i(52, 52)
const PRESENTATION_DISPLAY_SCALE := 0.38 * 96.0 / 104.0

static func prewarm_ambient_primitives() -> void:
	# Resolve the primitive meshes during Harbor loading. Assigning one of these
	# resources for the first time can otherwise synchronize the render thread
	# on the exact frame a resident enters the camera.
	_cached_capsule(0.17, 0.48)
	_cached_sphere(0.17, 0.34)
	for limb in [Vector2(.050, .22), Vector2(.042, .18), Vector2(.068, .28), Vector2(.058, .26)]:
		_cached_cylinder(limb.x, limb.x * .85, limb.y)
	for radius in [.046, .062]:
		_cached_sphere(radius, radius * 2.0)
	_cached_box(Vector3(.19, .14, .16))
	_cached_box(Vector3(.24, .025, .16))

func ensure_presentation() -> void:
	if viewport != null or _presentation_building:
		return
	if ambient_presentation_atlas and not ambient_low_lod:
		_presentation_building = true
		_build_staged_authored_presentation.call_deferred()
		return
	_build_3d_viewport()
	_complete_presentation_request()

func _build_staged_authored_presentation() -> void:
	await _build_3d_viewport()
	if not is_inside_tree() or viewport == null:
		_presentation_building = false
		return
	_complete_presentation_request()

func _complete_presentation_request() -> void:
	_presentation_building = false
	if is_instance_valid(_presentation_fallback):
		_presentation_fallback.queue_free()
	presentation_ready.emit()

func _reserve_presentation_stage(label: StringName) -> Dictionary:
	return await RUNTIME_WORK.reserve(
		self,
		StringName("pedestrian_presentation/%s" % String(label)),
		RUNTIME_WORK.PRIORITY_VISIBLE,
		RUNTIME_WORK.FRAME_BUDGET_USEC
	)

func _complete_presentation_stage(ticket: Dictionary, started_usec: int) -> void:
	if ticket.is_empty():
		return
	var actual_usec := Time.get_ticks_usec() - started_usec
	if actual_usec > _presentation_stage_max_usec:
		_presentation_stage_max_usec = actual_usec
		set_meta("presentation_stage_max_label", String(ticket.get("producer", "")))
	_presentation_stage_count += 1
	RUNTIME_WORK.complete(ticket, actual_usec)
	set_meta("presentation_stage_max_usec", _presentation_stage_max_usec)
	set_meta("presentation_stage_count", _presentation_stage_count)

func queue_presentation() -> void:
	if viewport != null or not is_inside_tree():
		return
	if get_meta("presentation_wait_for_close", false):
		return
	var budget := get_node_or_null("/root/PresentationBudget")
	if budget != null:
		budget.request(self)

func compact_presentation_for_sleep() -> void:
	if _presentation_atlas_active:
		_viewport_render_active = false
		_atlas_visibility_reported = false
		if not is_inside_tree():
			return
		var budget := get_node_or_null("/root/PresentationBudget")
		if budget != null and budget.has_method("set_ambient_atlas_actor_active"):
			budget.set_ambient_atlas_actor_active(self, false)
		return
	if viewport == null or viewport.size == SLEEP_PRESENTATION_SIZE: return
	viewport.size = SLEEP_PRESENTATION_SIZE

func restore_presentation_after_sleep() -> void:
	if _presentation_atlas_active:
		_viewport_cull_timer = 0.0
		_atlas_visibility_reported = false
		if not is_inside_tree():
			return
		var budget := get_node_or_null("/root/PresentationBudget")
		if budget != null and budget.has_method("set_ambient_atlas_actor_active"):
			budget.set_ambient_atlas_actor_active(self, true)
		return
	if viewport == null or viewport.size == PRESENTATION_SIZE: return
	_presentation_restore_pending = true
	# Let the regular presentation cadence request the first restored frame. A
	# synchronous UPDATE_ONCE here blocks the proximity transition frame.
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

var sprite_3d_display: Sprite2D

# The 3D rig render pass is expensive (own_world_3d + full scene submission)
# and was previously always-on regardless of camera distance. Only characters
# actually near the active camera need it updated every frame.
const VIEWPORT_CULL_CHECK_INTERVAL := 0.3
# Atlas membership checks are cheap and need a shorter horizon while driving;
# at 0.1 s the existing margin covers actors entering through the camera edge.
const ATLAS_VIEWPORT_CULL_CHECK_INTERVAL := 0.1
# The rig is ready more than two seconds before a normal walker reaches the
# screen, without submitting offscreen 3D viewports across a wider empty ring.
const VIEWPORT_CULL_MARGIN := 120.0
var _viewport_cull_timer: float = 0.0
var _viewport_render_active: bool = true
var _viewport_frame_timer: float = 0.0
var _viewport_frame_interval: float = 1.0 / 60.0
var _presentation_restore_pending := false
var viewport_render_requests: int = 0
var _fallen_presentation_cached := false

# Rig 3D
var model_root: Node3D
var torso_node: Node3D
var head_node: Node3D
var left_upper_arm: Node3D
var left_lower_arm: Node3D
var right_upper_arm: Node3D
var right_lower_arm: Node3D
var left_upper_leg: Node3D
var left_lower_leg: Node3D
var right_upper_leg: Node3D
var right_lower_leg: Node3D
var muzzle_flash_3d: MeshInstance3D

# Materiais e CustomizaÃ§Ãµes Visuais
var skin_color: Color
var hair_color: Color
var shirt_color: Color
var pants_color: Color
var shoe_color: Color
var hat_color: Color
var accessory_color: Color

# Flags de Detalhamento Visual FÃ­sico 3D
var has_cowboy_hat: bool = false
var has_beanie: bool = false
var has_fur_hood: bool = false
var has_ranger_hat: bool = false
var has_cap: bool = false
var has_earmuffs: bool = false
var has_visor: bool = false
var has_sunglasses: bool = false
var has_beard: bool = false
var has_scarf: bool = false
var has_bandana: bool = false
var has_tie: bool = false
var has_backpack: bool = false
var has_sleeping_bag: bool = false
var has_vest: bool = false
var has_badge: bool = false
var has_briefcase: bool = false
var has_coffee_cup: bool = false
var has_surfboard: bool = false
var has_headband: bool = false
var has_camera: bool = false
var has_walking_stick: bool = false
var has_handgun: bool = false

# Flags de Combate e Comportamento
var is_gangster: bool = false
var is_jogger: bool = false
var combat_target: Node2D = null
var gun_cooldown: float = 0.0
var dropped_cash: int = 35

# Timers de Comportamento Bioma
var behavior_timer: float = 0.0
var behavior_action: int = 0 # 0 = Normal, 1 = Tremer de frio, 2 = Limpar suor, 3 = Olhar natureza, 4 = Celular
const AMBIENT_NAVIGATION_INTERVAL := 1.0 / 30.0
# Ambient walkers do not need a full CharacterBody2D decision/motion pass at
# 60 Hz. The accumulated delta preserves travel speed while priority actors
# remain on the fixed physics cadence.
const AMBIENT_PHYSICS_INTERVAL := 1.0 / 30.0
var _ambient_physics_elapsed := 0.0
var _ambient_step_prepared := false
var _ambient_prepared_delta := 0.0
var _ambient_navigation_elapsed := 0.0
var _ambient_navigation_velocity := Vector2.ZERO
var _ambient_navigation_target := Vector2.INF

func _ready() -> void:
	# MultidÃµes repartem buscas; os agentes de emergÃªncia usam o orÃ§amento maior.
	movement_navigation.search_budget = 48
	movement_navigation.retry_delay = 2.5
	add_to_group("pedestrian")
	add_to_group("damageable")
	z_index = 6
	
	walk_timer = randf_range(0.0, 50.0)
	stride_freq_mult = randf_range(0.85, 1.15)
	
	collision_layer = 4
	collision_mask = 1 | 2 | 4 # CenÃ¡rio, veÃ­culos e pessoas.
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	platform_floor_layers = 0
	platform_wall_layers = 0
	platform_on_leave = CharacterBody2D.PLATFORM_ON_LEAVE_DO_NOTHING
	if get_node_or_null("CollisionShape2D") == null:
		var c := CollisionShape2D.new()
		c.name = "CollisionShape2D"
		var circle := CircleShape2D.new()
		circle.radius = 11.0
		c.shape = circle
		add_child(c)
	
	_setup_district_and_archetype()
	preload("res://characters/pedestrians/CitizenAppearance.gd").prepare(self)
	if defer_presentation:
		# A silhueta mantÃ©m o cidadÃ£o visÃ­vel enquanto o detalhe aguarda orÃ§amento.
		_presentation_fallback = Polygon2D.new()
		_presentation_fallback.polygon = PackedVector2Array([Vector2(-5, 0), Vector2(-5, -16), Vector2(0, -22), Vector2(5, -16), Vector2(5, 0)])
		_presentation_fallback.color = shirt_color
		add_child(_presentation_fallback)
		if not get_meta("presentation_wait_for_close", false):
			get_node("/root/PresentationBudget").request(self)
	else:
		_build_3d_viewport()
	_pick_new_sidewalk_target()
	# Ambient route and movement work is distributed at 30 Hz; danger/combat
	# actors stay at the full physics cadence so chaos remains responsive.
	_ambient_physics_elapsed = randf_range(0.0, AMBIENT_PHYSICS_INTERVAL)
	_ambient_navigation_elapsed = randf_range(0.0, AMBIENT_NAVIGATION_INTERVAL)
	# Stagger the first check across instances so 39+ pedestrians don't all
	# query the active camera on the same frame.
	_viewport_cull_timer = randf_range(0.0, VIEWPORT_CULL_CHECK_INTERVAL)
	_viewport_frame_timer = randf_range(0.0, 1.0 / 30.0)

func _setup_district_and_archetype() -> void:
	# VariaÃ§Ã£o de Altura e Largura Corporal (Portes FÃ­sicos Distintos)
	body_height_scale = randf_range(0.90, 1.14)
	body_width_scale = randf_range(0.88, 1.18)

	# Tons de Pele Naturais e Diversos (8 tonalidades calibradas)
	var skin_tones := [
		Color(0.96, 0.84, 0.74), # Pele Clara NÃ³rdica
		Color(0.90, 0.76, 0.62), # Pele Clara Rosada
		Color(0.82, 0.66, 0.50), # Moreno Claro / Oliva
		Color(0.72, 0.54, 0.38), # Moreno / Bronze Tan
		Color(0.58, 0.40, 0.26), # Moreno Escuro / Caramelo
		Color(0.44, 0.28, 0.18), # Negro / Chocolate
		Color(0.32, 0.20, 0.14), # Negro Retinto / Espresso
		Color(0.24, 0.15, 0.10)  # Ã‰bano Profundo
	]
	skin_color = skin_tones[randi() % skin_tones.size()]

	var hair_tones := [
		Color(0.10, 0.10, 0.10), # Preto Ã”nix
		Color(0.28, 0.18, 0.12), # Castanho Escuro
		Color(0.48, 0.30, 0.16), # Castanho MÃ©dio
		Color(0.72, 0.44, 0.20), # Castanho Acobreado
		Color(0.88, 0.72, 0.38), # Loiro Dourado
		Color(0.78, 0.28, 0.14), # Ruivo Vivo
		Color(0.68, 0.68, 0.70), # Grisalho / Prata
		Color(0.92, 0.92, 0.94)  # Branco Platinado
	]
	hair_color = hair_tones[randi() % hair_tones.size()]

	var target_pool: Array[Archetype] = []
	match district_theme:
		DistrictTheme.CITY_DOWNTOWN:
			target_pool = [
				Archetype.CITY_EXECUTIVE, Archetype.CITY_CASUAL, Archetype.CITY_STUDENT_BACKPACK, Archetype.CITY_POLICE_OFFICER,
				Archetype.CITY_JOGGER, Archetype.CITY_GANGSTER, Archetype.CITY_TOURIST, Archetype.CITY_ELDERLY
			]
		DistrictTheme.WINTER_SNOW:
			target_pool = [Archetype.WINTER_PARKA_FUR, Archetype.WINTER_BEANIE_SCARF, Archetype.WINTER_SKI_PUFFER, Archetype.WINTER_EARMUFFS_COAT]
		DistrictTheme.DESERT_BADLANDS:
			target_pool = [Archetype.DESERT_COWBOY_HAT, Archetype.DESERT_NOMAD_BANDANA, Archetype.DESERT_BIKER_LEATHER, Archetype.DESERT_RANCHER_STRAW]
		DistrictTheme.FOREST_WOODS:
			target_pool = [Archetype.FOREST_LUMBERJACK_PLAID, Archetype.FOREST_HIKER_BACKPACK, Archetype.FOREST_PARK_RANGER, Archetype.FOREST_CABIN_HUNTER]
		DistrictTheme.BEACH_COASTAL:
			target_pool = [Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER, Archetype.BEACH_FITNESS_RUNNER, Archetype.BEACH_CASUAL_RESORT]
		_: # ALL_MIXED
			target_pool = [
				Archetype.CITY_EXECUTIVE, Archetype.CITY_CASUAL, Archetype.CITY_STUDENT_BACKPACK, Archetype.CITY_POLICE_OFFICER,
				Archetype.CITY_JOGGER, Archetype.CITY_GANGSTER, Archetype.CITY_TOURIST, Archetype.CITY_ELDERLY,
				Archetype.WINTER_PARKA_FUR, Archetype.WINTER_BEANIE_SCARF, Archetype.WINTER_SKI_PUFFER, Archetype.WINTER_EARMUFFS_COAT,
				Archetype.DESERT_COWBOY_HAT, Archetype.DESERT_NOMAD_BANDANA, Archetype.DESERT_BIKER_LEATHER, Archetype.DESERT_RANCHER_STRAW,
				Archetype.FOREST_LUMBERJACK_PLAID, Archetype.FOREST_HIKER_BACKPACK, Archetype.FOREST_PARK_RANGER, Archetype.FOREST_CABIN_HUNTER,
				Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER, Archetype.BEACH_FITNESS_RUNNER, Archetype.BEACH_CASUAL_RESORT
			]

	if archetype_override >= 0:
		archetype = target_pool[posmod(archetype_override, target_pool.size())]
	else:
		archetype = target_pool[randi() % target_pool.size()]

	match archetype:
		# === 1. BAIRRO DA CIDADE (DOWNTOWN) ===
		Archetype.CITY_EXECUTIVE:
			var suits := [Color(0.12, 0.13, 0.16), Color(0.18, 0.22, 0.32), Color(0.28, 0.30, 0.34)]
			shirt_color = suits[randi() % suits.size()]
			pants_color = shirt_color
			shoe_color = Color(0.08, 0.08, 0.08)
			has_tie = true
			has_briefcase = true
			has_coffee_cup = randf() < 0.50
			has_sunglasses = randf() < 0.40
			dropped_cash = randi_range(40, 120)

		Archetype.CITY_CASUAL:
			var casual_colors := [Color("2980b9"), Color("c0392b"), Color("27ae60"), Color("8e44ad"), Color("d35400"), Color("34495e")]
			shirt_color = casual_colors[randi() % casual_colors.size()]
			pants_color = Color("1e272e") if randf() < 0.6 else Color("2c3e50")
			shoe_color = Color(0.85, 0.85, 0.88)
			has_cap = randf() < 0.45
			has_sunglasses = randf() < 0.50
			dropped_cash = randi_range(20, 60)

		Archetype.CITY_STUDENT_BACKPACK:
			shirt_color = Color("e74c3c") if randf() < 0.5 else Color("f39c12")
			pants_color = Color("2d3436")
			shoe_color = Color(0.9, 0.9, 0.9)
			has_backpack = true
			has_coffee_cup = true
			accessory_color = Color("0984e3")
			has_cap = randf() < 0.60
			dropped_cash = randi_range(15, 45)

		Archetype.CITY_POLICE_OFFICER:
			shirt_color = Color(0.11, 0.15, 0.24)
			pants_color = Color(0.09, 0.12, 0.20)
			shoe_color = Color(0.06, 0.06, 0.06)
			has_cap = true
			has_badge = true
			has_sunglasses = randf() < 0.65
			dropped_cash = randi_range(30, 80)

		Archetype.CITY_JOGGER:
			# Atleta / Corredor Urbano
			is_jogger = true
			var tank_colors := [Color("00cec9"), Color("ff7675"), Color("fdcb6e"), Color("e84393")]
			shirt_color = tank_colors[randi() % tank_colors.size()]
			pants_color = Color("2d3436")
			shoe_color = Color("fab1a0")
			has_headband = true
			accessory_color = shirt_color
			base_walk_speed = 135.0
			dropped_cash = randi_range(10, 35)

		Archetype.CITY_GANGSTER:
			# Membro de Gangue Urbana Armada
			is_gangster = true
			health = 70
			var jackets := [Color("1e272e"), Color("2d3436"), Color("4b4b4b"), Color("576574")]
			shirt_color = jackets[randi() % jackets.size()]
			pants_color = Color("1e272e")
			shoe_color = Color("000000")
			has_beanie = randf() < 0.5
			has_bandana = randf() < 0.6
			accessory_color = Color("c0392b")
			has_handgun = true
			has_sunglasses = randf() < 0.70
			dropped_cash = randi_range(120, 350)

		Archetype.CITY_TOURIST:
			# Turista com CÃ¢mera e Mapa
			var retro_shirts := [Color("f1c40f"), Color("e67e22"), Color("1abc9c"), Color("3498db")]
			shirt_color = retro_shirts[randi() % retro_shirts.size()]
			pants_color = Color("ecf0f1")
			shoe_color = Color("bdc3c7")
			has_camera = true
			has_sunglasses = true
			has_cap = true
			hat_color = Color("e67e22")
			dropped_cash = randi_range(60, 180)

		Archetype.CITY_ELDERLY:
			# Idoso com Passo Calmo e Bengala
			var coats := [Color("7f8c8d"), Color("95a5a6"), Color("57606f")]
			shirt_color = coats[randi() % coats.size()]
			pants_color = Color("2f3542")
			shoe_color = Color("1e272e")
			has_walking_stick = true
			has_cap = true
			hat_color = Color("2f3542")
			base_walk_speed = 36.0
			dropped_cash = randi_range(30, 90)

		# === 2. BAIRRO DE FRIO / NEVE (WINTER) ===
		Archetype.WINTER_PARKA_FUR:
			body_width_scale = randf_range(1.20, 1.34) # Silhueta encorpada de casaco acolchoado
			var parkas := [Color(0.15, 0.25, 0.35), Color(0.55, 0.15, 0.15), Color(0.20, 0.30, 0.22), Color(0.25, 0.25, 0.28)]
			shirt_color = parkas[randi() % parkas.size()]
			pants_color = Color(0.12, 0.12, 0.14)
			shoe_color = Color(0.20, 0.18, 0.16)
			has_fur_hood = true
			has_beanie = true
			hat_color = Color(0.88, 0.88, 0.90)

		Archetype.WINTER_BEANIE_SCARF:
			body_width_scale = randf_range(1.10, 1.25)
			shirt_color = Color(0.18, 0.20, 0.25)
			pants_color = Color(0.14, 0.15, 0.18)
			shoe_color = Color(0.10, 0.10, 0.12)
			has_beanie = true
			hat_color = Color("c0392b") if randf() < 0.5 else Color("d35400")
			has_scarf = true
			accessory_color = Color("f1c40f") if randf() < 0.5 else Color("ecf0f1")

		Archetype.WINTER_SKI_PUFFER:
			body_width_scale = randf_range(1.22, 1.35)
			var puffers := [Color("0984e3"), Color("d63031"), Color("00cec9"), Color("fdcb6e")]
			shirt_color = puffers[randi() % puffers.size()]
			pants_color = Color(0.15, 0.16, 0.20)
			shoe_color = Color(0.22, 0.24, 0.28)
			has_beanie = true
			hat_color = shirt_color
			has_sunglasses = true

		Archetype.WINTER_EARMUFFS_COAT:
			shirt_color = Color(0.35, 0.28, 0.24)
			pants_color = Color(0.18, 0.18, 0.20)
			shoe_color = Color(0.15, 0.12, 0.10)
			has_earmuffs = true
			has_scarf = true
			accessory_color = Color(0.85, 0.20, 0.20)

		# === 3. BAIRRO DE DESERTO (DESERT BADLANDS) ===
		Archetype.DESERT_COWBOY_HAT:
			shirt_color = Color(0.92, 0.88, 0.78)
			pants_color = Color(0.22, 0.32, 0.50)
			shoe_color = Color(0.38, 0.22, 0.12)
			has_cowboy_hat = true
			hat_color = Color(0.42, 0.26, 0.14)
			has_vest = true
			accessory_color = Color(0.35, 0.20, 0.10)
			has_sunglasses = randf() < 0.50

		Archetype.DESERT_NOMAD_BANDANA:
			shirt_color = Color(0.85, 0.78, 0.65)
			pants_color = Color(0.75, 0.68, 0.55)
			shoe_color = Color(0.40, 0.32, 0.22)
			has_bandana = true
			accessory_color = Color(0.65, 0.20, 0.15)
			has_sunglasses = true

		Archetype.DESERT_BIKER_LEATHER:
			body_width_scale = randf_range(1.12, 1.28)
			shirt_color = Color(0.12, 0.12, 0.14)
			pants_color = Color(0.15, 0.16, 0.20)
			shoe_color = Color(0.08, 0.08, 0.08)
			has_bandana = true
			has_beard = true
			accessory_color = Color(0.10, 0.10, 0.10)
			has_sunglasses = true

		Archetype.DESERT_RANCHER_STRAW:
			shirt_color = Color(0.95, 0.92, 0.84)
			pants_color = Color(0.45, 0.48, 0.55)
			shoe_color = Color(0.35, 0.22, 0.12)
			has_cowboy_hat = true
			hat_color = Color(0.85, 0.75, 0.45)

		# === 4. BAIRRO DE FLORESTA (FOREST WOODS) ===
		Archetype.FOREST_LUMBERJACK_PLAID:
			body_width_scale = randf_range(1.15, 1.30)
			shirt_color = Color(0.85, 0.15, 0.15) if randf() < 0.6 else Color(0.15, 0.65, 0.25)
			pants_color = Color(0.18, 0.28, 0.45)
			shoe_color = Color(0.45, 0.25, 0.10)
			has_beard = true
			has_beanie = randf() < 0.65
			hat_color = Color(0.15, 0.15, 0.18)

		Archetype.FOREST_HIKER_BACKPACK:
			shirt_color = Color(0.75, 0.55, 0.25)
			pants_color = Color(0.35, 0.40, 0.30)
			shoe_color = Color(0.30, 0.20, 0.12)
			has_backpack = true
			has_sleeping_bag = true
			accessory_color = Color(0.85, 0.35, 0.10)
			has_cap = true
			hat_color = Color(0.25, 0.35, 0.25)

		Archetype.FOREST_PARK_RANGER:
			shirt_color = Color(0.35, 0.48, 0.30)
			pants_color = Color(0.28, 0.38, 0.24)
			shoe_color = Color(0.20, 0.15, 0.10)
			has_ranger_hat = true
			hat_color = Color(0.40, 0.32, 0.20)
			has_badge = true

		Archetype.FOREST_CABIN_HUNTER:
			shirt_color = Color(0.45, 0.35, 0.25)
			pants_color = Color(0.20, 0.25, 0.20)
			shoe_color = Color(0.25, 0.18, 0.12)
			has_vest = true
			accessory_color = Color(0.85, 0.45, 0.05)
			has_cap = true
			hat_color = Color(0.85, 0.45, 0.05)

		# === 5. BAIRRO PRAIANO (BEACH COASTAL) ===
		Archetype.BEACH_HAWAIIAN_FLORAL:
			var hawaiian_colors := [Color("e17055"), Color("00cec9"), Color("fdcb6e"), Color("e84393"), Color("6c5ce7")]
			shirt_color = hawaiian_colors[randi() % hawaiian_colors.size()]
			pants_color = Color(0.92, 0.90, 0.82)
			shoe_color = Color(0.70, 0.55, 0.35)
			has_sunglasses = true
			has_visor = randf() < 0.35

		Archetype.BEACH_SURFER_SUMMER:
			shirt_color = Color(0.10, 0.70, 0.85)
			pants_color = Color(0.95, 0.45, 0.10)
			shoe_color = Color(0.85, 0.70, 0.50)
			has_surfboard = true
			has_sunglasses = true

		Archetype.BEACH_FITNESS_RUNNER:
			shirt_color = Color(0.95, 0.95, 0.15) if randf() < 0.5 else Color(0.95, 0.20, 0.60)
			pants_color = Color(0.12, 0.12, 0.15)
			shoe_color = Color(0.20, 0.85, 0.95)
			has_visor = true
			hat_color = Color(0.95, 0.95, 0.95)
			has_sunglasses = true

		_: # BEACH_CASUAL_RESORT
			shirt_color = Color(0.95, 0.95, 0.98)
			pants_color = Color(0.35, 0.55, 0.75)
			shoe_color = Color(0.80, 0.70, 0.50)
			has_sunglasses = true
			has_cap = randf() < 0.40

func _build_3d_viewport() -> void:
	body_type = (posmod(body_type_override, BODY_PROPORTIONS.size()) if body_type_override >= 0 else randi_range(0, BODY_PROPORTIONS.size() - 1)) as BodyType
	body_height_scale = BODY_PROPORTIONS[body_type].x
	var presentation_budget := get_node_or_null("/root/PresentationBudget")
	if ambient_low_lod and presentation_budget != null and presentation_budget.has_method("acquire_ambient_atlas"):
		_build_ambient_atlas_presentation(presentation_budget)
		return
	var use_authored_atlas := ambient_presentation_atlas and presentation_budget != null and presentation_budget.has_method("acquire_ambient_atlas")
	var stage_ticket: Dictionary = {}
	var stage_started_usec := 0
	if use_authored_atlas:
		stage_ticket = await _reserve_presentation_stage(&"setup")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	var character_world: World3D = null
	if use_authored_atlas:
		var allocation: Dictionary = presentation_budget.acquire_ambient_atlas(self)
		viewport = allocation["viewport"] as SubViewport
		character_world = allocation["world"] as World3D
		_presentation_atlas_active = true
		_presentation_atlas_region = allocation["region"] as Rect2
		_presentation_world_origin = allocation["origin"] as Vector3
		set_meta("presentation_world_origin", _presentation_world_origin)
		model_root = Node3D.new()
		model_root.position = _presentation_world_origin
		model_root.scale = Vector3(1.0, body_height_scale, 1.0)
		viewport.add_child(model_root)
	else:
		viewport = SubViewport.new()
		viewport.size = PRESENTATION_SIZE
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		viewport.own_world_3d = true
		add_child(viewport)
		_presentation_world_origin = Vector3.ZERO
		var cam := Camera3D.new()
		cam.position = Vector3(0.0, 3.2, 1.4)
		cam.fov = 36.0
		viewport.add_child(cam)
		cam.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
		light.light_energy = 1.35
		viewport.add_child(light)
		var env := WorldEnvironment.new()
		var env_res := Environment.new()
		env_res.background_mode = Environment.BG_COLOR
		env_res.background_color = Color(0, 0, 0, 0)
		env_res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env_res.ambient_light_color = Color(0.70, 0.72, 0.82)
		env.environment = env_res
		viewport.add_child(env)
		model_root = Node3D.new()
		model_root.position = Vector3.ZERO
		model_root.scale = Vector3(1.0, body_height_scale, 1.0)
		viewport.add_child(model_root)
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"shadow")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	# A rig is intentionally assembled in safe frame-sized phases. The fallback
	# silhouette remains visible while the detailed presentation is built, so a
	# newly materialized citizen cannot monopolize the gameplay frame.
	# Sombra Projetada 3D nos pés
	var shadow_mat: StandardMaterial3D = StandardMaterial3D.new()
	if ambient_low_lod and character_world != null and presentation_budget != null:
		shadow_mat = presentation_budget.acquire_character_shadow(character_world)
	else:
		shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shadow_mat.albedo_color = Color(0.02, 0.02, 0.04, 0.50)
		shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"shadow_mesh")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()

	var shadow_mesh := MeshInstance3D.new()
	var cyl_shadow := _cached_cylinder(0.28 * body_width_scale, 0.28 * body_width_scale, 0.01)
	shadow_mesh.mesh = cyl_shadow
	shadow_mesh.material_override = shadow_mat
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	shadow_mesh.name = "GroundShadow"
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if use_authored_atlas:
		model_root.add_child(shadow_mesh)
	else:
		viewport.add_child(shadow_mesh)
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"shadow_soften")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	preload("res://systems/ContactShadow.gd").soften(shadow_mesh, Vector2(0.86 * body_width_scale, 0.72))
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"materials")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()

	# Materiais 3D
	var mat_shirt: Material = _make_mat(shirt_color, 0.6)
	var mat_pants: Material = _make_mat(pants_color, 0.7)
	var mat_skin: Material = _make_mat(skin_color, 0.5)
	var mat_hair: Material = _make_mat(hair_color, 0.8)
	var mat_shoe: Material = _make_mat(shoe_color, 0.5)
	if ambient_low_lod and character_world != null and presentation_budget != null:
		mat_shirt = presentation_budget.acquire_character_material(character_world, shirt_color, 0.6)
		mat_pants = presentation_budget.acquire_character_material(character_world, pants_color, 0.7)
		mat_skin = presentation_budget.acquire_character_material(character_world, skin_color, 0.5)
		mat_hair = presentation_budget.acquire_character_material(character_world, hair_color, 0.8)
		mat_shoe = presentation_budget.acquire_character_material(character_world, shoe_color, 0.5)
	if ambient_low_lod:
		_build_ambient_low_lod_rig(mat_shirt, mat_pants, mat_skin, mat_hair, mat_shoe)
		_finish_presentation_build(false)
		return
	var mat_hat := _make_mat(hat_color, 0.5)
	var mat_acc := _make_mat(accessory_color, 0.4)
	var mat_glasses := _make_mat(Color(0.05, 0.05, 0.06), 0.1)
	var mat_white := _make_mat(Color(0.96, 0.96, 0.98), 0.5)
	var mat_gold := _make_mat(Color(0.95, 0.80, 0.15), 0.2)
	var mat_fur := _make_mat(Color(0.85, 0.85, 0.88), 0.9)
	var mat_leather := _make_mat(Color(0.35, 0.20, 0.10), 0.4)
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"torso")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	
	# 1. TORSO 3D
	torso_node = Node3D.new()
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"torso_mesh_prepare")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()

	var torso_mesh := MeshInstance3D.new()
	torso_mesh.name = "BodyShell"
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"torso_mesh_resource")
		if stage_ticket.is_empty():
			torso_mesh.free()
			return
		stage_started_usec = Time.get_ticks_usec()
	var cap_torso := _cached_capsule(0.17, 0.48)
	torso_mesh.mesh = cap_torso
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"torso_mesh_material")
		if stage_ticket.is_empty():
			torso_mesh.free()
			return
		stage_started_usec = Time.get_ticks_usec()
	torso_mesh.material_override = mat_shirt
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"torso_mesh_attach")
		if stage_ticket.is_empty():
			torso_mesh.free()
			return
		stage_started_usec = Time.get_ticks_usec()
	torso_node.add_child(torso_mesh)
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"torso_accessories")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	
	if has_tie:
		var shirt_inner := MeshInstance3D.new()
		var box_s := _cached_box(Vector3(0.12, 0.26, 0.03))
		shirt_inner.mesh = box_s
		shirt_inner.material_override = mat_white
		shirt_inner.position = Vector3(0.0, 0.08, -0.16)
		torso_node.add_child(shirt_inner)
		
		var tie := MeshInstance3D.new()
		var box_t := _cached_box(Vector3(0.04, 0.22, 0.035))
		tie.mesh = box_t
		tie.material_override = _make_mat(Color(0.80, 0.15, 0.15), 0.3)
		tie.position = Vector3(0.0, 0.06, -0.175)
		torso_node.add_child(tie)
		
	if has_vest:
		var vest := MeshInstance3D.new()
		var box_v := _cached_box(Vector3(0.36, 0.38, 0.36))
		vest.mesh = box_v
		vest.material_override = mat_acc if accessory_color != Color.BLACK else mat_leather
		vest.position = Vector3(0.0, 0.02, 0.0)
		torso_node.add_child(vest)

	if has_backpack:
		var pack := MeshInstance3D.new()
		var box_pk := _cached_box(Vector3(0.24, 0.34, 0.16))
		pack.mesh = box_pk
		pack.material_override = mat_acc
		pack.position = Vector3(0.0, 0.05, 0.19)
		torso_node.add_child(pack)

		# Isolante TÃ©rmico / Saco de Dormir Enrolado no Topo da Mochila
		if has_sleeping_bag:
			var mat_roll := MeshInstance3D.new()
			var cyl_mr := _cached_cylinder(0.06, 0.06, 0.28)
			mat_roll.mesh = cyl_mr
			mat_roll.material_override = _make_mat(Color("27ae60"), 0.5)
			mat_roll.rotation_degrees = Vector3(0, 0, 90)
			mat_roll.position = Vector3(0.0, 0.24, 0.19)
			torso_node.add_child(mat_roll)

	if has_scarf:
		var scarf := MeshInstance3D.new()
		var torus_sc := _cached_torus(0.14, 0.19)
		scarf.mesh = torus_sc
		scarf.material_override = mat_acc
		scarf.position = Vector3(0.0, 0.25, 0.0)
		torso_node.add_child(scarf)

	if has_bandana:
		var band := MeshInstance3D.new()
		var box_bd := _cached_box(Vector3(0.18, 0.12, 0.04))
		band.mesh = box_bd
		band.material_override = mat_acc
		band.position = Vector3(0.0, 0.19, -0.15)
		torso_node.add_child(band)

	if has_badge:
		var badge := MeshInstance3D.new()
		var box_b := _cached_box(Vector3(0.045, 0.055, 0.03))
		badge.mesh = box_b
		badge.material_override = mat_gold
		badge.position = Vector3(-0.08, 0.10, -0.165)
		torso_node.add_child(badge)
		
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"head")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	# 2. CABEÃ‡A 3D
	head_node = Node3D.new()
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)
	
	var head_mesh := MeshInstance3D.new()
	var sphere_head := _cached_sphere(0.17, 0.34)
	head_mesh.mesh = sphere_head
	head_mesh.material_override = mat_skin
	head_node.add_child(head_mesh)

	var hair_mesh := MeshInstance3D.new()
	hair_mesh.name = "BaseHair"
	var sphere_hair := _cached_sphere(0.175, 0.28)
	hair_mesh.mesh = sphere_hair
	hair_mesh.material_override = mat_hair
	hair_mesh.position = Vector3(0.0, 0.05, 0.02)
	head_node.add_child(hair_mesh)

	# Barba Cheia 3D (Lenhadores e Motoqueiros)
	if has_beard:
		var beard := MeshInstance3D.new()
		var box_brd := _cached_box(Vector3(0.19, 0.14, 0.16))
		beard.mesh = box_brd
		beard.material_override = mat_hair
		beard.position = Vector3(0.0, -0.09, -0.08)
		head_node.add_child(beard)

	if has_sunglasses:
		var glasses := MeshInstance3D.new()
		var box_gl := _cached_box(Vector3(0.24, 0.05, 0.04))
		glasses.mesh = box_gl
		glasses.material_override = mat_glasses
		glasses.position = Vector3(0.0, 0.03, -0.165)
		head_node.add_child(glasses)

	# Coberturas de CabeÃ§a
	if has_cowboy_hat:
		var crown := MeshInstance3D.new()
		var cyl_cr := _cached_cylinder(0.15, 0.18, 0.14)
		crown.mesh = cyl_cr
		crown.material_override = mat_hat
		crown.position = Vector3(0.0, 0.14, 0.0)
		head_node.add_child(crown)

		var brim_c := MeshInstance3D.new()
		var cyl_br := _cached_cylinder(0.30, 0.30, 0.02)
		brim_c.mesh = cyl_br
		brim_c.material_override = mat_hat
		brim_c.position = Vector3(0.0, 0.08, 0.0)
		head_node.add_child(brim_c)

	elif has_beanie:
		var beanie := MeshInstance3D.new()
		var sph_bn := _cached_sphere(0.19, 0.26)
		beanie.mesh = sph_bn
		beanie.material_override = mat_hat
		beanie.position = Vector3(0.0, 0.08, 0.0)
		head_node.add_child(beanie)

	elif has_fur_hood:
		var hood := MeshInstance3D.new()
		var sph_hd := _cached_sphere(0.22, 0.30)
		hood.mesh = sph_hd
		hood.material_override = mat_shirt
		hood.position = Vector3(0.0, 0.06, 0.04)
		head_node.add_child(hood)

		var fur_rim := MeshInstance3D.new()
		var torus_fr := _cached_torus(0.165, 0.205)
		fur_rim.mesh = torus_fr
		fur_rim.material_override = mat_fur
		fur_rim.rotation_degrees = Vector3(90, 0, 0)
		fur_rim.position = Vector3(0.0, 0.06, -0.06)
		head_node.add_child(fur_rim)

	elif has_ranger_hat:
		var ranger_cr := MeshInstance3D.new()
		var cyl_rg := _cached_cylinder(0.14, 0.17, 0.12)
		ranger_cr.mesh = cyl_rg
		ranger_cr.material_override = mat_hat
		ranger_cr.position = Vector3(0.0, 0.13, 0.0)
		head_node.add_child(ranger_cr)

		var ranger_br := MeshInstance3D.new()
		var cyl_rb := _cached_cylinder(0.28, 0.28, 0.02)
		ranger_br.mesh = cyl_rb
		ranger_br.material_override = mat_hat
		ranger_br.position = Vector3(0.0, 0.08, 0.0)
		head_node.add_child(ranger_br)

	elif has_cap:
		var cap := MeshInstance3D.new()
		var sph_cp := _cached_sphere(0.18, 0.24)
		cap.mesh = sph_cp
		cap.material_override = mat_hat if hat_color != Color.BLACK else mat_shirt
		cap.position = Vector3(0.0, 0.08, 0.0)
		head_node.add_child(cap)

		var cap_visor := MeshInstance3D.new()
		var box_visor := _cached_box(Vector3(0.24, 0.025, 0.16))
		cap_visor.mesh = box_visor
		cap_visor.material_override = mat_hat if hat_color != Color.BLACK else mat_shirt
		cap_visor.position = Vector3(0.0, 0.07, -0.18)
		cap_visor.rotation_degrees = Vector3(12, 0, 0)
		head_node.add_child(cap_visor)

	elif has_earmuffs:
		var muff_l := MeshInstance3D.new()
		var sph_m1 := _cached_sphere(0.07, 0.12)
		muff_l.mesh = sph_m1
		muff_l.material_override = mat_fur
		muff_l.position = Vector3(-0.18, 0.03, 0.0)
		head_node.add_child(muff_l)

		var muff_r := MeshInstance3D.new()
		var sph_m2 := _cached_sphere(0.07, 0.12)
		muff_r.mesh = sph_m2
		muff_r.material_override = mat_fur
		muff_r.position = Vector3(0.18, 0.03, 0.0)
		head_node.add_child(muff_r)

	elif has_visor:
		var visor_band := MeshInstance3D.new()
		var box_vb := _cached_box(Vector3(0.35, 0.04, 0.35))
		visor_band.mesh = box_vb
		visor_band.material_override = mat_hat
		visor_band.position = Vector3(0.0, 0.06, 0.0)
		head_node.add_child(visor_band)

		var visor_br := MeshInstance3D.new()
		var box_vr := _cached_box(Vector3(0.24, 0.02, 0.15))
		visor_br.mesh = box_vr
		visor_br.material_override = mat_hat
		visor_br.position = Vector3(0.0, 0.05, -0.18)
		visor_br.rotation_degrees = Vector3(12, 0, 0)
		head_node.add_child(visor_br)
		
	elif has_headband:
		var headband := MeshInstance3D.new()
		var box_hb := _cached_box(Vector3(0.36, 0.04, 0.36))
		headband.mesh = box_hb
		headband.material_override = mat_acc
		headband.position = Vector3(0.0, 0.07, 0.0)
		head_node.add_child(headband)
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"arms")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	# 3. BRAÃ‡OS 3D
	left_upper_arm = Node3D.new()
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_shirt, Vector3(0, -0.11, 0)))
	
	left_lower_arm = Node3D.new()
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	var mat_forearm_l: Material = mat_skin if archetype in [Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER, Archetype.BEACH_FITNESS_RUNNER, Archetype.CITY_JOGGER] else mat_shirt
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_forearm_l, Vector3(0, -0.09, 0)))
	left_lower_arm.add_child(_create_hand(mat_skin, Vector3(0, -0.19, 0)))
	left_lower_arm.add_child(_create_joint_cap(0.046, mat_forearm_l, Vector3.ZERO))

	# Detalhe: CÃ¢mera TurÃ­stica no PescoÃ§o
	if has_camera:
		var cam_body := MeshInstance3D.new()
		var box_cam := _cached_box(Vector3(0.12, 0.08, 0.06))
		cam_body.mesh = box_cam
		cam_body.material_override = _make_mat(Color("2d3436"), 0.3)
		cam_body.position = Vector3(0.0, 0.02, -0.18)
		torso_node.add_child(cam_body)
		
		var cam_lens := MeshInstance3D.new()
		var cyl_lens := _cached_cylinder(0.032, 0.032, 0.05)
		cam_lens.mesh = cyl_lens
		cam_lens.material_override = _make_mat(Color("74b9ff"), 0.2)
		cam_lens.rotation_degrees = Vector3(90, 0, 0)
		cam_lens.position = Vector3(0.0, 0.02, -0.21)
		torso_node.add_child(cam_lens)

	# Detalhe: Copinho de CafÃ© na MÃ£o Esquerda
	if has_coffee_cup:
		var cup := MeshInstance3D.new()
		var cyl_cup := _cached_cylinder(0.035, 0.025, 0.09)
		cup.mesh = cyl_cup
		cup.material_override = mat_white
		cup.position = Vector3(0.0, -0.18, -0.05)
		left_lower_arm.add_child(cup)

	# Detalhe: Prancha de Surf 3D no BraÃ§o Esquerdo
	if has_surfboard:
		var board := MeshInstance3D.new()
		var cap_bd := _cached_capsule(0.08, 0.75)
		board.mesh = cap_bd
		board.material_override = _make_mat(Color("fdcb6e"), 0.2)
		board.rotation_degrees = Vector3(25, 0, 0)
		board.position = Vector3(-0.12, -0.10, 0.0)
		left_lower_arm.add_child(board)
	
	right_upper_arm = Node3D.new()
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_shirt, Vector3(0, -0.11, 0)))
	
	right_lower_arm = Node3D.new()
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	var mat_forearm_r: Material = mat_skin if archetype in [Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER, Archetype.BEACH_FITNESS_RUNNER, Archetype.CITY_JOGGER] else mat_shirt
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_forearm_r, Vector3(0, -0.09, 0)))
	right_lower_arm.add_child(_create_hand(mat_skin, Vector3(0, -0.19, 0)))
	right_lower_arm.add_child(_create_joint_cap(0.046, mat_forearm_r, Vector3.ZERO))

	if has_briefcase:
		var briefcase := MeshInstance3D.new()
		var box_bc := _cached_box(Vector3(0.06, 0.22, 0.26))
		briefcase.mesh = box_bc
		briefcase.material_override = _make_mat(Color(0.25, 0.15, 0.08), 0.3)
		briefcase.position = Vector3(0.06, -0.22, 0.0)
		right_lower_arm.add_child(briefcase)

	# Detalhe: Bengala de Madeira do Idoso
	if has_walking_stick:
		var cane := MeshInstance3D.new()
		var cyl_c := _cached_cylinder(0.015, 0.012, 0.55)
		cane.mesh = cyl_c
		cane.material_override = _make_mat(Color("5c381e"), 0.5)
		cane.position = Vector3(0.06, -0.24, -0.08)
		right_lower_arm.add_child(cane)

	# Detalhe: Pistola 3D na mÃ£o do Gangster
	if has_handgun:
		muzzle_flash_3d = MeshInstance3D.new()
		var sph_mf := _cached_sphere(0.06, 0.12)
		muzzle_flash_3d.mesh = sph_mf
		var mat_fl := StandardMaterial3D.new()
		mat_fl.albedo_color = Color(1.0, 0.85, 0.2)
		mat_fl.emission_enabled = true
		mat_fl.emission = Color(1.0, 0.6, 0.1)
		mat_fl.emission_energy_multiplier = 4.0
		mat_fl.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		muzzle_flash_3d.material_override = mat_fl
		muzzle_flash_3d.position = Vector3(0.0, -0.18, -0.18)
		muzzle_flash_3d.visible = false
		right_lower_arm.add_child(muzzle_flash_3d)
	
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"legs")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
	# 4. PERNAS 3D
	left_upper_leg = Node3D.new()
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))
	
	left_lower_leg = Node3D.new()
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	var mat_shin_l: Material = mat_skin if archetype in [Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER, Archetype.BEACH_FITNESS_RUNNER] else mat_pants
	left_lower_leg.add_child(_create_limb(0.058, 0.26, mat_shin_l, Vector3(0, -0.13, 0)))
	left_lower_leg.add_child(_create_shoe(mat_shoe, Vector3(0, -0.26, -0.02)))
	left_lower_leg.add_child(_create_joint_cap(0.062, mat_shin_l, Vector3.ZERO))
	
	right_upper_leg = Node3D.new()
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0)))
	
	right_lower_leg = Node3D.new()
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	var mat_shin_r: Material = mat_skin if archetype in [Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER, Archetype.BEACH_FITNESS_RUNNER] else mat_pants
	right_lower_leg.add_child(_create_limb(0.058, 0.26, mat_shin_r, Vector3(0, -0.13, 0)))
	right_lower_leg.add_child(_create_shoe(mat_shoe, Vector3(0, -0.26, -0.02)))
	right_lower_leg.add_child(_create_joint_cap(0.062, mat_shin_r, Vector3.ZERO))
	
	_apply_body_proportions()
	if use_authored_atlas:
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		var sculpt = preload("res://characters/pedestrians/CitizenSculpt.gd")
		var sculpt_context: Dictionary = sculpt.prepare(self)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_face_shell_prepare")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		var face_shell: MeshInstance3D = sculpt.create_face_shell(self, sculpt_context)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_face_shell_attach")
		if stage_ticket.is_empty():
			face_shell.free()
			return
		stage_started_usec = Time.get_ticks_usec()
		head_node.add_child(face_shell)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_nose")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_nose(self, sculpt_context)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_face_details")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_face_details(self, sculpt_context)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_beard_neck")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_beard_and_neck(self, sculpt_context)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_hair_crown")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_hair_crown(self)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_hair_sides")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_hair_sides(self)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_hair_back")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_hair_back_base(self)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		for hair_begin in [0, 6]:
			stage_ticket = await _reserve_presentation_stage(StringName("sculpt_hair_extra_%d" % hair_begin))
			if stage_ticket.is_empty():
				return
			stage_started_usec = Time.get_ticks_usec()
			sculpt.build_hair_extras(self, hair_begin, hair_begin + 6)
			_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_torso")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_tailored_torso(self, sculpt_context)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"sculpt_waist")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.build_waist(self)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
		for sculpt_side in 2:
			stage_ticket = await _reserve_presentation_stage(StringName("sculpt_side_%d" % sculpt_side))
			if stage_ticket.is_empty():
				return
			stage_started_usec = Time.get_ticks_usec()
			sculpt.build_side(self, sculpt_context, sculpt_side)
			_complete_presentation_stage(stage_ticket, stage_started_usec)
		stage_ticket = await _reserve_presentation_stage(&"finish")
		if stage_ticket.is_empty():
			return
		stage_started_usec = Time.get_ticks_usec()
		sculpt.finish(self, sculpt_context)
		_finish_presentation_build(false)
		_complete_presentation_stage(stage_ticket, stage_started_usec)
	else:
		_finish_presentation_build(true)

func _build_ambient_atlas_presentation(presentation_budget: Node) -> void:
	var allocation: Dictionary = presentation_budget.acquire_ambient_atlas(self)
	viewport = allocation["viewport"] as SubViewport
	_presentation_atlas_active = true
	_presentation_atlas_region = allocation["region"] as Rect2
	_presentation_world_origin = allocation["origin"] as Vector3
	set_meta("presentation_world_origin", _presentation_world_origin)
	model_root = Node3D.new()
	model_root.position = _presentation_world_origin
	model_root.scale = Vector3(1.0, body_height_scale, 1.0)
	viewport.add_child(model_root)
	var character_world: World3D = allocation["world"] as World3D
	var shadow_mat: StandardMaterial3D = presentation_budget.acquire_character_shadow(character_world)
	var shadow_mesh := MeshInstance3D.new()
	shadow_mesh.mesh = _cached_cylinder(0.28 * body_width_scale, 0.28 * body_width_scale, 0.01)
	shadow_mesh.material_override = shadow_mat
	# Keep the shadow under the actor root so atlas compaction moves the complete
	# 3D presentation atomically between render tiles.
	shadow_mesh.position = Vector3(0.0, 0.01, 0.0)
	shadow_mesh.name = "GroundShadow"
	shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model_root.add_child(shadow_mesh)
	preload("res://systems/ContactShadow.gd").soften(shadow_mesh, Vector2(0.86 * body_width_scale, 0.72))
	var mat_shirt: Material = presentation_budget.acquire_character_material(character_world, shirt_color, 0.6)
	var mat_pants: Material = presentation_budget.acquire_character_material(character_world, pants_color, 0.7)
	var mat_skin: Material = presentation_budget.acquire_character_material(character_world, skin_color, 0.5)
	var mat_hair: Material = presentation_budget.acquire_character_material(character_world, hair_color, 0.8)
	var mat_shoe: Material = presentation_budget.acquire_character_material(character_world, shoe_color, 0.5)
	_build_ambient_low_lod_rig(mat_shirt, mat_pants, mat_skin, mat_hair, mat_shoe)
	_finish_presentation_build(false)
	_viewport_cull_timer = 0.0
	_update_viewport_render_state(0.0)

func _apply_ambient_atlas_slot(_render_slot: int, origin: Vector3, region: Rect2) -> void:
	_presentation_world_origin = origin
	_presentation_atlas_region = region
	set_meta("presentation_world_origin", origin)
	if is_instance_valid(model_root): model_root.position = origin
	if is_instance_valid(sprite_3d_display): sprite_3d_display.region_rect = region

func _finish_presentation_build(include_details := true) -> void:
	if include_details:
		preload("res://characters/pedestrians/CitizenDetails.gd").dress(self, int(archetype))
	if is_gangster or (has_handgun and civilian_reaction == CivilianReaction.ARMED):
		preload("res://characters/pedestrians/NPCCombatRig.gd").attach(self, "pistol")
	elif civilian_reaction == CivilianReaction.FIGHT:
		preload("res://characters/pedestrians/NPCCombatRig.gd").attach(self, "fists")
	# ExibiÃ§Ã£o 2D
	sprite_3d_display = Sprite2D.new()
	sprite_3d_display.texture = viewport.get_texture()
	if _presentation_atlas_active:
		sprite_3d_display.region_enabled = true
		sprite_3d_display.region_rect = _presentation_atlas_region
	sprite_3d_display.scale = Vector2.ONE * PRESENTATION_DISPLAY_SCALE
	add_child(sprite_3d_display)
	# Deferred citizens keep walking before PresentationBudget builds the rig.
	# Install the gait only after every articulated limb exists.
	var built_gait := preload("res://characters/pedestrians/CitizenGait.gd").new()
	if built_gait.configure(self, int(get_meta("appearance_variant", 0))):
		gait = built_gait

func _build_ambient_low_lod_rig(mat_shirt: Material, mat_pants: Material, mat_skin: Material, mat_hair: Material, mat_shoe: Material) -> void:
	if is_instance_valid(_ambient_rig_template):
		for child in _ambient_rig_template.get_children():
			model_root.add_child(child.duplicate())
		_bind_ambient_rig_references()
		_recolor_ambient_rig({"shirt": mat_shirt, "pants": mat_pants, "skin": mat_skin, "hair": mat_hair, "shoe": mat_shoe})
		_apply_body_proportions()
		return
	torso_node = Node3D.new()
	torso_node.name = "AmbientTorso"
	torso_node.position = Vector3(0.0, 0.85, 0.0)
	model_root.add_child(torso_node)
	var torso := MeshInstance3D.new()
	torso.set_meta("ambient_material_role", "shirt")
	torso.mesh = _cached_capsule(0.17, 0.48)
	torso.material_override = mat_shirt
	torso_node.add_child(torso)
	head_node = Node3D.new()
	head_node.name = "AmbientHead"
	head_node.position = Vector3(0.0, 1.25, 0.0)
	model_root.add_child(head_node)
	var head := MeshInstance3D.new()
	head.set_meta("ambient_material_role", "skin")
	head.mesh = _cached_sphere(0.17, 0.34)
	head.material_override = mat_skin
	head_node.add_child(head)
	var hair := MeshInstance3D.new()
	hair.set_meta("ambient_material_role", "hair")
	hair.mesh = _cached_sphere(0.175, 0.28)
	hair.material_override = mat_hair
	hair.position = Vector3(0.0, 0.05, 0.02)
	head_node.add_child(hair)
	left_upper_arm = Node3D.new()
	left_upper_arm.name = "AmbientLeftUpperArm"
	left_upper_arm.position = Vector3(-0.24, 1.05, 0.0)
	model_root.add_child(left_upper_arm)
	left_upper_arm.add_child(_create_limb(0.050, 0.22, mat_shirt, Vector3(0, -0.11, 0), "shirt"))
	left_lower_arm = Node3D.new()
	left_lower_arm.name = "AmbientLeftLowerArm"
	left_lower_arm.position = Vector3(0, -0.22, 0)
	left_upper_arm.add_child(left_lower_arm)
	left_lower_arm.add_child(_create_limb(0.042, 0.18, mat_shirt, Vector3(0, -0.09, 0), "shirt"))
	left_lower_arm.add_child(_create_hand(mat_skin, Vector3(0, -0.19, 0), "skin"))
	right_upper_arm = Node3D.new()
	right_upper_arm.name = "AmbientRightUpperArm"
	right_upper_arm.position = Vector3(0.24, 1.05, 0.0)
	model_root.add_child(right_upper_arm)
	right_upper_arm.add_child(_create_limb(0.050, 0.22, mat_shirt, Vector3(0, -0.11, 0), "shirt"))
	right_lower_arm = Node3D.new()
	right_lower_arm.name = "AmbientRightLowerArm"
	right_lower_arm.position = Vector3(0, -0.22, 0)
	right_upper_arm.add_child(right_lower_arm)
	right_lower_arm.add_child(_create_limb(0.042, 0.18, mat_shirt, Vector3(0, -0.09, 0), "shirt"))
	right_lower_arm.add_child(_create_hand(mat_skin, Vector3(0, -0.19, 0), "skin"))
	left_upper_leg = Node3D.new()
	left_upper_leg.name = "AmbientLeftUpperLeg"
	left_upper_leg.position = Vector3(-0.11, 0.65, 0.0)
	model_root.add_child(left_upper_leg)
	left_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0), "pants"))
	left_lower_leg = Node3D.new()
	left_lower_leg.name = "AmbientLeftLowerLeg"
	left_lower_leg.position = Vector3(0, -0.28, 0)
	left_upper_leg.add_child(left_lower_leg)
	left_lower_leg.add_child(_create_limb(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0), "pants"))
	left_lower_leg.add_child(_create_shoe(mat_shoe, Vector3(0, -0.26, -0.02), "shoe"))
	right_upper_leg = Node3D.new()
	right_upper_leg.name = "AmbientRightUpperLeg"
	right_upper_leg.position = Vector3(0.11, 0.65, 0.0)
	model_root.add_child(right_upper_leg)
	right_upper_leg.add_child(_create_limb(0.068, 0.28, mat_pants, Vector3(0, -0.14, 0), "pants"))
	right_lower_leg = Node3D.new()
	right_lower_leg.name = "AmbientRightLowerLeg"
	right_lower_leg.position = Vector3(0, -0.28, 0)
	right_upper_leg.add_child(right_lower_leg)
	right_lower_leg.add_child(_create_limb(0.058, 0.26, mat_pants, Vector3(0, -0.13, 0), "pants"))
	right_lower_leg.add_child(_create_shoe(mat_shoe, Vector3(0, -0.26, -0.02), "shoe"))
	_apply_body_proportions()
	_ambient_rig_template = Node3D.new()
	for child in model_root.get_children():
		if child.name == &"GroundShadow": continue
		_ambient_rig_template.add_child(child.duplicate())

func _bind_ambient_rig_references() -> void:
	torso_node = model_root.get_node("AmbientTorso")
	head_node = model_root.get_node("AmbientHead")
	left_upper_arm = model_root.get_node("AmbientLeftUpperArm")
	left_lower_arm = left_upper_arm.get_node("AmbientLeftLowerArm")
	right_upper_arm = model_root.get_node("AmbientRightUpperArm")
	right_lower_arm = right_upper_arm.get_node("AmbientRightLowerArm")
	left_upper_leg = model_root.get_node("AmbientLeftUpperLeg")
	left_lower_leg = left_upper_leg.get_node("AmbientLeftLowerLeg")
	right_upper_leg = model_root.get_node("AmbientRightUpperLeg")
	right_lower_leg = right_upper_leg.get_node("AmbientRightLowerLeg")

func _recolor_ambient_rig(materials: Dictionary) -> void:
	for mesh in model_root.find_children("*", "MeshInstance3D", true, false):
		var role := String(mesh.get_meta("ambient_material_role", ""))
		if materials.has(role): mesh.material_override = materials[role]

func _apply_body_proportions() -> void:
	var proportions: Vector4 = BODY_PROPORTIONS[body_type]
	# Preserve clothing bulk, without inflating the head and hands with the torso.
	var clothing_bulk := maxf(1.0, body_width_scale)
	torso_node.scale = Vector3(proportions.y * clothing_bulk, 1.0, proportions.z * clothing_bulk)
	# Match Dante's adult head proportions; hair and facial details inherit this
	# scale. The neck still overlaps the collar and the base of the head.
	const HEAD_SCALE := 0.72
	head_node.scale = Vector3(HEAD_SCALE, HEAD_SCALE / sqrt(body_height_scale), HEAD_SCALE)
	for arm in [left_upper_arm, right_upper_arm]:
		arm.position.x = signf(arm.position.x) * (0.17 * proportions.y * clothing_bulk + 0.07 * proportions.w)
		arm.scale = Vector3(proportions.w, 1.0, proportions.w)
	for leg in [left_upper_leg, right_upper_leg]:
		leg.position.x = signf(leg.position.x) * 0.11 * maxf(0.85, proportions.y * 0.85)
		leg.scale = Vector3(proportions.w, 1.0, proportions.w)

func _make_mat(col: Color, roughness: float) -> StandardMaterial3D:
	# Keep material ownership local to the actor/viewport, but avoid rebuilding
	# the same StandardMaterial shader state for every arriving resident.
	# Sharing the resource itself across World3D instances was rejected because
	# it produced black portraits and a renderer spike; duplicating a template
	# preserves isolation while making the CPU-side construction cheaper.
	var template_key := "%.3f" % roughness
	if not _presentation_material_templates.has(template_key):
		var template := StandardMaterial3D.new()
		template.roughness = roughness
		_presentation_material_templates[template_key] = template
	var mat := (_presentation_material_templates[template_key] as StandardMaterial3D).duplicate() as StandardMaterial3D
	mat.albedo_color = col
	mat.roughness = roughness
	if _presentation_shared_world:
		# The isolated presentation cameras share a World3D whose light can be
		# unavailable for one or more frames while a rig is materialized. Keep
		# fallback presentation materials visible instead of producing black
		# silhouettes; ambient LOD materials use the same policy in the budget.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 1.0
	return mat

static func _primitive_key(prefix: String, values: Array) -> String:
	return prefix + ":" + ":".join(values.map(func(value: Variant) -> String: return "%.5f" % float(value)))

static func _cached_box(size: Vector3) -> BoxMesh:
	var key := "box:%s:%s:%s" % [size.x, size.y, size.z]
	if not _primitive_mesh_cache.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_primitive_mesh_cache[key] = mesh
	return _primitive_mesh_cache[key] as BoxMesh

static func _cached_cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var key := _primitive_key("cylinder", [top_radius, bottom_radius, height])
	if not _primitive_mesh_cache.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = top_radius
		mesh.bottom_radius = bottom_radius
		mesh.height = height
		_primitive_mesh_cache[key] = mesh
	return _primitive_mesh_cache[key] as CylinderMesh

static func _cached_capsule(radius: float, height: float) -> CapsuleMesh:
	var key := _primitive_key("capsule", [radius, height])
	if not _primitive_mesh_cache.has(key):
		var mesh := CapsuleMesh.new()
		mesh.radius = radius
		mesh.height = height
		_primitive_mesh_cache[key] = mesh
	return _primitive_mesh_cache[key] as CapsuleMesh

static func _cached_sphere(radius: float, height: float) -> SphereMesh:
	var key := _primitive_key("sphere", [radius, height])
	if not _primitive_mesh_cache.has(key):
		var mesh := SphereMesh.new()
		mesh.radius = radius
		mesh.height = height
		_primitive_mesh_cache[key] = mesh
	return _primitive_mesh_cache[key] as SphereMesh

static func _cached_torus(inner_radius: float, outer_radius: float) -> TorusMesh:
	var key := _primitive_key("torus", [inner_radius, outer_radius])
	if not _primitive_mesh_cache.has(key):
		var mesh := TorusMesh.new()
		mesh.inner_radius = inner_radius
		mesh.outer_radius = outer_radius
		_primitive_mesh_cache[key] = mesh
	return _primitive_mesh_cache[key] as TorusMesh

func _create_limb(radius: float, height: float, mat: Material, offset: Vector3, role := "") -> MeshInstance3D:
	var m := MeshInstance3D.new()
	if not role.is_empty(): m.set_meta("ambient_material_role", role)
	var cyl := _cached_cylinder(radius, radius * 0.85, height)
	m.mesh = cyl
	m.material_override = mat
	m.position = offset
	return m

func _create_shoe(mat: Material, offset: Vector3, role := "") -> MeshInstance3D:
	var shoe := MeshInstance3D.new()
	if not role.is_empty(): shoe.set_meta("ambient_material_role", role)
	var box := _cached_box(Vector3(0.09, 0.065, 0.16))
	shoe.mesh = box
	shoe.material_override = mat
	shoe.position = offset
	return shoe

func _create_hand(mat: Material, offset: Vector3, role := "") -> MeshInstance3D:
	var hand := MeshInstance3D.new()
	if not role.is_empty(): hand.set_meta("ambient_material_role", role)
	var sph := _cached_sphere(0.044, 0.088)
	hand.mesh = sph
	hand.material_override = mat
	hand.position = offset
	return hand

func _create_joint_cap(radius: float, mat: Material, offset: Vector3) -> MeshInstance3D:
	var cap := MeshInstance3D.new()
	var sph := _cached_sphere(radius, radius * 2.0)
	cap.mesh = sph
	cap.material_override = mat
	cap.position = offset
	return cap

func _update_viewport_render_state(delta: float) -> void:
	if _presentation_atlas_active:
		_update_ambient_atlas_render_state(delta)
		return
	if viewport == null:
		return
	# A settled corpse is a static portrait. Submit the final pose once and then
	# stop its personal viewport; keeping every body at 30 Hz erased the atlas
	# saving during combat scenes.
	if (is_dead or is_incapacitated) and fall_presentation.started and not fall_presentation.active:
		if not _fallen_presentation_cached:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			_fallen_presentation_cached = true
		else:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var restore_canvas := get_canvas_transform()
	var restore_screen_position := restore_canvas * global_position
	var visible_now := is_visible_in_tree() and get_viewport().get_visible_rect().grow(VIEWPORT_CULL_MARGIN).has_point(restore_screen_position)
	if visible_now and _presentation_restore_pending:
		viewport.size = PRESENTATION_SIZE
		_presentation_restore_pending = false
	_viewport_cull_timer -= delta
	if _viewport_cull_timer <= 0.0:
		_viewport_cull_timer = VIEWPORT_CULL_CHECK_INTERVAL
		# Canvas transform includes camera smoothing, offset, rotation and zoom.
		var canvas := get_canvas_transform()
		var screen_position := canvas * global_position
		var projected_scale := maxf(canvas.x.length(), canvas.y.length())
		var should_render := screen_position.is_finite() and is_finite(projected_scale)
		should_render = should_render and get_viewport().get_visible_rect().grow(VIEWPORT_CULL_MARGIN).has_point(screen_position)
		if should_render and not _viewport_render_active:
			_viewport_frame_timer = fposmod(float(get_instance_id()) * 0.0073, _viewport_frame_interval)
		_viewport_render_active = should_render
		# Close-up rigs must follow the physics pose every tick, rather than
		# visibly stepping at 30Hz while the camera and body move at 60Hz.
		# Keep cheaper rendering for small representations in the overview.
		var projected_height := projected_scale * 36.0
		var render_hz := 30.0 if projected_height >= 36.0 else (12.0 if projected_height < 18.0 else 20.0)
		_viewport_frame_interval = 1.0 / render_hz
	if not _viewport_render_active or not is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	# Only render submission is throttled. Navigation, collision, attack timers,
	# run-over movement and the articulated pose below still run every tick.
	_viewport_frame_timer -= delta
	if _viewport_frame_timer <= 0.000001:
		# Retain the fractional remainder; resetting to a full interval loses
		# time and makes the cadence drift at non-divisor physics tick rates.
		# Submit at most once per tick even after a long stall.
		_viewport_frame_timer = fposmod(_viewport_frame_timer, _viewport_frame_interval)
		if _viewport_frame_timer <= 0.000001:
			_viewport_frame_timer = _viewport_frame_interval
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		viewport_render_requests += 1
	elif viewport.render_target_update_mode == SubViewport.UPDATE_WHEN_VISIBLE:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _update_ambient_atlas_render_state(delta: float) -> void:
	if viewport == null or not is_inside_tree(): return
	_viewport_cull_timer -= delta
	if _viewport_cull_timer > 0.0: return
	_viewport_cull_timer = ATLAS_VIEWPORT_CULL_CHECK_INTERVAL
	var canvas := get_canvas_transform()
	var screen_position := canvas * global_position
	var projected_scale := maxf(canvas.x.length(), canvas.y.length())
	var should_render := screen_position.is_finite() and is_finite(projected_scale) and is_visible_in_tree()
	should_render = should_render and not get_meta("proximity_sleeping", false)
	should_render = should_render and get_viewport().get_visible_rect().grow(VIEWPORT_CULL_MARGIN).has_point(screen_position)
	var world_distance := screen_position.distance_to(get_viewport().get_visible_rect().get_center()) / maxf(projected_scale, 0.001)
	var active_camera := get_viewport().get_camera_2d()
	if is_instance_valid(active_camera):
		world_distance = global_position.distance_to(active_camera.get_screen_center_position())
	var projected_height := projected_scale * 36.0
	var render_hz := 12.0
	if projected_height >= 48.0 or world_distance <= 360.0:
		render_hz = 30.0
	elif projected_height >= 24.0 or world_distance <= 760.0:
		render_hz = 20.0
	set_meta("presentation_world_distance", world_distance)
	set_meta("presentation_render_hz", render_hz if should_render else 0.0)
	_viewport_render_active = should_render
	if _atlas_visibility_reported and _atlas_reported_visible == should_render and is_equal_approx(_atlas_reported_hz, render_hz):
		return
	_atlas_visibility_reported = true
	_atlas_reported_visible = should_render
	_atlas_reported_hz = render_hz
	var budget := get_node_or_null("/root/PresentationBudget")
	if budget != null and budget.has_method("set_ambient_atlas_actor_visibility"):
		budget.set_ambient_atlas_actor_visibility(self, should_render, render_hz)

func _prepare_ambient_physics_step(delta: float) -> bool:
	_update_viewport_render_state(delta)
	if _ambient_requires_full_physics():
		_ambient_prepared_delta = delta
		return true
	_ambient_physics_elapsed += delta
	if _ambient_physics_elapsed < AMBIENT_PHYSICS_INTERVAL:
		return false
	_ambient_prepared_delta = _ambient_physics_elapsed
	_ambient_physics_elapsed = 0.0
	return true


func _physics_process(delta: float) -> void:
	if not _ambient_step_prepared and not _prepare_ambient_physics_step(delta):
		return
	delta = _ambient_prepared_delta
	if is_flying:
		fly_velocity = preload("res://guns/combat/VehiclePersonImpact.gd").move_falling_body(self, fly_velocity, delta)
		if fly_velocity.length() < 12.0: is_flying = false

	if is_dead or is_incapacitated:
		if not fall_presentation.started: _start_fall()
		fall_presentation.update(delta)
		return

	var actual_speed := velocity.length()
	if actual_speed > 1.0:
		walk_timer += delta * (actual_speed / maxf(1.0, base_walk_speed)) * stride_freq_mult
	_advance_gait(delta)
	behavior_timer += delta
	
	if is_scared:
		panic_timer -= delta
		if panic_timer <= 0.0:
			is_scared = false
			panic_recovery = randf_range(2.0, 4.0)
			_resume_after_panic()
	panic_recovery = maxf(0.0, panic_recovery - delta)
	
	# Velocidade adaptativa conforme o bioma
	# Velocidade adaptativa conforme o bioma e arquÃ©tipo
	var biome_speed_mult: float = 1.0
	match archetype:
		Archetype.WINTER_PARKA_FUR, Archetype.WINTER_BEANIE_SCARF, Archetype.WINTER_SKI_PUFFER:
			biome_speed_mult = 1.20 # Apressado para fugir do frio
		Archetype.DESERT_COWBOY_HAT, Archetype.DESERT_NOMAD_BANDANA, Archetype.DESERT_RANCHER_STRAW:
			biome_speed_mult = 0.88 # Cadenciado sob sol escaldante
		Archetype.BEACH_HAWAIIAN_FLORAL, Archetype.BEACH_SURFER_SUMMER:
			biome_speed_mult = 0.82 # Passo lento de praia
		Archetype.BEACH_FITNESS_RUNNER, Archetype.CITY_JOGGER:
			biome_speed_mult = 1.48 if ambient_running_enabled else 1.0

	# Active civilian defenders reuse the existing combat movement and weapons.
	if not is_gangster and civilian_reaction in [CivilianReaction.FIGHT, CivilianReaction.ARMED]:
		civilian_reaction_time -= delta
		if not is_instance_valid(combat_target) or civilian_reaction_time <= 0.0 or global_position.distance_to(combat_target.global_position) > (540.0 if civilian_reaction == CivilianReaction.ARMED else 270.0):
			_end_civilian_defense()
	# LÃ³gica de Combate e RetaliaÃ§Ã£o Armada (Gangsters de Bairro)
	if (is_gangster or civilian_reaction in [CivilianReaction.FIGHT, CivilianReaction.ARMED]) and is_instance_valid(combat_target):
		_ambient_navigation_target = Vector2.INF
		var target_dist = global_position.distance_to(combat_target.global_position)
		walk_dir = global_position.direction_to(combat_target.global_position)
		if not is_gangster:
			civilian_sight_timer -= delta
			if civilian_sight_timer <= 0.0:
				civilian_sight_timer = 0.25
				civilian_has_sight = _civilian_clear_shot(combat_target)
		
		# MantÃ©m postura de tiro com a mÃ£o erguida
		if right_upper_arm and right_lower_arm and civilian_reaction != CivilianReaction.FIGHT:
			right_upper_arm.rotation = Vector3(1.40, -0.05, 0.0)
			right_lower_arm.rotation = Vector3(0.05, 0.0, 0.0)
			
		# LÃ³gica de combate: distingue armas brancas e armas de fogo
		var rig := get_node_or_null("NPCCombatRig")
		var is_melee_npc := civilian_reaction == CivilianReaction.FIGHT and not is_gangster
		var melee_data: Dictionary = {}
		if rig:
			melee_data = WeaponCatalog.get_weapon(rig.active_weapon_id)
			is_melee_npc = melee_data.get("is_melee", false) == true
		elif is_melee_npc:
			melee_data = WeaponCatalog.get_weapon("fists")

		var attack_range: float = float(melee_data.get("melee_range", 52.0)) if is_melee_npc else 420.0
		gun_cooldown -= delta
		if gun_cooldown <= 0.0 and civilian_reaction_time <= 8.45 and target_dist <= attack_range and (is_gangster or civilian_has_sight):
			if is_melee_npc:
				gun_cooldown = float(melee_data.get("fire_interval", 0.65)) + randf_range(0.1, 0.25)
				_gangster_melee_attack(combat_target, melee_data)
			else:
				gun_cooldown = randf_range(0.8, 1.4)
				_gangster_shoot_target(combat_target.global_position)

		# Recua ou avanÃ§a taticamente de acordo com o tipo de combate
		var combat_speed = base_walk_speed * (1.35 if is_melee_npc else 1.2)
		var stand_dist := (attack_range * 0.65) if is_melee_npc else 180.0
		var dest = combat_target.global_position + (global_position - combat_target.global_position).normalized() * stand_dist
		if not is_gangster and not civilian_has_sight: dest = combat_target.global_position
		velocity = _navigate_towards(dest, combat_speed, delta)
	elif is_scared:
		_ambient_navigation_target = Vector2.INF
		if _update_civilian_call(delta):
			velocity = Vector2.ZERO
			if is_instance_valid(civilian_threat): walk_dir = global_position.direction_to(civilian_threat.global_position)
		else:
			velocity = danger_response.movement(self, delta, base_walk_speed * 2.0)
			walk_dir = velocity.normalized()
	elif _horn_escape_time > 0.0:
		_horn_escape_time = maxf(0.0, _horn_escape_time - delta)
		_ambient_navigation_target = Vector2.INF
		velocity = _navigate_towards(_horn_escape_target, base_walk_speed * 1.55, delta) if global_position.distance_to(_horn_escape_target) > 8.0 else Vector2.ZERO
		walk_dir = velocity.normalized()
	elif _ambient_walk_paused():
		_ambient_navigation_target = Vector2.INF
		velocity = Vector2.ZERO
	else:
		var cur_speed: float = base_walk_speed * biome_speed_mult * (0.75 if panic_recovery > 0.0 else 1.0)
		_update_walk_destination(delta)

		# The navigation helper performs route and social-neighbour decisions.
		# Its result is safe to retain for one intervening tick because the actual
		# body still calls move_and_slide every tick and therefore reacts to live
		# physical contact immediately. Accumulated delta keeps its timers exact.
		_ambient_navigation_elapsed += delta
		if _ambient_navigation_target != walk_target or _ambient_navigation_elapsed >= AMBIENT_NAVIGATION_INTERVAL:
			var navigation_delta := maxf(delta, _ambient_navigation_elapsed)
			_ambient_navigation_elapsed = 0.0
			_ambient_navigation_target = walk_target
			_ambient_navigation_velocity = _navigate_towards(walk_target, cur_speed, navigation_delta)
		velocity = _ambient_navigation_velocity
		walk_dir = velocity.normalized() if velocity.length_squared() > 1.0 else global_position.direction_to(walk_target)
	
	# The 3D rig orientation/walk-cycle pose below is pure presentation: nothing
	# else in the codebase reads model_root/limb rotations, and the collision
	# shape driving move_and_slide() below is rotation-independent. When the
	# character's SubViewport isn't being submitted for render (off-screen â€”
	# see _update_viewport_render_state above), skip recomputing and writing
	# it; walk_timer keeps advancing so the cycle resumes in-phase the moment
	# it's back in view. Navigation/collision/move_and_slide are unaffected.
	if _viewport_render_active:
		# RotaÃ§Ã£o 3D com orientaÃ§Ã£o precisa
		if model_root and walk_dir.length_squared() > 0.01:
			var target_angle_3d: float = -atan2(walk_dir.y, walk_dir.x) - PI * 0.5
			model_root.rotation.y = lerp_angle(model_root.rotation.y, target_angle_3d, 10.0 * delta)

		if gait != null:
			gait.apply_pose()

	preload("res://characters/pedestrians/PersonMotion.gd").move_actor(self)

func _ambient_requires_full_physics() -> bool:
	# Preserve the full cadence for anything that can change gameplay state
	# immediately. Ambient citizens remain physically present, but their
	# accumulated move_and_slide step runs at 30 Hz.
	if is_flying or is_dead or is_incapacitated or is_scared:
		return true
	if is_instance_valid(combat_target):
		return true
	if has_meta("medical_pending") or get_meta("simulation_keep_alive", false):
		return true
	if get_meta("interior_actor_presentation", false):
		return true
	return false


func _advance_gait(delta: float) -> void:
	# move_actor can skip move_and_slide when stopped; get_position_delta would
	# then retain an old step indefinitely. Measure actual position ourselves.
	var displacement := global_position - _gait_last_position if _gait_position_valid else Vector2.ZERO
	_gait_last_position=global_position
	_gait_position_valid=true
	if gait == null: return
	var sprinting: bool=is_scared or (is_gangster and is_instance_valid(combat_target)) or (ambient_running_enabled and (is_jogger or archetype==Archetype.BEACH_FITNESS_RUNNER))
	gait.advance_distance(delta,displacement,sprinting)

func _ambient_walk_paused() -> bool:
	return false

func _update_walk_destination(_delta: float) -> void:
	var dist := global_position.distance_to(walk_target)
	if dist < 16.0 or dist > 1400.0 or stuck_timer > 2.5:
		_pick_new_sidewalk_target()
		movement_navigation.reset_progress()
		stuck_timer = 0.0

func _gangster_shoot_target(target_pos: Vector2) -> void:
	var rig := get_node_or_null("NPCCombatRig")
	if rig: rig.attack()
	var bullet_scene = load("res://guns/Bullet.tscn")
	if bullet_scene:
		var dir: Vector2 = global_position.direction_to(target_pos)
		var bullet = bullet_scene.instantiate()
		get_tree().current_scene.add_child(bullet)
		bullet.owner_body = self
		bullet.configure_range(WeaponCatalog.get_weapon("pistol"))
		bullet.damage = 10
		bullet.speed = 900.0
		bullet.direction = dir.rotated(randf_range(-0.06, 0.06))
		bullet.global_position = global_position + dir * 20.0
	
	if muzzle_flash_3d:
		muzzle_flash_3d.visible = true
		var t := create_tween()
		t.tween_interval(0.05)
		t.tween_callback(func(): if muzzle_flash_3d: muzzle_flash_3d.visible = false)

	_play_audio(ProceduralAudio.get_gunshot_pistol_stream(), -4.0, randf_range(0.92, 1.08))

func _gangster_melee_attack(target: Node2D, data: Dictionary) -> void:
	var rig := get_node_or_null("NPCCombatRig")
	if rig:
		rig.attack()
	else:
		_play_audio(ProceduralAudio.get_melee_swing_stream("fists"), -4.0)
	var dmg: int = int(data.get("damage", 12))
	if is_instance_valid(target) and target.has_method("take_damage"):
		target.set_meta("combat_attacker", self)
		var reach := float(data.get("melee_range", 46.0))
		dmg = WeaponCatalog.distance_damage(dmg, global_position.distance_to(target.global_position), float(data.get("falloff_start", reach * 0.65)), reach, float(data.get("min_damage_ratio", 0.65)))
		if dmg <= 0: return
		target.take_damage(dmg, false)
		if data.get("is_knife", false) and preload("res://audio/combat/ImpactMaterial.gd").resolve(target) == &"flesh":
			preload("res://guns/combat/BodyWound.gd").apply(target, global_position.direction_to(target.global_position))

var last_pos: Vector2 = Vector2.ZERO
var stuck_timer: float = 0.0
var unstuck_dir_sign: float = 1.0

var movement_navigation := preload("res://emergency/ResponderNavigation.gd").new()

func _navigate_towards(dest: Vector2, move_speed: float, delta: float) -> Vector2:
	var result: Vector2 = movement_navigation.movement(self, dest, move_speed, delta)
	stuck_timer = movement_navigation.stuck_time
	return result


func _pick_new_sidewalk_target() -> void:
	var side_tracks: Array = [
		Vector2(200, 200), Vector2(600, 200), Vector2(1100, 200), Vector2(1500, 200),
		Vector2(200, 420), Vector2(600, 420), Vector2(1100, 420), Vector2(1500, 420),
		Vector2(200, 800), Vector2(600, 800), Vector2(1100, 800), Vector2(1500, 800),
		Vector2(200, 1100), Vector2(600, 1100), Vector2(1100, 1100), Vector2(1500, 1100)
	]
	walk_target = side_tracks[randi() % side_tracks.size()] + Vector2(randf_range(-60, 60), randf_range(-60, 60))

var is_flying: bool = false
var fly_velocity: Vector2 = Vector2.ZERO

## Below this impact speed (px/s) a pedestrian survives a vehicle hit --
## knocked down but alive, waiting for an ambulance. At or above it, the
## hit is fatal and the IML is dispatched instead. Not everyone can be
## saved; a light bump and a full-speed hit read very differently.
const LETHAL_IMPACT_SPEED := 200.0

func get_run_over(impact_velocity: Vector2, _is_player_driver: bool = false) -> void:
	set_meta("death_cause", "vehicle_impact")
	if is_dead or is_incapacitated: return
	if not impact_velocity.is_finite() or impact_velocity.length() < 35.0: return
	if _panic_bubble: _panic_bubble.hide()
	is_flying = true
	fly_velocity = impact_velocity.limit_length(600.0) * 0.85
	_start_fall(impact_velocity)
	collision_layer = 0
	for c in find_children("", "CollisionShape2D", true, false):
		(c as CollisionShape2D).set_deferred("disabled", true)
	for c in find_children("", "CollisionPolygon2D", true, false):
		(c as CollisionPolygon2D).set_deferred("disabled", true)
	var wm = get_node_or_null("/root/WantedManager")
	if impact_velocity.length() < LETHAL_IMPACT_SPEED:
		# Survivable: knocked down, not killed. get_run_over() itself only
		# starts the ragdoll fall (handled in _physics_process); is_dead
		# stays false so this branch, not _die()'s, owns the outcome.
		is_incapacitated = true
		health = 1
		_play_audio(ProceduralAudio.get_scream_stream(), -5.0)
		if wm and _is_player_driver: wm.report_crime(6)
		_dispatch_emergency_ambulance()
	else:
		is_dead = true
		health = 0
		_drop_cash_loot()
		_create_3d_blood_puddle()
		_play_audio(ProceduralAudio.get_scream_stream(), -4.0)
		if wm and _is_player_driver: wm.report_crime(20)
		_dispatch_emergency_coroner()
		_start_decay()
	preload("res://guns/combat/VehiclePersonImpact.gd").feedback(self, impact_velocity, is_dead)

func take_damage(amount: int, is_player_attacker: bool = false) -> void:
	if amount <= 0 or is_dead or is_incapacitated: return
	health = maxi(0, health - amount)
	
	if is_gangster:
		combat_target = get_tree().get_first_node_in_group("player")
		_show_gangster_bubble()
	else:
		panic()
		if health > 0 and is_player_attacker:
			var attacker := get_meta("combat_attacker", null) as Node2D
			if not is_instance_valid(attacker): attacker = get_tree().get_first_node_in_group("player") as Node2D
			_try_civilian_response(attacker)
		
	preload("res://audio/combat/CombatImpactAudio.gd").play_hurt(self, amount)
	
	if health <= 0:
		_die(is_player_attacker)

func _show_gangster_bubble() -> void:
	var phrases = ["MEXEU COM O BONDE ERRADO!", "DERRUBA ELE!", "PEGA O CARA!", "FOGO NELE!"]
	_show_custom_bubble(phrases[randi() % phrases.size()], Color(0.9, 0.2, 0.2))

func hear_traffic_horn(vehicle: Node2D) -> void:
	if is_dead or is_incapacitated or is_flying or is_scared: return
	if get_meta("medical_vehicle_protected", false): return
	var forward := vehicle.global_transform.x.normalized()
	var relative := global_position - vehicle.global_position
	if relative.dot(forward) < 0.0 or relative.dot(forward) > 220.0: return
	var side := forward.orthogonal()
	var width := 44.0
	var hull := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if hull != null and hull.shape is RectangleShape2D:
		width = hull.shape.size.y * vehicle.global_scale.y * 0.5 + 28.0
	if absf(relative.dot(side)) > width: return
	if relative.dot(side) < 0.0: side = -side
	# Test both shoulders with the actual walking body. Never teleport through
	# a parked car or wall; the ordinary navigation and movement remain active.
	for direction in [side, -side]:
		var target: Vector2 = global_position + direction * (width + 28.0 - relative.dot(direction))
		if test_move(global_transform, target - global_position): continue
		_horn_escape_target = target
		_horn_escape_time = 4.5
		return

func hear_gunfire(origin: Vector2, end: Vector2) -> void:
	if is_dead or is_incapacitated or is_gangster: return
	var was_scared := is_scared
	danger_response.remember(origin, end)
	panic()
	if not was_scared:
		_show_custom_bubble("TIROS! CORRE!", Color(0.9, 0.6, 0.2))

func react_to_gunfire(origin: Vector2, end: Vector2, shooter: Node) -> void:
	hear_gunfire(origin, end)
	_try_civilian_response(shooter as Node2D)

func _try_civilian_response(attacker: Node2D) -> void:
	if is_dead or is_incapacitated or is_gangster or not is_scared: return
	if not is_instance_valid(attacker) or not attacker.is_in_group("player"): return
	# Harbor's real walkers are subclasses defined inside HarborLife.gd. Use
	# their ambient group, while story actors keep their authored reactions.
	var ambient_walker := is_in_group("authored_sidewalk_pedestrian") or is_in_group("harbor_dock_worker")
	if not ambient_walker and String(get_script().resource_path) != "res://characters/AnimatedPedestrian3D.gd": return
	if civilian_called_police or civilian_reaction != CivilianReaction.FLEE: return
	if civilian_reaction_profile < 0:
		var roll := randf()
		civilian_reaction_profile = CivilianReaction.ARMED if roll < 0.08 else (CivilianReaction.FIGHT if roll < 0.22 else (CivilianReaction.CALL_POLICE if roll < 0.46 else CivilianReaction.FLEE))
		if archetype == Archetype.CITY_POLICE_OFFICER: civilian_reaction_profile = CivilianReaction.ARMED
		if archetype in [Archetype.CITY_STUDENT_BACKPACK, Archetype.CITY_ELDERLY] and civilian_reaction_profile in [CivilianReaction.FIGHT, CivilianReaction.ARMED]:
			civilian_reaction_profile = CivilianReaction.CALL_POLICE
	var distance := global_position.distance_to(attacker.global_position)
	var chosen := civilian_reaction_profile
	if health < 18 or (chosen == CivilianReaction.FIGHT and distance > 140.0) or (chosen == CivilianReaction.ARMED and distance > 350.0):
		chosen = CivilianReaction.FLEE
	if chosen == CivilianReaction.FLEE: return
	civilian_reaction = chosen
	civilian_threat = attacker
	match chosen:
		CivilianReaction.CALL_POLICE:
			civilian_reaction_time = 1.5
			civilian_call_progress = 3.2
			civilian_call_started = false
		CivilianReaction.FIGHT, CivilianReaction.ARMED:
			civilian_reaction_time = 9.0
			civilian_sight_timer = 0.0
			combat_target = attacker
			if chosen == CivilianReaction.ARMED:
				has_handgun = true
				if is_instance_valid(right_lower_arm):
					var rig := preload("res://characters/pedestrians/NPCCombatRig.gd").attach(self, "pistol")
					rig.set_physics_process(true)
					var weapon := rig.get("current_gun_mesh") as Node3D
					if weapon: weapon.visible = true
				_show_custom_bubble("ABAIXA A ARMA!", Color(0.9, 0.25, 0.2))
			else:
				if is_instance_valid(right_lower_arm):
					var rig := preload("res://characters/pedestrians/NPCCombatRig.gd").attach(self, "fists")
					rig.set_physics_process(true)
				_show_custom_bubble("PARA!", Color(0.9, 0.45, 0.2))

func _civilian_clear_shot(target: Node2D) -> bool:
	if not is_instance_valid(target): return false
	var hit := preload("res://guns/combat/ShotQuery.gd").cast(self, global_position, target.global_position, 7, [get_rid()])
	return hit.is_empty() or hit.collider == target or target.is_ancestor_of(hit.collider)

func _end_civilian_defense() -> void:
	combat_target = null
	civilian_reaction = CivilianReaction.FLEE
	civilian_reaction_time = 0.0
	var rig := get_node_or_null("NPCCombatRig")
	if rig:
		if has_handgun:
			var weapon := rig.get("current_gun_mesh") as Node3D
			if weapon: weapon.visible = false
		rig.set_physics_process(false)

func _update_civilian_call(delta: float) -> bool:
	if civilian_reaction != CivilianReaction.CALL_POLICE: return false
	civilian_reaction_time -= delta
	if civilian_reaction_time > 0.0: return false
	if is_instance_valid(civilian_threat) and global_position.distance_to(civilian_threat.global_position) < 150.0 and not danger_response.sheltered:
		return false
	if not civilian_call_started:
		civilian_call_started = true
		_show_custom_bubble("LIGANDO 190", Color(0.3, 0.65, 0.95))
		_play_audio(ProceduralAudio.get_phone_dial_stream(), -8.0)
	civilian_call_progress -= delta
	if civilian_call_progress <= 0.0:
		civilian_called_police = true
		civilian_reaction = CivilianReaction.FLEE
		var wanted := get_node_or_null("/root/WantedManager")
		if wanted: wanted.report_crime(12)
		_show_custom_bubble("POLÍCIA AVISADA!", Color(0.3, 0.65, 0.95))
		return false
	return true

func _resume_after_panic() -> void:
	if civilian_reaction in [CivilianReaction.FIGHT, CivilianReaction.ARMED]: _end_civilian_defense()
	civilian_reaction = CivilianReaction.FLEE
	civilian_call_started = false
	civilian_threat = null
	danger_response.threats.clear()
	_pick_new_sidewalk_target()

func panic() -> void:
	if is_dead or is_incapacitated: return
	panic_timer = randf_range(9.0, 12.0)
	if is_scared: return
	if danger_response.threats.is_empty():
		var player := get_tree().get_first_node_in_group("player") as Node2D
		var origin := player.global_position if player else global_position - Vector2(30, 0)
		danger_response.remember(origin, origin)
	is_scared = true
	behavior_action = 0
	# A lethal hit has its own reaction in _die(); do not stack two voices.
	if health > 0:
		_play_audio(ProceduralAudio.get_pedestrian_scream_stream(), -6.0)
	var phrases = ["SOCORRO!", "PARA COM ISSO!", "CORRE!", "CUIDADO!"]
	_show_custom_bubble(phrases[randi() % phrases.size()], Color(0.9, 0.6, 0.2))

var _panic_bubble: PanelContainer = null
var _panic_label: Label = null

func _show_custom_bubble(text: String, border_col: Color) -> void:
	if _panic_bubble == null:
		_panic_bubble = PanelContainer.new()
		_panic_bubble.position = Vector2(-55, -44)
		_panic_bubble.custom_minimum_size = Vector2(110, 22)
		_panic_bubble.z_index = 22
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.15, 0.90)
		style.border_color = border_col
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 2
		style.content_margin_bottom = 2
		_panic_bubble.add_theme_stylebox_override("panel", style)
		
		_panic_label = Label.new()
		_panic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_panic_label.add_theme_font_size_override("font_size", 9)
		_panic_label.add_theme_color_override("font_color", Color.WHITE)
		_panic_bubble.add_child(_panic_label)
		add_child(_panic_bubble)
		
	_panic_label.text = text
	preload("res://ui/WorldSpeechLayout.gd").show_for(self, _panic_bubble, 2.8)

func _drop_cash_loot() -> void:
	var tree = get_tree()
	if tree == null: return
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	var cash = CashPickup.new()
	cash.amount = dropped_cash
	cash.global_position = global_position + Vector2(randf_range(-8, 8), randf_range(-8, 8))
	parent.call_deferred("add_child", cash)
	
	if is_gangster:
		var wp := WeaponPickup.new()
		wp.weapon_id = &"pistol" if randf() > 0.35 else &"smg"
		wp.ammo_amount = randi_range(10, 24)
		wp.global_position = global_position + Vector2(randf_range(-12, 12), randf_range(-12, 12))
		parent.call_deferred("add_child", wp)

func _die(is_player_attacker: bool = false) -> void:
	is_dead = true
	if _panic_bubble: _panic_bubble.visible = false
	velocity = Vector2.ZERO
	collision_layer = 0
	for c in find_children("", "CollisionShape2D", true, false):
		(c as CollisionShape2D).set_deferred("disabled", true)
	for c in find_children("", "CollisionPolygon2D", true, false):
		(c as CollisionPolygon2D).set_deferred("disabled", true)
	_start_fall()
	_drop_cash_loot()
	_create_3d_blood_puddle()
	_play_audio(ProceduralAudio.get_death_reaction_stream(), -4.0)
	
	var wm = get_node_or_null("/root/WantedManager")
	if wm and is_player_attacker: wm.report_crime(20)
	_dispatch_emergency_coroner()
	_start_decay()

func _dispatch_emergency_coroner() -> void:
	# Fatal bodies are bounded by GroundBlood's corpse visual budget. The game
	# keeps no coroner/IML dispatch for them; ambulances remain reserved for
	# incapacitated living actors.
	return

func _dispatch_emergency_ambulance() -> void:
	var care := get_node_or_null("/root/NPCMedicalCare")
	if care:
		care.report_injury(self)
		return
	var director := get_tree().get_first_node_in_group("emergency_depot_director")
	if director and director.has_method("request_dispatch"):
		get_tree().create_timer(1.2).timeout.connect(func():
			if is_instance_valid(self) and is_incapacitated and not is_dead:
				director.request_dispatch("ambulance", self)
		)

## Compatibility entry point; recovery belongs to the saved medical routine.
var emergency_rescue_in_progress := false

func rescue_from_emergency(ambulance: Node2D) -> void:
	if emergency_rescue_in_progress: return
	var care := get_node_or_null("/root/NPCMedicalCare")
	if care == null or not is_instance_valid(ambulance): return
	emergency_rescue_in_progress = true
	care.report_injury(self)
	care.board_patient(self, ambulance)

func _create_3d_blood_puddle() -> void:
	preload("res://guns/combat/GroundBlood.gd").spawn(self, true)


func _start_decay() -> void:
	# Corpse lifetime is owned by GroundBlood's five-entry visual budget so the
	# body and its blood fade together instead of using independent timers.
	return

func _play_audio(stream: AudioStream, volume_db: float = -6.0, pitch_scale: float = 1.0) -> void:
	var player := AudioStreamPlayer2D.new()
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.max_distance = 600.0
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _start_fall(impact := Vector2.ZERO) -> void:
	ensure_presentation()
	_fallen_presentation_cached = false
	_detach_atlas_presentation_for_fall()
	fall_presentation.start(self, model_root, viewport, impact)

func _detach_atlas_presentation_for_fall() -> void:
	if not _presentation_atlas_active or not is_instance_valid(model_root): return
	var budget := get_node_or_null("/root/PresentationBudget")
	if budget == null or not budget.has_method("detach_ambient_atlas_actor"): return
	if not budget.detach_ambient_atlas_actor(self): return
	var personal_viewport := SubViewport.new()
	personal_viewport.name = "FallenCitizenViewport"
	personal_viewport.size = PRESENTATION_SIZE
	personal_viewport.transparent_bg = true
	personal_viewport.own_world_3d = true
	personal_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	personal_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(personal_viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.2, 1.4)
	camera.fov = 36.0
	personal_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.65, 0.0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	light.light_energy = 1.35
	light.shadow_enabled = false
	personal_viewport.add_child(light)
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0, 0, 0, 0)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color(0.70, 0.72, 0.82)
	environment.environment = resource
	personal_viewport.add_child(environment)
	var preserved_rotation := model_root.rotation
	var preserved_scale := model_root.scale
	model_root.reparent(personal_viewport, false)
	model_root.position = Vector3.ZERO
	model_root.rotation = preserved_rotation
	model_root.scale = preserved_scale
	viewport = personal_viewport
	_presentation_atlas_active = false
	_presentation_shared_world = false
	_presentation_world_origin = Vector3.ZERO
	_presentation_atlas_region = Rect2()
	set_meta("presentation_world_origin", Vector3.ZERO)
	if is_instance_valid(sprite_3d_display):
		sprite_3d_display.texture = viewport.get_texture()
		sprite_3d_display.region_enabled = false
		sprite_3d_display.region_rect = Rect2()
