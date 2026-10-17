extends RefCounted
## Acessórios de cabeça (bonés, chapéus, gorro, óculos) para corpos importados do Meshy.
##
## O corpo do Meshy já traz cabelo e rosto na textura, então chapéu e óculos entram como peças do kit
## (`CivilianMeshKit`, uma malha pequena e compartilhada por tipo) presas ao osso `Head` do esqueleto com um
## `BoneAttachment3D`: seguem a cabeça exatamente como o crânio, inclusive na queda e na morte. A peça é
## desenhada no mesmo espaço da cabeça do kit (origem na base do pescoço, topo do cabelo em ~0,29 m, rosto em +Z);
## `MeshyBodyRig.attach_accessories` posiciona essa origem para o crânio de cada corpo.
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
## Cor de cada tipo quando o chamador não escolhe uma; `lens` é fixo no kit.
const KINDS := ["cap", "beanie", "cowboy", "straw", "fedora", "sunglasses", "clown", "motorcycle_helmet"]

static func mesh(kind: String) -> ArrayMesh:
	return KIT.cached("acc|" + kind, func() -> ArrayMesh:
		var b := KIT._builder()
		match kind:
			"motorcycle_helmet":
				b.ellipsoid(Vector3(0,.20,-.008),Vector3(.145,.15,.156),KIT.SLOT_ACCENT,Basis.IDENTITY,16,10)
				b.ellipsoid(Vector3(0,.19,.127),Vector3(.12,.065,.044),KIT.SLOT_LENS,Basis.IDENTITY,14,6)
				b.ellipsoid(Vector3(0,.10,.09),Vector3(.135,.033,.10),KIT.SLOT_ACCENT,Basis.IDENTITY,12,5)
			"cap": # boné
				b.ellipsoid(Vector3(0, .238, -.006), Vector3(.109, .075, .12), KIT.SLOT_ACCENT, Basis.IDENTITY, 12, 6)
				b.ellipsoid(Vector3(0, .222, .115), Vector3(.085, .011, .085), KIT.SLOT_ACCENT, Basis(Vector3.RIGHT, .12), 10, 3, .85)
			"beanie": # gorro com dobra
				b.ellipsoid(Vector3(0, .232, -.012), Vector3(.112, .1, .124), KIT.SLOT_ACCENT, Basis.IDENTITY, 12, 7)
				b.loft([[.21, .113, .124, KIT.SLOT_ACCENT, -.012], [.17, .113, .125, KIT.SLOT_ACCENT, -.012]], KIT.SLOT_ACCENT, Transform3D.IDENTITY, 14, false, false, .82)
			"fedora": # copa com vinco, fita no tom `inner_color` e aba
				b.loft([[.335, .082, .09, KIT.SLOT_ACCENT, -.01, 2.4], [.3, .1, .112, KIT.SLOT_ACCENT, -.01, 2.4], [.24, .112, .124, KIT.SLOT_INNER, -.01, 2.3], [.21, .113, .125, KIT.SLOT_ACCENT, -.01]], KIT.SLOT_ACCENT, Transform3D.IDENTITY, 14, true, false)
				b.ellipsoid(Vector3(0, .335, -.01), Vector3(.03, .012, .07), KIT.SLOT_ACCENT, Basis.IDENTITY, 6, 3, .7)
				b.ellipsoid(Vector3(0, .212, -.008), Vector3(.2, .012, .21), KIT.SLOT_ACCENT, Basis(Vector3.RIGHT, -.06), 14, 3, .9)
			"cowboy": # chapéu de vaqueiro: copa amassada, fita e aba larga com as laterais viradas para cima
				b.loft([[.355, .066, .082, KIT.SLOT_ACCENT, -.01, 2.4], [.322, .096, .112, KIT.SLOT_ACCENT, -.01, 2.4], [.255, .114, .126, KIT.SLOT_ACCENT, -.01, 2.3], [.21, .115, .127, KIT.SLOT_ACCENT, -.01]], KIT.SLOT_ACCENT, Transform3D.IDENTITY, 14, true, false)
				b.loft([[.262, .1155, .1275, KIT.SLOT_INNER, -.01], [.232, .1165, .1285, KIT.SLOT_INNER, -.01]], KIT.SLOT_INNER, Transform3D.IDENTITY, 14, false, false)
				b.ellipsoid(Vector3(0, .338, -.01), Vector3(.034, .012, .07), KIT.SLOT_ACCENT, Basis.IDENTITY, 6, 3, .7)
				b.ellipsoid(Vector3(0, .212, -.004), Vector3(.17, .012, .225), KIT.SLOT_ACCENT, Basis(Vector3.RIGHT, -.05), 14, 3, .9)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .185, .238, -.004), Vector3(.075, .011, .2), KIT.SLOT_ACCENT, Basis(Vector3.FORWARD, side * .5), 8, 3, .9)
			"straw": # chapéu de palha: copa baixa e aba larga e plana
				b.loft([[.31, .09, .105, KIT.SLOT_ACCENT, -.01, 2.2], [.285, .108, .122, KIT.SLOT_ACCENT, -.01, 2.2], [.215, .114, .127, KIT.SLOT_ACCENT, -.01]], KIT.SLOT_ACCENT, Transform3D.IDENTITY, 14, true, false)
				b.loft([[.245, .1155, .1285, KIT.SLOT_INNER, -.01], [.222, .1165, .1295, KIT.SLOT_INNER, -.01]], KIT.SLOT_INNER, Transform3D.IDENTITY, 14, false, false)
				b.ellipsoid(Vector3(0, .207, -.004), Vector3(.26, .01, .27), KIT.SLOT_ACCENT, Basis(Vector3.RIGHT, -.04), 16, 3, .9)
			"clown": # peruca de palhaço (laterais e topete na cor `color`) e nariz vermelho (cor `band`)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .125, .2, -.02), Vector3(.075, .085, .085), KIT.SLOT_ACCENT, Basis.IDENTITY, 10, 6)
					b.ellipsoid(Vector3(side * .06, .275, .0), Vector3(.075, .06, .08), KIT.SLOT_ACCENT, Basis.IDENTITY, 8, 5)
				b.ellipsoid(Vector3(0, .15, .125), Vector3(.034, .034, .034), KIT.SLOT_INNER, Basis.IDENTITY, 8, 5)
			"sunglasses": # lentes escuras e hastes (geometria do `glasses` do kit, um pouco maiores)
				for side in [-1.0, 1.0]:
					b.ellipsoid(Vector3(side * .039, .172, .121), Vector3(.03, .02, .007), KIT.SLOT_LENS, Basis.IDENTITY, 8, 4)
					b.ellipsoid(Vector3(side * .088, .176, .06), Vector3(.004, .005, .058), KIT.SLOT_LENS, Basis.IDENTITY, 4, 3)
				b.ellipsoid(Vector3(0, .178, .123), Vector3(.016, .004, .004), KIT.SLOT_LENS, Basis.IDENTITY, 4, 3)
		return b.commit())

## Descritor: {"kind": String, "color": Color (tom do chapéu), "band": Color (fita)}.
static func make_piece(descriptor: Dictionary) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.name = "Acc_" + String(descriptor.kind)
	piece.mesh = mesh(String(descriptor.kind))
	piece.material_override = KIT.material(true)
	piece.set_instance_shader_parameter("accent_color", Color(descriptor.get("color", Color("3a3f45"))))
	piece.set_instance_shader_parameter("inner_color", Color(descriptor.get("band", Color("1d1f22"))))
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return piece
