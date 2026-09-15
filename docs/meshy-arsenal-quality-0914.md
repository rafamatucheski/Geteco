# Arsenal no Dante Meshy — 14/09/2026

O alvo desta revisão é o personagem importado em
`assets/characters/meshy_dante/dante_grip.glb`, ativado por `--meshy-dante`.
As poses novas ficam nos ramos Meshy; o construtor compartilhado de armas também
fornece os modelos melhorados aos demais locais que exibem o arsenal.

As 15 armas receberam acabamento de bordas, materiais e detalhes de acordo com
o tipo. A AK tem carregador com silhueta curva e coronha modelada. Foram
acrescentados detalhes de miras, empunhaduras, guardas e bocas dos canos;
granada e soco-inglês usam anéis vazados. Peças estáticas são agrupadas por
material, enquanto Pump, LoadedRocket e ReloadCylinder permanecem animáveis.
Não foram alterados dano, alcance ou cadência das armas.

Pistolas, armas longas, lançadores e armas de corpo a corpo têm ajuste de alcance,
punhos e dedos para o Meshy. O braço de apoio conserva uma margem de flexão para
evitar que a manga atravesse o tronco. Transições de locomoção não reintroduzem
a rotação anterior dos braços já resolvidos por IK.

Granada, taco e machado usam `MeshyMeleePose.gd`: arremesso por cima, varredura
lateral e golpe descendente, respectivamente. As fases do machado e do taco
mantêm os instantes de impacto existentes. No Meshy, a granada nasce após 0,20 s,
sincronizada com a soltura; a mão abre e a granada deixa de aparecer nela. Entrar
em área sem armas, morrer ou trocar de arma antes da soltura cancela o arremesso
e devolve a unidade reservada. O rig original mantém a soltura imediata.

## Validação

- `test_meshy_dante.gd -- --arsenal`: 15 armas, poses de porte, mira, corrida,
  recarga/ataque, contato das palmas, orientação dos punhos e troca de roupa;
  zero falhas. Captura em `--capture-motion`: 2.250 quadros.
- `tools/check_meshy_clearance.py artifacts/arsenal-quality-0914`: zero falhas.
  Escopo: mangas versus núcleo convexo do tronco ponderado pelos ossos da coluna,
  tolerância de 3 mm. Não certifica toda a superfície do personagem ou toda
  possível combinação de animações.
- `test_meshy_grenade_release.gd`: nascimento no tempo de soltura, consumo de uma
  unidade, cancelamento em área sem armas e na troca de arma, com restituição;
  zero falhas.
- `test_garage_weapon_restrictions.gd -- --meshy-dante`: zero falhas na garagem
  real, inclusive proteção dos personagens essenciais.
- `test_player_combat_pose.gd`: regressão do rig original, 16 armas, zero falhas.
- `test_weapon_effects_realism.gd`: zero falhas. O teste de melee legado também
  encerra seus casos sem falhas, mas relata recursos/RIDs pendentes ao desmontar
  a fixture; não equivale a uma verificação geral de ausência de vazamentos.

As prévias isoladas estão em `artifacts/arsenal-quality-0914`: `pose-*.png`,
`models-after.png`, `meshy-arsenal.mp4` e `meshy-granada-taco-machado.mp4`.
São capturas do rig real em uma cena de revisão, não gravações de combate na cidade.
O teste de soltura usa a ação nativa e o projétil real separadamente.

## Performance

Comparativo em HarborGame renderizado, checkpoint downtown, RTX 4060 Laptop,
Godot 4.7.2 Mobile, 1280×720, seed 12092026, dia sem chuva, VSync/limite desligados,
10 s de aquecimento e 30 s de amostra, mesma sequência de 15 armas. Saves isolados
na pasta de evidências. Meta provisória: 60 FPS; aumento acima de 5% em p95/p99
exige investigação. Relatórios em `before/driving.json` e `after/driving.json`.

| Métrica | Antes | Depois |
| --- | ---: | ---: |
| FPS médio | 53,37 | 54,63 |
| p50 (ms) | 17,465 | 17,142 |
| p95 (ms) | 26,060 | 25,113 |
| p99 (ms) | 29,064 | 30,745 |
| Máximo (ms) | 81,654 | 75,154 |
| Quadros acima de 33,3 ms | 2 | 9 |
| Quadros acima de 66,7 ms | 2 | 2 |

A meta provisória de 60 FPS já não era atendida no baseline. O p99 aumentou
5,78% na primeira amostra depois; foi solicitada uma amostra finita de confirmação
com código e condições iguais, em `after-confirm/driving.json`.

A confirmação mediu 53,81 FPS, p50 17,351 ms, p95 25,339 ms, p99 30,202 ms,
máximo 76,378 ms, 12 quadros acima de 33,3 ms e 2 acima de 66,7 ms. O p99 ficou
3,92% acima do baseline: o aumento acima do limiar de 5% não se repetiu. Há
variação na cauda dos frames e a meta de 60 FPS permanece não atendida; não há
certificação geral de performance. Nenhuma configuração de qualidade do jogo
foi reduzida para produzir o comparativo.

A revisão adicional `--review-angles` gerou vistas frontal, lateral e traseira
do Meshy com as 15 armas (`angles-*.png`) e terminou sem falhas de empunhadura.
