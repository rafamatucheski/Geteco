extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"
## Shared metric anchors for visible bays and the persistent vehicle slots.
const CAR := Vector3(6.5,0,0)
const MOTO := Vector3(9.0,0,0)

static func placement(variant: int) -> Vector3:
	# Westgate's tree and Quayside's street occupy the right side of the house.
	return Vector3(-15.6,0,0) if variant in [0,1] else Vector3.ZERO

static func offset(slot := "car", variant := 2) -> Vector3:
	return (MOTO if slot == "motorcycle" else CAR)+placement(variant)

func _ready() -> void:
	# Flush paving: no curb across the drive-in opening or pedestrian route.
	box("GaragePaving",Vector3(5.8,.05,7.6),Vector3(7.8,-.015,.1),"8a8d88")
	for x in [4.95,8.1,10.65]:
		box("BayLine",Vector3(.055,.012,6.6),Vector3(x,.018,.2),"d8d3bf")
	box("BayBackLine",Vector3(5.7,.012,.055),Vector3(7.8,.018,-3.1),"d8d3bf")
	# Rear/side posts leave both vehicle doors and the front fully accessible.
	for x in [5.0,10.6]:
		for z in [-3.55,3.6]:
			var post := box("GaragePost",Vector3(.14,2.85,.14),Vector3(x,1.425,z),"59645f")
			post.set_meta("interior_solid_id","GaragePost")
	box("GarageCanopy",Vector3(5.95,.14,7.65),Vector3(7.8,2.92,.05),"5b6765")
	# Standing-seam metal roofing: real raised seams and finished perimeter.
	# Keep it opaque and present; the city's actor silhouette handles occlusion.
	for seam in 12:
		box("CanopySeam",Vector3(.045,.055,7.65),Vector3(5.05+seam*.5,3.015,.05),"74817c")
	for x in [4.83,10.77]:
		box("CanopyEdge",Vector3(.09,.16,7.75),Vector3(x,2.98,.05),"c7c8bb")
	box("CanopyRearTrim",Vector3(5.95,.16,.1),Vector3(7.8,2.98,-3.8),"c7c8bb")
	for x in [5.0,10.6]: box("GarageBeam",Vector3(.16,.2,7.5),Vector3(x,2.8,.05),"414b46")
	box("GarageFascia",Vector3(5.95,.24,.12),Vector3(7.8,2.89,3.88),"c7c8bb")
	# Bike-sized wheel guide makes the narrow bay legible without decorative text.
	box("MotorcycleGuide",Vector3(.16,.04,1.4),Vector3(9,.035,-.35),"47524e")
