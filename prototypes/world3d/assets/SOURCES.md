# Origem dos modelos

Cópias locais do próprio projeto, feitas em 21/09/2026. Nenhuma licença adicional foi inferida.

- `dante.glb`: cópia byte a byte de `assets/characters/meshy_dante/dante_grip.glb` do projeto pai. Os PNGs são extraídos do GLB pelo importador. Escala de apresentação de 1,03 para aproximadamente 1,75 m neste mundo.
- `Coupe.scn`: cópia byte a byte de `prototypes/living_cast/CoupeDamagePreparedGeometry.scn`. Contém 38 malhas sem scripts ou dependências externas. Os materiais são reconstruídos com os valores de `_coupe_prepare_runtime_materials()` em `CoupeDamageModel.gd`. O comportamento de dano não foi importado.
- `CivilianModel.gd`: cópia de `prototypes/living_cast/CivilianDriverModel.gd`, alterando apenas a referência à classe base para `CivilianBase.gd`.
- `CivilianBase.gd`: adaptador dos campos e do helper visual `part()` de `world/mountain_pass/WinterResidentModel.gd`, compartilhando SphereMesh e materiais e sem carregar a simulação antiga.

O protótipo não simplifica o GLB do Dante nem a geometria preparada do cupê. Os moradores usam esse modelo original de civil específico; não representam toda a variedade e os comportamentos de AnimatedPedestrian3D.
