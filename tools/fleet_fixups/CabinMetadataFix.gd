extends RefCounted
## Offline authoring contract: measure the actual front cabin independently of
## consolidated surfaces. Values from cabin-probe.json's unbatched glazing.
## No geometry, materials, physics or opacity changes.
const SPECS := {
	"medic_box": {"kind":"van", "floor":.32, "belt":1.01298892498016,
		"roof":1.68701112270355, "hw":.944999992847443,
		"wz0":-1.64469611644745, "wz1":-1.44000005722046,
		"rear":-.519999980926514, "rear_top":-.519999980926514},
	"beach_cabriolet": {"kind":"sport", "open_top":true, "floor":.08,
		"belt":.819999992847443, "roof":1.32500004768372,
		"hw":.699999988079071, "wz0":-.879999995231628,
		"wz1":-.300000011920929, "rear":-.300000011920929,
		"rear_top":-.300000011920929}
}

static func apply(model: Node3D, id: String) -> void:
	if not SPECS.has(id): return
	var spec: Dictionary = model.get_meta("vehicle_interior_spec",{}).duplicate(true)
	spec.merge(SPECS[id],true)
	model.set_meta("vehicle_interior_spec",spec)
	model.set_meta("cabin_metadata_revision",1)
