extends RefCounted
## Terrain3D's baked output, limited to one tile near Terminal da Serra.
## The live 1.0.2 native node crashes this 4.7.2 .NET session (Windows heap
## corruption). No native Terrain3D node is instantiated during gameplay.
const ORIGIN := Vector2(704, -448)
const SIZE := 64
const SHADER := preload("res://world/regions/mountain_terrain3d_pilot.gdshader")
const BAKED_PATH := "res://world/regions/terrain3d_pilot/terminal_mesh.res"

static func enabled() -> bool:
	return "--terrain3d-baseline" not in OS.get_cmdline_user_args()

static var _baked: ArrayMesh

static func attach(source: RefCounted, surface: MeshInstance3D, rect: Rect2, trail: Texture2D) -> void:
	if rect.position != ORIGIN or not enabled(): return
	# Guardada: só o trecho do terminal segura a malha, e ao sair dele o recurso deixava o cache; a volta
	# relia o .res do disco no meio do jogo, no estágio síncrono de superfícies.
	if _baked == null: _baked = load(BAKED_PATH) as ArrayMesh
	var mesh := _baked
	if mesh == null:
		push_error("Missing Terrain3D baked pilot: run tools/terrain3d/bake_mountain.gd")
		return
	# Future road edits must not leave an obsolete floor over the collider.
	var heights: PackedFloat32Array = mesh.get_meta("native_grid_heights",PackedFloat32Array())
	if heights.size()!=289: push_error("Invalid Terrain3D pilot height signature"); return
	for z in 17:
		for x in 17:
			if absf(heights[z*17+x]-source.height_at(ORIGIN+Vector2(x,z)*4.0))>.001:
				push_warning("Terrain3D pilot needs rebaking after mountain layout changes; native ground retained")
				return
	surface.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("trail_mask",trail)
	preload("res://world/regions/WorldConnection3D.gd").configure_ground_material(material)
	preload("res://world/regions/MountainGroundFinish.gd").apply_ground(material)
	surface.material_override = material
	surface.set_instance_shader_parameter("origin",ORIGIN)
	surface.set_meta("terrain3d_baked_pilot",true)
