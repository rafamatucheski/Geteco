extends "res://prototypes/living_cast/CoupeDamageModel.gd"

## Classe base para todos os modelos de veículos 3D procedurais da Frota Viva.
## Herda os contratos de deformação e dano de lataria (CoupeDamageModel.gd).
## Fornece helpers especializados para carrocerias, vidros, rodas esterçáveis e equipamentos.

func _init() -> void:
	var geometry_cache := preload("res://cars/VehicleGeometryCache.gd")
	# Regional prewarm constructs an empty scripted shell, then advances geometry,
	# validation and publication in scheduler-owned stages. Normal gameplay never
	# enters this mode and keeps the restore/build/capture path below unchanged.
	if geometry_cache.should_defer_constructor(self):
		set_meta("vehicle_deferred_prewarm_shell", true)
		return
	if get_child_count() == 0:
		if not geometry_cache.restore(self):
			build()
			geometry_cache.capture(self)

func _enter_tree() -> void:
	if get_child_count() == 0:
		build()

func _ready() -> void:
	if get_child_count() == 0:
		build()
	super._ready()

func add_wheel(
	side: float,
	wheel_y: float,
	wheel_z: float,
	tire_radius: float = 0.35,
	tire_width: float = 0.22,
	rim_radius: float = 0.22,
	spoke_count: int = 5,
	rim_color: String = "b5bdc3"
) -> void:
	var black := mat("rubber", "15191d", 0.0, 0.92)
	var trim := mat("trim", "282f36", 0.2, 0.45)
	var rim_mat := mat("rim_" + rim_color, rim_color, 0.75, 0.25)
	var brake_mat := mat("caliper", "cd382b", 0.3, 0.4)
	var rotor_mat := mat("rotor", "555d64", 0.6, 0.5)

	var style := _wheel_style()
	var first_idx := get_child_count()
	var center := Vector3(side, wheel_y, wheel_z)

	# 1. Pneu de borracha
	var tire := cylinder(center, tire_radius, tire_width, black)
	tire.rotation.z = PI / 2.0

	# The authored tire is a capped cylinder. Place the wheel face beyond its
	# outer cap: the former solid rim hid every spoke inside that cylinder.
	var outward := signf(side)
	var face := center + Vector3(outward * (tire_width * 0.5 + 0.014), 0, 0)
	var lip := TorusMesh.new()
	lip.inner_radius = rim_radius * 0.87
	lip.outer_radius = rim_radius
	lip.rings = 32
	lip.ring_segments = 6
	mesh_node(lip, face, rim_mat).rotation.z = PI / 2.0
	var disc := cylinder(face - Vector3(outward * 0.010, 0, 0), rim_radius * 0.87, 0.006, rotor_mat)
	disc.rotation.z = PI / 2.0
	var caliper := box(face + Vector3(-outward * 0.003, rim_radius * 0.60, 0.035), Vector3(0.012, rim_radius * 0.35, 0.055), brake_mat if style in ["split", "sport"] else trim)

	if style in ["steel", "utility", "classic", "aero"]:
		var plate := cylinder(face, rim_radius * 0.88, 0.008, rim_mat)
		plate.rotation.z = PI / 2.0
		var holes := 6 if style == "steel" else 8
		for i in holes:
			var angle := TAU * i / holes
			var inset := face + Vector3(outward * 0.006, cos(angle) * rim_radius * 0.65, sin(angle) * rim_radius * 0.65)
			if style == "aero":
				var slot := box(inset, Vector3(0.004, rim_radius * 0.27, rim_radius * 0.085), trim)
				slot.rotation.x = angle + 0.35
			else:
				var hole := cylinder(inset, rim_radius * (0.14 if style == "utility" else 0.10), 0.004, trim)
				hole.rotation.z = PI / 2.0
	else:
		var count := 5 if style in ["sport", "split"] else spoke_count
		for i in count:
			var angle := TAU * i / count
			var branches := 2 if style == "split" else 1
			for branch in branches:
				var a := angle + ((-0.10 if branch == 0 else 0.10) if branches == 2 else 0.0)
				var width := rim_radius * (0.23 if style == "sport" else 0.11)
				var spoke := box(face + Vector3(outward * 0.005, cos(a) * rim_radius * 0.53, sin(a) * rim_radius * 0.53), Vector3(0.014, rim_radius * 0.76, width), rim_mat)
				spoke.rotation.x = a
	var hub_radius := rim_radius * (0.48 if style == "classic" else 0.24)
	var hub := cylinder(face + Vector3(outward * 0.014, 0, 0), hub_radius, 0.020, rim_mat if style in ["classic", "utility"] else trim)
	hub.rotation.z = PI / 2.0

	# Marcação de metadados para direção de HarborCoupe
	for idx in range(first_idx, get_child_count()):
		var part := get_child(idx)
		part.set_meta("wheel_center", center)
		part.set_meta("wheel_spins", part != caliper)
		# O rig precisa do raio real para rolar o pneu na velocidade certa: um
		# caminhão de 0.50 m girava com a cadência de um sedã de 0.355 m.
		part.set_meta("wheel_radius", tire_radius)
		part.set_meta("wheel_style", style)

