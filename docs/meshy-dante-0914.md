# Dante Meshy: primeira integração, pistola e AK-47

O Dante Meshy é o padrão de gameplay desde a atualização de 14/09/2026 solicitada
para teste. Continua selecionável por `Player.use_meshy_dante` e pelo método
`set_meshy_dante_enabled()`. O argumento `-- --meshy-dante` e o launcher
`tools/start_meshy_dante.ps1` continuam compatíveis, mas não são necessários.
Desde a revisão de trajes (ver `docs/meshy-outfits-0914.md`), todos os trajes
usam o modelo importado, recolorido por região e com acessórios nos ossos.

O GLB original foi preservado em `assets/characters/meshy_dante/dante.glb`.
`dante_grip.glb` é o derivado utilizado: mantém os 17 clipes, 28 ossos e 57.235
triângulos, acrescenta morphs independentes de pegada e reduz normal/ORM para
1024², preservando a cor em 2048². Arquivo passou de 14.031.624 para 10.577.636
bytes. A malha não foi decimada. Reconstrução, na raiz do repositório:

```powershell
python tools/prepare_meshy_dante.py game/assets/characters/meshy_dante/dante.glb game/assets/characters/meshy_dante/dante_grip.glb
```

`MeshyDanteRig.gd` usa os clipes de caminhada, corrida e caminhada para trás.
A fase acompanha a distância percorrida pelo Player; deslocamento horizontal
do quadril é removido para não deslocar o visual em relação à colisão. A parte
superior usa os alvos de `PlayerCombatPose`: mira, porte, recuo e recarga continuam
vinculados ao combate real. IK adapta os dois braços ao comprimento do novo rig.
As malhas antigas ficam ocultas, conservando os nós de referência, origem dos
projéteis, sombras e integração de profundidade do jogador.

Correção da mão da pistola: os eixos do osso não correspondiam aos eixos
anatômicos da palma. A orientação agora considera o roll de cada mão, com
polegar para cima e dedos para a frente, fechando para dentro. Os morphs incluem
também os vértices ligados a `Hand_End`; omiti-los deixava pontas esticadas.
É uma pegada por morph, não articulação individual de cada dedo.

Validação realizada em Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop:

- `tests/test_meshy_dante.gd` renderizado: sem falhas em contato, orientação dos
  polegares, poses finitas, ciclos de corrida, mira, porte, recarga e reconstrução
  de traje. Erro máximo entre referência da palma e alvo: aproximadamente
  0,0000004 unidade. Isso mede o ponto da palma, não ausência universal de clipping.
- `tests/test_player_combat_pose.gd`: 16 armas, zero falhas na regressão do rig padrão.
- `tests/test_garage_weapon_restrictions.gd -- --meshy-dante`: zero falhas.
- `tests/test_projected_interior_contract.gd -- --meshy-dante` renderizado: zero
  falhas; 17 grupos sólidos, 136 aproximações varridas, controles de oclusão e
  visibilidade aprovados. O resultado vale para os ambientes cobertos pelo teste.
- A importação do GLB funcionou. A varredura global do editor terminou com erros
  preexistentes em LandmarksV2.tscn e CarjackedDriver.tscn; não equivale a um build
  completo aprovado.

Comparativo de 30 segundos em HarborGame, 1280×720, VSync e limitador desativados,
mesma rota de caminhada/corrida e seed, após aquecimento:

| Métrica | Dante padrão | Meshy |
| --- | ---: | ---: |
| FPS médio | 50,75 | 50,19 |
| Frame p50 (ms) | 18,13 | 18,11 |
| Frame p95 (ms) | 27,19 | 27,85 |
| Frame p99 (ms) | 31,17 | 32,45 |
| Frame máximo (ms) | 283,70 | 270,23 |

O cenário já fica abaixo da meta provisória de 60 FPS. Não há certificação de
performance. A medição Meshy precede o ajuste final dos eixos das mãos e dos
morphs das pontas; não é uma medição separada dessa revisão visual.

Evidências em `D:/geteco/artifacts/meshy-dante-0914/`: JSONs `baseline-clean` e
`meshy`, logs de garagem/interior, `weapon-review.png`, `pistol-hands.png` e
`dante-pistol-ak47.mp4`. O vídeo é uma prévia isolada de poses, não gravação da
cidade. A primeira medição `baseline.json` foi descartada por concorrência com
importação; usar `baseline-clean.json`.

Pendências históricas da primeira integração (ver os relatórios posteriores): acabamento individual dos dedos e
gatilho, calibração do passo/strafe e transições, poses de armas restantes,
veículos/moto/esqui, efeitos de dano no material importado e otimização da malha.
Os demais clipes importados permanecem disponíveis, mas não foram ligados
automaticamente a ações de gameplay só pelo nome.

Revisão visual de braços e porte da AK: cotovelos orientados para baixo,
clavículas levemente adiantadas, punho livre neutro na recarga e estabilização
do tronco durante a locomoção armada. O porte Meshy da AK usa menos giro lateral
e cano baixo; a pose de mira baixa o apoio da coronha em relação ao alvo antigo,
que ficava acima do ombro. Referência visual consultada:
https://www.thefirearmblog.com/blog/2020/05/20/rifle-sling-positions-ready-positions/

A prévia atual é `dante-natural-arms.mp4`, com caminhada, mira, corrida e recarga
de pistola e AK. O teste de mangas verifica apenas o núcleo convexo do tronco
ponderado pelos ossos da coluna, com tolerância de 3 mm; não certifica todas as
colisões da malha. As medições de performance acima continuam sendo da revisão
anterior, não desta revisão de poses.

Validação final desta revisão: 300 quadros sem falhas no teste de mangas contra
o núcleo do tronco; encaixe das palmas e orientação dos punhos sem falhas em
`ak-reference-motion.log`. Regressão do rig original: 16 armas, zero falhas em
`ak-carry-regression.log`. O cotovelo da AK recebe um alvo mais à frente e para
fora para acomodar o porte baixo sem atravessar a jaqueta.
