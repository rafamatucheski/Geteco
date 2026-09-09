class_name PortArtPackShowcase
extends Node3D

## Galeria completa de demonstração do Kit Procedural 3D do Porto (Harbor Art Pack).
## Exibe todos os 21 props organizados por categorias, referências humanas de 1,80m
## e as 3 composições prontas de ambientação.

func _ready() -> void:
	_build_gallery()

func _build_gallery() -> void:
	# 1. Piso geral de concreto do porto
	_create_port_ground()

	# 2. Iluminação ambiente e sol suave
	_setup_lighting()

	# 3. Fileira A: Contêineres e Referência Humana (Z = -14.0)
	var z_row_a := -14.0
	var man_a := PortHumanReference3D.new()
	man_a.position = Vector3(-14.0, 0.0, z_row_a)
	add_child(man_a)

	var c40 := PortContainer40ft3D.new()
	c40.position = Vector3(-8.0, 0.0, z_row_a)
	add_child(c40)

	var c20 := PortContainer20ft3D.new()
	c20.position = Vector3(0.0, 0.0, z_row_a)
	add_child(c20)

	var c_open := PortContainerOpen3D.new()
	c_open.position = Vector3(6.5, 0.0, z_row_a)
	add_child(c_open)

	var c_reefer := PortReeferContainer3D.new()
	c_reefer.position = Vector3(14.0, 0.0, z_row_a)
	add_child(c_reefer)

	# 4. Fileira B: Carga, Pallets e Veículos de Armazém (Z = -6.0)
	var z_row_b := -6.0
	var man_b := PortHumanReference3D.new()
	man_b.position = Vector3(-14.0, 0.0, z_row_b)
	add_child(man_b)

	var forklift := PortForklift3D.new()
	forklift.position = Vector3(-9.0, 0.0, z_row_b)
	add_child(forklift)

	var cart := PortPlatformCart3D.new()
	cart.position = Vector3(-4.5, 0.0, z_row_b)
	add_child(cart)

	var hand_truck := PortHandTruck3D.new()
	hand_truck.position = Vector3(-2.5, 0.0, z_row_b)
	add_child(hand_truck)

	var p_stack := PortPalletStack3D.new()
	p_stack.position = Vector3(0.0, 0.0, z_row_b)
	add_child(p_stack)

	var p_clean := PortWoodenPallet3D.new()
	p_clean.position = Vector3(2.5, 0.0, z_row_b)
	add_child(p_clean)

	var p_weath := PortWeatheredPallet3D.new()
	p_weath.position = Vector3(4.5, 0.0, z_row_b)
	add_child(p_weath)

	var tote := PortPlasticTote3D.new()
	tote.position = Vector3(6.5, 0.0, z_row_b)
	add_child(tote)

	var drum_pal := PortDrumClusterPallet3D.new()
	drum_pal.position = Vector3(9.5, 0.0, z_row_b)
	add_child(drum_pal)

	var tower := PortFloodlightTower3D.new()
	tower.position = Vector3(14.0, 0.0, z_row_b)
	add_child(tower)

	# 5. Fileira C: Caixas, Tambores e Elementos de Cais (Z = 1.0)
	var z_row_c := 1.0
	var man_c := PortHumanReference3D.new()
	man_c.position = Vector3(-14.0, 0.0, z_row_c)
	add_child(man_c)

	var crate := PortCargoCrate3D.new()
	crate.position = Vector3(-11.0, 0.0, z_row_c)
	add_child(crate)

	var long_crate := PortLongCrate3D.new()
	long_crate.position = Vector3(-7.5, 0.0, z_row_c)
	add_child(long_crate)

	var drum_clean := PortOilDrum3D.new()
	drum_clean.position = Vector3(-4.5, 0.0, z_row_c)
	add_child(drum_clean)

	var drum_rust := PortRustyDrum3D.new()
	drum_rust.position = Vector3(-3.0, 0.0, z_row_c)
	add_child(drum_rust)

	var fender := PortPierFender3D.new()
	fender.position = Vector3(0.0, 0.0, z_row_c)
	add_child(fender)

	var bollard := PortMooringBollard3D.new()
	bollard.position = Vector3(3.0, 0.0, z_row_c)
	add_child(bollard)

	var buoy := PortLifebuoyStand3D.new()
	buoy.position = Vector3(5.5, 0.0, z_row_c)
	add_child(buoy)

	var hazard := PortHazardSign3D.new()
	hazard.position = Vector3(8.0, 0.0, z_row_c)
	add_child(hazard)

	# 6. Três Composições Prontas (Z = 13.0 a 24.0)
	# Composição 1: Área de Carga e Estivação
	var comp1 := PortCargoStagingArea3D.new()
	comp1.position = Vector3(-16.0, 0.0, 16.0)
	add_child(comp1)

	# Composição 2: Depósito Portuário
	var comp2 := PortStorageDepot3D.new()
	comp2.position = Vector3(1.0, 0.0, 16.0)
	add_child(comp2)

	# Composição 3: Canto de Manutenção
	var comp3 := PortMaintenanceCorner3D.new()
	comp3.position = Vector3(14.0, 0.0, 16.0)
	add_child(comp3)

func _create_port_ground() -> void:
	var ground_mat := PortArtMaterials.get_mat("port_ground_asphalt", Color("#33383d"), 0.1, 0.85)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(70.0, 70.0)
	floor_mesh.mesh = pm
	floor_mesh.position = Vector3(0.0, -0.01, 4.0)
	floor_mesh.material_override = ground_mat
	add_child(floor_mesh)

func _setup_lighting() -> void:
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-48.0, 42.0, 0.0)
	dir_light.light_color = Color("#fff7e6")
	dir_light.light_energy = 1.3
	dir_light.shadow_enabled = true
	add_child(dir_light)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#4b5b6d")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9eaec1")
	env.ambient_light_energy = 0.55
	env_node.environment = env
	add_child(env_node)