func _wheel_style() -> String:
	# Stable per authored model, including models whose legacy vehicle_id is empty.
	match get_script().resource_path.get_file().trim_suffix("Model.gd"):
		"MetroHatch", "CourierVan", "DockDeliveryVan", "PoliceCruiser": return "steel"
		"RouteCity", "Boxrunner", "Towmaster", "RescuePumper", "MedicBox", "AmericanFlatbed", "SnowPlow": return "utility"
		"NordicEstate", "WoodyWagon", "BeachBuggy", "UnionSedan": return "classic"
		"OrbitaMicro", "NimbusMinivan": return "aero"
		"SportEstate", "VerticeMidEngine", "ValeCrossover": return "split"
		"SummitSUV", "ArcticJeep", "PoliceSUV", "RanchSingle", "BravioCrew", "AtlasCrewPickup", "SertaoTrailPickup", "DuneBuggy": return "sport"
		_: return "multi"

func add_lightbar(
	y_pos: float,
	z_pos: float,
	color_left: Color = Color.RED,
	color_right: Color = Color.BLUE,
	width: float = 1.10
) -> void:
	var bar_base := box(Vector3(0.0, y_pos, z_pos), Vector3(width, 0.05, 0.22), mat("lightbar_mount", "1a1d20", 0.5, 0.4))
	var glass_left := box(Vector3(-width * 0.26, y_pos + 0.05, z_pos), Vector3(width * 0.44, 0.07, 0.18), mat("bar_left", color_left.to_html(false), 0.1, 0.1, 0.95))
	var glass_right := box(Vector3(width * 0.26, y_pos + 0.05, z_pos), Vector3(width * 0.44, 0.07, 0.18), mat("bar_right", color_right.to_html(false), 0.1, 0.1, 0.95))
	var center_siren := cylinder(Vector3(0.0, y_pos + 0.04, z_pos), 0.08, 0.10, mat("siren_speaker", "2f3640", 0.6, 0.3))
	center_siren.rotation.x = PI / 2.0

func add_roof_sign(y_pos: float, z_pos: float, text_label: String, bg_color: Color = Color("#f1c40f"), fg_color: Color = Color("#111111")) -> void:
	var base := box(Vector3(0.0, y_pos + 0.015, z_pos), Vector3(0.48, 0.025, 0.16), mat("sign_base", "2d3436", 0.4, 0.5))
	var sign_box := box(Vector3(0.0, y_pos + 0.08, z_pos), Vector3(0.44, 0.10, 0.12), mat("sign_glow", bg_color.to_html(false), 0.1, 0.2, 0.55))
	# Letras ou símbolos contrastantes
	var mark := box(Vector3(0.0, y_pos + 0.08, z_pos), Vector3(0.36, 0.05, 0.125), mat("sign_text", fg_color.to_html(false), 0.1, 0.4))

func add_exhaust_dual(x_offset: float, y_pos: float, z_pos: float, radius: float = 0.065) -> void:
	var rim_mat := mat("chrome_exhaust", "dcdde1", 0.85, 0.2)
	var black := mat("exhaust_hole", "000000", 0.0, 1.0)
	for s in [-1.0, 1.0]:
		var pipe := cylinder(Vector3(s * x_offset, y_pos, z_pos), radius, 0.14, rim_mat)
		pipe.rotation.x = PI / 2.0
		var hole := cylinder(Vector3(s * x_offset, y_pos, z_pos + 0.06), radius * 0.78, 0.02, black)
		hole.rotation.x = PI / 2.0
