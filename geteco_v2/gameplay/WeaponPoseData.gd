extends RefCounted

## Presentation only: damage, ammo and fire cadence remain owned by Player.
## Arms use the existing rig lengths. Gun orientation is independent of the
## forearm so raising the elbow never points the barrel into the sky.
const PROFILES := {
	"pistol": [Vector3(0.19, 0.96, -0.27), Vector3.ZERO, 0.11, 15.0],
	"magnum": [Vector3(0.17, 0.99, -0.26), Vector3(-0.10, -0.04, 0.01), 0.22, 9.0],
	"smg": [Vector3(0.07, 0.94, -0.16), Vector3(-0.05, 0.0, -0.12), 0.055, 21.0],
	"shotgun": [Vector3(0.05, 0.98, -0.10), Vector3(-0.04, 0.0, -0.20), 0.24, 8.0],
	"sawed_off": [Vector3(0.19, 0.84, -0.23), Vector3.ZERO, 0.28, 8.0],
	"ak47": [Vector3(0.04, 1.0, -0.12), Vector3(-0.05, 0.0, -0.18), 0.10, 15.0],
	"m4a1": [Vector3(0.04, 1.02, -0.12), Vector3(-0.05, 0.0, -0.16), 0.07, 18.0],
	"hunting_rifle": [Vector3(0.10, 1.0, -0.34), Vector3(-0.025, -0.012, -0.20), 0.18, 9.0],
	"rpg": [Vector3(0.16, 1.07, -0.08), Vector3(-0.12, -0.06, -0.16), 0.18, 7.0],
	"flamethrower": [Vector3(0.06, 0.84, -0.10), Vector3(-0.08, 0.0, -0.20), 0.018, 18.0],
	"grenade": [Vector3(0.23, 0.92, -0.12), Vector3.ZERO, 0.0, 12.0],
	"axe": [Vector3(0.20, 0.88, -0.16), Vector3.ZERO, 0.0, 10.0],
	"knife": [Vector3(0.21, 0.86, -0.16), Vector3.ZERO, 0.0, 14.0],
	"knuckles": [Vector3(0.22, 0.72, -0.06), Vector3.ZERO, 0.0, 14.0],
	"bat": [Vector3(0.18, 0.95, -0.10), Vector3(-0.04, -0.02, 0.08), 0.0, 11.0],
	"fists": [Vector3(0.24, 0.68, -0.02), Vector3.ZERO, 0.0, 12.0],
}

# Mesh-space centres of the actual handles, not the receiver or barrel.
const GRIPS := {
	"pistol": Vector3(0, -0.03, 0.02), "magnum": Vector3(0, -0.05, 0.03),
	"smg": Vector3(0, -0.05, 0.03), "shotgun": Vector3(0, -0.04, 0.07),
	"sawed_off": Vector3(0, -0.05, 0.05), "ak47": Vector3(0, -0.06, 0.04),
	"m4a1": Vector3(0, -0.06, 0.04), "hunting_rifle": Vector3(0, -0.035, 0.035),
	"rpg": Vector3(0, 0, -0.10), "flamethrower": Vector3(0, -0.05, 0.03),
	"grenade": Vector3(0, 0, -0.10), "knife": Vector3(0, 0, 0.025),
	"axe": Vector3(0, 0, 0.105), "knuckles": Vector3.ZERO,
	"bat": Vector3(0, 0, 0.10),
	"fists": Vector3.ZERO,
}
const SUPPORT_GRIPS := {
	"pistol": Vector3(-0.038, -0.033, 0.02),
	"sawed_off": Vector3(-0.012, -0.018, -0.055),
	"axe": Vector3(0, 0, -0.095),
	"magnum": Vector3(-0.035, -0.05, 0.03), "smg": Vector3(-0.02, -0.02, -0.15),
	"shotgun": Vector3(-0.02, -0.025, -0.16), "ak47": Vector3(-0.02, -0.015, -0.15),
	"m4a1": Vector3(-0.02, -0.012, -0.15), "hunting_rifle": Vector3(-0.025, -0.025, -0.14),
	"rpg": Vector3(-0.012, 0.0, -0.22), "flamethrower": Vector3(-0.012, -0.055, -0.14),
	"bat": Vector3(0, 0, 0.035),
}
# Rear faces of the stocks, including the compact SMG wire stock.
const STOCK_ENDS := {"smg": Vector3(0, 0.03, 0.19), "shotgun": Vector3(0, -0.04, 0.27), "ak47": Vector3(0, -0.02, 0.29), "m4a1": Vector3(0, 0, 0.25), "hunting_rifle": Vector3(0, -0.02, 0.19)}
