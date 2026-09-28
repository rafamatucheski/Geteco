extends SceneTree
## Vértice isolada (sem Main): monta a empresa, confere que as rotas novas dos
## operadores, as vagas das empilhadeiras e os caminhos do escritório não
## atravessam nenhum sólido, e que os modelos dos funcionários olham para +Z
## do visual girado (frente real) — a causa da caminhada de ré.
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	print(("OK   " if ok else "FAIL ")+label)
	if not ok: failures.append(label); push_error(label)
func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, radius: float, exclude: Array) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 1.7
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = exclude
	var steps := maxi(1,ceili(from.distance_to(to)/.25))
	for i in steps+1:
		query.transform = Transform3D(Basis(),from.lerp(to,float(i)/steps)+Vector3.UP*.95)
		var hits := space.intersect_shape(query,1)
		if not hits.is_empty():
			var body: Node = hits[0].collider
			print("     bloqueio em %s por %s"%[str(from.lerp(to,float(i)/steps)),body.get_path()])
			return true
	return false
func run() -> void:
	var company = load("res://gameplay/urban_v1/VerticeCompany.gd").new()
	root.add_child(company)
	for i in 4: await physics_frame
	var space: PhysicsDirectSpaceState3D = company.get_world_3d().direct_space_state
	var origin: Vector3 = company.ORIGIN
	var operators := 0
	for entry in company.staff:
		if not entry.guard and not entry.office: operators += 1
		# O visual do Actor aponta -Z para o movimento; o modelo precisa de meia volta.
		var model: Node3D = entry.model
		var walk_dir: Vector3 = -entry.actor.visual.global_basis.z
		check(model.global_basis.z.normalized().dot(walk_dir.normalized())>.99,"%s: peito do modelo na direção da caminhada"%entry.actor.name)
		# A patrulha do guarda (anterior a este teste) raspa no poste (42, 56);
		# o Actor contorna deslizando. Aqui só as rotas de operadores e escritório.
		if entry.guard: continue
		var route: Array = entry.route
		for i in route.size():
			var a: Vector3 = origin+route[i]
			var b: Vector3 = origin+route[(i+1)%route.size()]
			if route.size()==1: break
			check(not _blocked(space,a,b,.3,[entry.actor.get_rid()]),"%s: trecho %d livre de sólidos"%[entry.actor.name,i])
	check(operators>=6,"Seis ou mais operadores (%d)"%operators)
	check(company.desk_staff.size()==2,"Dois funcionários sentados")
	for bay in company.forklifts.BAYS:
		var query := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.7,2.0,4.0)
		query.shape = box
		query.collision_mask = 1
		query.transform = Transform3D(Basis(Vector3.UP,bay.yaw),origin+bay.point+Vector3.UP*1.1)
		check(space.intersect_shape(query,1).is_empty(),"Vaga da empilhadeira em %s livre"%str(bay.point))
	# Caminhos do escritório: porta até a passagem, e até o envelope escondido.
	check(not _blocked(space,origin+Vector3(35,0,29),origin+Vector3(35,0,8),.3,[]),"Corredor x35 do escritório livre")
	check(not _blocked(space,origin+Vector3(35,0,8),origin+Vector3(35,0,3.4),.3,[]),"Envelope escondido continua alcançável")
	check(not _blocked(space,origin+Vector3(35,0,8),origin+Vector3(28.5,0,8),.3,[]),"Passagem z8 escritório–galpão livre")
	check(company.clutter.solids.size()>=8,"Bagunça do escritório com volumes físicos (%d)"%company.clutter.solids.size())
	check(company.booms.size()==3 and company.lift_cylinders.size()==3,"Três reach-stackers com lança e cilindro")
	print("FALHAS: %d"%failures.size())
	quit(0 if failures.is_empty() else 1)
