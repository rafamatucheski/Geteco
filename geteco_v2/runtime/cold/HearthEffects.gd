extends Node3D
## Small, deterministic warm effects: five flame tongues and seven wisps.
## No fullscreen bloom or abrupt flashes; suspended with the owning interior.
@export var show_flames := true
@export var smoke_height := 0.7
@export var warmth := 0.7
var clock := 0.0
var flames: Array[MeshInstance3D] = []
var wisps: Array[MeshInstance3D] = []

func _ready() -> void:
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1, 0.48, 0.10, 0.8)
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1, 0.38, 0.06)
	flame_mat.emission_energy_multiplier = 0.7
	if show_flames:
		for i in 5:
			var flame := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.07
			mesh.height = 0.35
			mesh.radial_segments = 8
			mesh.rings = 4
			flame.mesh = mesh
			flame.material_override = flame_mat
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.position = Vector3((i - 2) * 0.065, 0.16, sin(i * 2.0) * 0.05)
			add_child(flame)
			flames.append(flame)
	for i in 7:
		var smoke := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.06
		mesh.height = 0.09
		mesh.radial_segments = 8
		mesh.rings = 4
		smoke.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.7, 0.76, 0.8, 0.07)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		smoke.material_override = mat
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(smoke)
		wisps.append(smoke)

func _process(delta: float) -> void:
	clock += minf(delta, 0.1)
	for i in flames.size():
		var flame := flames[i]
		flame.scale.y = 0.85 + 0.17 * sin(clock * 4.0 + i * 1.7) + 0.05 * sin(clock * 7.3 + i)
		flame.rotation.z = 0.12 * sin(clock * 2.3 + i)
	for i in wisps.size():
		var t := fposmod(clock * 0.24 + float(i) / 7.0, 1.0)
		var smoke := wisps[i]
		smoke.position = Vector3(sin(clock * 0.7 + i) * 0.05 * t, 0.22 + t * smoke_height, cos(i * 1.7) * t * 0.045)
		smoke.scale = Vector3.ONE * (0.6 + t * 1.3)
		var mat := smoke.material_override as StandardMaterial3D
		mat.albedo_color.a = sin(t * PI) * 0.065
