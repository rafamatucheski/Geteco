extends Node3D
## Six reusable transparent ribbon segments; no surface rebuilds during a swing.
## Rastro de movimento do taco e do machado: a faixa liga, quadro a quadro, o
## segmento `inner`→`outer` (espaço do modelo da arma). No machado é a largura do
## fio; no taco, o comprimento do barril — lê como borrão de velocidade.
const MAX_SAMPLES := 7
const LIFETIME := 0.09
@export var inner := Vector3(0.07, 0, -0.44)
@export var outer := Vector3(0.19, 0, -0.44)
@export var opacity := 0.18
var samples: Array[Dictionary] = []
var ribbon: MultiMeshInstance3D
var mesh := MultiMesh.new()
var material := StandardMaterial3D.new()

func _ready() -> void:
	ribbon = MultiMeshInstance3D.new()
	ribbon.top_level = true
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_colors = true
	mesh.mesh = QuadMesh.new()
	mesh.instance_count = MAX_SAMPLES - 1
	mesh.visible_instance_count = 0
	ribbon.multimesh = mesh
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	ribbon.material_override = material
	add_child(ribbon)
	ribbon.global_transform = Transform3D.IDENTITY
	ribbon.visible = false

## `active`: trecho rápido do golpe (`WeaponRigPose` → `swing_trail`). Fora dele
## as amostras só envelhecem e a faixa some sozinha.
func update_trail(delta: float, active: bool) -> void:
	if not is_instance_valid(ribbon): return
	for sample in samples: sample.life -= delta
	while not samples.is_empty() and samples[0].life <= 0.0: samples.pop_front()
	if active:
		samples.append({"inner": get_parent().to_global(inner), "outer": get_parent().to_global(outer), "life": LIFETIME})
		if samples.size() > MAX_SAMPLES: samples.pop_front()
	var count := 0
	for i in range(1, samples.size()):
		var a := samples[i-1]
		var b := samples[i]
		var width: Vector3 = ((a.outer - a.inner) + (b.outer - b.inner)) * 0.5
		var along: Vector3 = ((b.inner + b.outer) - (a.inner + a.outer)) * 0.5
		var normal := width.cross(along)
		if normal.length_squared() < 0.00000001: continue
		var center: Vector3 = (a.inner + a.outer + b.inner + b.outer) * 0.25
		mesh.set_instance_transform(count, Transform3D(Basis(width, along, normal.normalized()), center))
		mesh.set_instance_color(count, Color(0.78,0.85,0.9,float(a.life) / LIFETIME * opacity))
		count += 1
	mesh.visible_instance_count = count
	ribbon.visible = count > 0
