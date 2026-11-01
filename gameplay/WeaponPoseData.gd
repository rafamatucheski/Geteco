extends RefCounted

## Só apresentação: dano, munição e cadência de tiro continuam pertencendo a Player.
## Os braços usam os comprimentos existentes do rig. A orientação da arma é independente do
## antebraço para que erguer o cotovelo nunca aponte o cano para o céu.
const PROFILES := {
	"pistol_suppressed": [Vector3(0.19, 0.96, -0.27), Vector3.ZERO, 0.09, 16.0],
	"smg_compact": [Vector3(0.07, 0.94, -0.16), Vector3(-0.05, 0.0, -0.12), 0.07, 19.0],
	"smg_tactical": [Vector3(0.07, 0.94, -0.16), Vector3(-0.05, 0.0, -0.12), 0.05, 22.0],
	"shotgun_auto": [Vector3(0.05, 0.98, -0.10), Vector3(-0.04, 0.0, -0.20), 0.17, 11.0],
	"katana": [Vector3(0.18, 0.95, -0.25), Vector3.ZERO, 0.0, 16.0],
	"sword_shield": [Vector3(0.18, 0.95, -0.25), Vector3.ZERO, 0.0, 16.0],
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

# Centros, no espaço da malha, das empunhaduras reais, não do receptor nem do cano.
const GRIPS := {
	"pistol_suppressed": Vector3(0, -0.03, 0.02),
	"smg_compact": Vector3(0, -0.05, 0.03), "smg_tactical": Vector3(0, -0.05, 0.03),
	"shotgun_auto": Vector3(0, -0.04, 0.07),
	"katana": Vector3(0, 0, 0.04), "sword_shield": Vector3(0, 0, 0.04),
	"pistol": Vector3(0, -0.03, 0.02), "magnum": Vector3(0, -0.05, 0.03),
	"smg": Vector3(0, -0.05, 0.03), "shotgun": Vector3(0, -0.04, 0.07),
	"sawed_off": Vector3(0, -0.05, 0.05), "ak47": Vector3(0, -0.06, 0.04),
	# Rifle de caça: mão embaixo da empunhadura (o "pistol grip" da coronha desce até
	# y −0,085). No centro dela o pulso direito ficava 4–5 cm dentro da base da coronha.
	"m4a1": Vector3(0, -0.06, 0.04), "hunting_rifle": Vector3(0, -0.075, 0.06),
	"rpg": Vector3(0, 0, -0.10), "flamethrower": Vector3(0, -0.05, 0.03),
	"grenade": Vector3(0, 0, -0.10), "knife": Vector3(0, 0, 0.025),
	# Taco e machado com a pegada de quem bate pelo lado direito: mão ESQUERDA no pé
	# do cabo (`SUPPORT_GRIPS`) e a direita logo acima. Com a direita embaixo o braço
	# esquerdo cruzava por cima do direito em quase todo golpe.
	"axe": Vector3(0, 0, 0.015),
	# Soqueira sobre os nós dos dedos do punho fechado, 4 cm adiante do ponto da palma
	# (no centro da palma ela abraçava o dorso da mão junto ao pulso).
	"knuckles": Vector3(0, 0, 0.04),
	"bat": Vector3(0, 0, 0.035),
	"fists": Vector3.ZERO,
}
const SUPPORT_GRIPS := {
	"pistol_suppressed": Vector3(-0.038, -0.033, 0.02),
	"smg_compact": Vector3(-0.02, -0.02, -0.15), "smg_tactical": Vector3(-0.02, -0.02, -0.15),
	"shotgun_auto": Vector3(-0.02, -0.025, -0.16),
	"pistol": Vector3(-0.038, -0.033, 0.02),
	# Empunhadura compacta de pistola: a palma de apoio envolve a mão que atira, não os canos.
	"sawed_off": Vector3(-0.038, -0.053, 0.05),
	# Mão esquerda no fim do cabo, junto ao calcanhar (vai até 0,16): mais acima, o pé
	# do cabo entrava no peito quando as mãos passavam junto ao tronco.
	"axe": Vector3(0, 0, 0.135),
	"magnum": Vector3(-0.035, -0.05, 0.03), "smg": Vector3(-0.02, -0.02, -0.15),
	"shotgun": Vector3(-0.02, -0.025, -0.16), "ak47": Vector3(-0.02, -0.015, -0.15),
	"m4a1": Vector3(-0.02, -0.012, -0.15), "hunting_rifle": Vector3(-0.025, -0.025, -0.14),
	"rpg": Vector3(-0.012, 0.0, -0.22), "flamethrower": Vector3(-0.012, -0.055, -0.14),
	"bat": Vector3(0, 0, 0.10),
}
# Faces traseiras das coronhas, incluindo a coronha de arame da SMG compacta.
const STOCK_ENDS := {"smg_compact": Vector3(0, 0.03, 0.19), "smg_tactical": Vector3(0, 0.03, 0.19), "shotgun_auto": Vector3(0, -0.04, 0.27), "smg": Vector3(0, 0.03, 0.19), "shotgun": Vector3(0, -0.04, 0.27), "ak47": Vector3(0, -0.02, 0.29), "m4a1": Vector3(0, 0, 0.25), "hunting_rifle": Vector3(0, -0.02, 0.19)}

## Constantes de pose do rig (WeaponRigPose e auxiliares WeaponRigReload/Stance/Grips), saídas de
## WeaponRigPose.gd em 01/11 sem mudar valor nem ordem; as lidas de fora são reexportadas lá.
## Escala do Dante V2 / escala do Dante V1 sobre o mesmo GLB (Actor.gd: 1,03;
## V1 MeshyDanteRig.SCALE: 0,82). Também vale para o modelo da arma: na V1 a arma
## não era escalada junto com o corpo, então relativamente ao Dante ela era esse
## tanto maior do que o modelo cru na V2.
const V1_TO_V2 := 1.03 / 0.82
const HANDGUNS := ["pistol", "pistol_suppressed", "magnum", "sawed_off"]
const LONG_GUNS := ["smg", "smg_compact", "smg_tactical", "shotgun", "shotgun_auto", "ak47", "m4a1", "hunting_rifle"]
const FIREARMS := ["pistol", "pistol_suppressed", "magnum", "smg", "smg_compact", "smg_tactical", "shotgun", "shotgun_auto", "sawed_off", "ak47", "m4a1", "hunting_rifle", "rpg", "flamethrower"]
## V1 `_cross_grip`: o cabo atravessa a palma em vez de ficar na vertical.
const CROSS_GRIP := ["axe", "knife", "bat"]
const CROSS_GRIP_LEFT := ["smg", "smg_compact", "smg_tactical", "shotgun", "shotgun_auto", "ak47", "m4a1", "hunting_rifle"]
## Ombro de referência do `MeshyMeleePose` (espaço V1) para o balanço do cabo ao andar.
const MELEE_SHOULDER := Vector3(0.23, 1.18, -0.015)
const GRENADE_RELEASE := 0.20
const GRENADE_RECOVERY := 0.70
## Instante de contato nas trajetórias abaixo; Gameplay usa o mesmo relógio.
const MELEE_CONTACT := {"fists": 0.14, "knuckles": 0.16, "knife": 0.18, "bat": 0.36, "axe": 0.38, "katana": 0.26, "sword_shield": 0.26}
## Repouso dos ossos no espaço do esqueleto do `dante.glb` (medido no GLB; o
## modelo é girado 180° dentro do Actor). Com eles o ombro sai da mesma conta
## que a V1 fazia em `sync_shoulders`: clavícula protraída 0,20 rad e tronco
## girado pela postura — independentemente da ordem em que o esqueleto é lido.
const SKELETON_SCALE := 1.03
const SK_SPINE := Vector3(0.003647, 1.28616, -0.0122)
const SK_CLAVICLE := {"Right": Vector3(-0.032291, 1.315796, -0.045289), "Left": Vector3(0.037389, 1.319443, -0.045306)}
const SK_ARM := {"Right": Vector3(-0.176041, 1.315796, -0.051777), "Left": Vector3(0.172361, 1.319443, -0.052288)}
const KNUCKLE_DURATION := 0.32
## Hit-stop (congelamento curto do golpe no impacto) por arma, em segundos. É o
## que dá peso ao contato nos jogos de ação: o braço "trava" no alvo por 3–5
## quadros antes do follow-through. Golpe pesado (fim da sequência) segura mais.
const HIT_STOP := {"fists": 0.045, "knuckles": 0.055, "knife": 0.04, "bat": 0.075, "axe": 0.085, "katana": 0.055, "sword_shield": 0.055}
const HEAVY_HIT_STOP := 0.035
## Velocidade angular máxima das articulações do braço (rad/s) durante o golpe.
## O padrão do Actor (18) é o da prontidão; um direto real passa de 25 no cotovelo.
const STRIKE_ARM_RATE := 30.0
## Fração do curso do ferrolho/telha gasta puxando; o resto é o retorno da mola.
const RACK_PULL := 0.72
## Parte da torção da pegada de taco/machado que o antebraço assume (o resto fica
## no pulso); ver `Actor._solve_combat_arm`.
const FOREARM_SHARE := 0.8
## Rolagem máxima da arma em torno do próprio cabo (rad/s; ver `MeleeMoveset.swing_basis`).
const BLADE_ROLL_RATE := 20.0
## Cabeça do Dante no espaço V1 do Actor, medida nos ossos realizados (Head + 40%
## até head_end) com a guarda parada; inclinar 0,1 rad para trás leva a cabeça
## ~6 cm para trás (coeficiente medido, não o braço de alavanca geométrico). A malha
## da cabeça com cabelo/barba cabe em 0,14 m = 0,111 V1. Folga mínima garantida =
## HEAD_CLEARANCE + CLEAR_SOFT/2 (0,166 V1, 5,5 cm de margem além do raio) porque,
## perto do limite de alcance, a mão real fica 3–4 cm atrás do alvo.
const HEAD_CENTER := Vector3(0.0, 1.243, -0.065)
## Carregar no ombro (V1): punho à frente do peito, à direita; a cabeça da arma vai
## para trás por cima do ombro direito, por fora da cabeça do Dante.
const CARRY_HAND := Vector3(0.20, 0.90, -0.15)
const CARRY_HEAD := Vector3(0.25, 0.82, 0.5)
const CARRY_POLE := Vector3(0.9, -1.5, 0.3)
## Fuzil apoiado: giro do tronco na mira, bolso da coronha relativo ao ombro (x para
## fora, y para cima, z para a frente do peito; espaço V1) e alcance da palma esquerda
## a partir do ombro (0,41 m no V2, medido: pedindo 0,44 o IK ficava 2–3 cm curto). O
## apoio não recua além de z = −0,03 da empunhadura (frente do encaixe do carregador).
const STOCK_STANCE := -0.75
## Fração do saque a partir da qual a arma longa aparece na mão.
const EQUIP_SHOW := 0.6
const EQUIP_SHOW_HANDGUN := 0.15
## Lança-chamas: o apoio fica longe da empunhadura e o antebraço esquerdo ainda subia
## por dentro do corpo da arma quando ela aparecia a 0,6 do saque (4,5 cm vindo dos punhos).
const EQUIP_SHOW_BY_ID := {"flamethrower": 0.95}
const STOCK_POCKET := Vector3(-0.02, -0.025, 0.06)
const LEFT_PALM_REACH := 0.41 / (1.03 / 0.82)
const SUPPORT_MIN_REACH_Z := -0.03
## Rifle de caça: o receptor tem ferrolho e luneta logo à frente da empunhadura; a mão
## deslizando até ali enfiava os dedos neles (4,5 cm). Para no início do guarda-mão.
const SUPPORT_MIN_REACH_Z_BY_ID := {"hunting_rifle": -0.14}
## Avanço do bolso por seno da inclinação da arma (altura do bico da coronha, V1).
const STOCK_TOE := 0.08
## Rifle de caça: coronha curta (15,5 cm da empunhadura ao fim) e sem empunhadura de
## pistola; a base da coronha encostava 4–5 cm no antebraço direito logo atrás do pulso.
## Medido em 2026-10-06: bolso 3 cm mais baixo na mira e na recarga, 3 cm mais alto
## com a arma baixa (a ponta da coronha sai de cima do antebraço).
## M4A1: a coronha retrátil (a4634240) sobe em degrau até y 0,04 do modelo em z 0,17, e a
## quina de dentro desse degrau entrava 3,7–4,3 cm na gola/peito direito mirando andando
## ou de lado. 1,5 cm mais baixo e 1 cm à frente (medido em 2026-10-19: mira, tiro e recarga,
## parado e andando, ≤ 2,0 cm, só a base da coronha apoiada no peito; só 1,5 cm mais baixo,
## andando e atirando o topo do receptor encostava na lapela).
const STOCK_POCKET_SHIFT := {"hunting_rifle": Vector3(0, -0.03, 0), "m4a1": Vector3(0, -0.015, 0.01)}
const STOCK_POCKET_SHIFT_READY := {"hunting_rifle": Vector3(0, 0.03, 0)}
const STOCK_ELBOW := Vector3(1.4, -1.2, 0.3)
const RELOAD_LEFT_POLE := Vector3(-0.2, -1.5, 1.0)
## Mão direita no lança-foguetes apoiado (V1): tubo com o fundo no topo do ombro
## (y 1,44 no V2) e a lateral por fora da cabeça (x ≤ 0,12 no V2).
const RPG_SHOULDER := Vector3(0.145, 1.115, -0.26)
## Boca do tubo do lança-foguetes no espaço do modelo (eixo 8 cm acima das empunhaduras;
## a ogiva encaixada vai de z −0,31 a −0,49).
const RPG_MUZZLE := Vector3(0.0, 0.08, -0.31)
## Foguete na recarga: a mão esquerda o pega no cinto em RPG_ROCKET_GRAB e o encaixa
## entre RPG_ROCKET_SEAT.x e .y (fração da recarga); o centro da ogiva fica 9 cm à
## frente da boca quando encaixado (`ArsenalWeapon3D`, "LoadedRocket").
const RPG_ROCKET_GRAB := 0.27
const RPG_ROCKET_SEAT := Vector2(0.50, 0.62)
const RPG_ROCKET_CENTER := 0.09
## Palma na lateral da ogiva voltada para o ombro esquerdo (raio 5,6 cm + palma), não no
## eixo: com a palma no centro, punho e antebraço ficavam até 5 cm dentro da ogiva no
## encaixe e na volta ao tubo.
const RPG_ROCKET_SIDE := 0.07
const RPG_POLE := Vector3(0.4, -1.5, -0.2)
## Submetralhadora na recarga rolada como AK/M4: coronha curta, o receptor fica rente
## ao peito, e a −0,38 o topo dele entrava 5 cm na jaqueta andando (medido: −0,60 → 3 cm).
const SMG_RELOAD_ROLL := -0.60
const KNUCKLE_RUN_POLE := Vector3(0.45, -1.5, 0.9)
const HEAD_ABOVE_SPINE := 0.6
const HEAD_CLEARANCE := 0.146
## Carregando parado: só a cabeça com cabelo (+2 cm de margem com a faixa suave).
## Com a margem do golpe a arma saía do ombro e atravessava o peito.
const HEAD_CLEARANCE_CARRY := 0.111
const CLEAR_SOFT := 0.04
const WEAPON_RADIUS := {"bat": 0.036, "axe": 0.048}
