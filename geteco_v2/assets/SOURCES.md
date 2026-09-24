# Origem dos modelos

Cópias locais do próprio projeto, feitas em 21/09/2026. Nenhuma licença adicional foi inferida.

- `dante.glb`: cópia byte a byte de `assets/characters/meshy_dante/dante_grip.glb` do projeto pai. Os PNGs são extraídos do GLB pelo importador. Escala de apresentação de 1,03 para aproximadamente 1,75 m neste mundo.
- `Coupe.scn`: cópia byte a byte de `prototypes/living_cast/CoupeDamagePreparedGeometry.scn`. Contém 38 malhas sem scripts ou dependências externas. Os materiais são reconstruídos com os valores de `_coupe_prepare_runtime_materials()` em `CoupeDamageModel.gd`. O comportamento de dano não foi importado.
- `CivilianModel.gd`: cópia de `prototypes/living_cast/CivilianDriverModel.gd`, alterando apenas a referência à classe base para `CivilianBase.gd`.
- `CivilianBase.gd`: adaptador dos campos e do helper visual `part()` de `world/mountain_pass/WinterResidentModel.gd`, compartilhando SphereMesh e materiais e sem carregar a simulação antiga.

O protótipo não simplifica o GLB do Dante nem a geometria preparada do cupê. Os moradores usam esse modelo original de civil específico; não representam toda a variedade e os comportamentos de AnimatedPedestrian3D.

## Áudio de combate copiado do V1 (rodada de paridade de combate)

Áudio do menu: `audio/menu/harbor_night_menu.wav` no projeto V2 é cópia byte a byte do mesmo caminho no V1. Acrescentado para corrigir referência a recurso ausente em `ui/MenuAudio.gd`; hashes SHA-256 comparados. Importação e reprodução pelo Godot ainda não verificadas nesta correção.

Cópias byte a byte, feitas depois de 21/09/2026, de `assets/gameplay/audio/`. Três takes por família; os takes 3–4 do V1 não foram copiados. Não foram importados `.import` (o jogo lê os WAVs por `AudioStreamWAV.load_from_file`).

- `reload/<arma>_{0..2}.wav` (11 armas): de `audio/reload/`. Fontes e licença CC0 em `reload/CREDITS.md` (copiado).
- `impact_{flesh,metal,concrete,wood,glass}_{0..2}.wav`: de `audio/combat/<material>_{0..2}.wav`.
- `rpg_{0..2}.wav`: de `audio/acoustic/rpg_launch_{0..2}.wav`.
- `suppressed_{pistol,smg,shotgun,ak47,m4a1,hunting_rifle}_{0..2}.wav`: de `audio/combat/arsenal_v2/`.

`gameplay/CombatAudio.gd` reescreve as fórmulas procedurais V1 (golpe de punho, faca, taco, lança-chamas, arremesso de granada) com semente fixa em vez de `randf`.
- `hurt_{0..2}.wav`: cópia de `audio/reactions/hurt_{0..2}.wav` (gemido de dor, CC0; créditos em `HURT_CREDITS.md`).
