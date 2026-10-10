# Pedestres genéricos com corpo do Meshy (10/10/2026)

Segunda etapa depois do piloto do mecânico ([npc-meshy-piloto-20261010.md](npc-meshy-piloto-20261010.md)):
os pedestres da rua, criados em `scripts/Actor.gd`, passam a usar um catálogo de 8 corpos importados do Meshy.
O desempenho foi medido logo em seguida (seção "Desempenho").

## Arquitetura

- `CivilianModel.body_source` (caminho de GLB) liga o corpo importado a qualquer `CivilianModel`; vazio = corpo do
  kit. A lógica ficou em `assets/civilians/MeshyBodyRig.gd`; o antigo `MeshyRigBody` (subclasse) foi removido e o
  `MechanicModel` usa o mesmo mecanismo.
- `assets/civilians/CivilianBodyCatalog.gd` escolhe o corpo pela identidade do pedestre, reaproveitando o sexo e a
  corpulência que o próprio `CivilianModel` sortearia (`_appearance_wardrobe`); a mesma identidade tem sempre o
  mesmo corpo e uma variação de matiz/brilho só das roupas coloridas (`civilian_meshy.gdshader`, instance uniform).
  Guarda-roupa fixo (`wardrobe_overrides`, ex. montanha) continua procedural.
- `scripts/Actor.gd`: 2 linhas (constante + `BODY_CATALOG.apply(model, identity)`). O arquivo tem alterações abertas
  de outra sessão; o commit leva só estas linhas.
- `civilian_meshy.gdshader` responde ao parâmetro `skin_color` com fuligem (alfa 1), que é como
  `BurningActor.char_body` escurece todo corpo civil, então corpo queimado continua funcionando.

## Corpos (`assets/civilians/meshy/pedestrians/`)

| id | quem | build do kit | ossos (de → após poda) |
|---|---|---|---|
| m_medium_a / _b | homem jovem, polo (pele clara / escura) | 1 | 80 → 24 |
| m_heavy_a / _b | homem robusto, polo e bermuda | 2 | 66 → 22 |
| f_medium_a / _b | mulher adulta, cabelo longo, camiseta e jeans | 1 | 32 → 22 |
| f_slim_a / _b | mulher jovem, cabelo curto, camiseta e jeans | 0 | 66 → 22 |

Cada GLB: ~4,1 mil triângulos, ~600 KB, textura 1024. Falta um corpo masculino magro (o build 0 masculino usa o
médio, o build 2 feminino usa o médio). Os 8 foram baixados como pacote "withSkin"; só o `Walking` é usado e a
animação é descartada (a pose vem da IK).

## O que deu errado no meio (e como foi corrigido)

A primeira leva feminina (mulher média e esguia) saiu ruim, como você notou: a manga virava uma lâmina e as pernas
esticavam. Causas, nessa ordem: (1) a malha saiu com braços quase horizontais, palmas para cima e cotovelo dobrado;
(2) numa delas as duas pernas ficaram coladas, o que impede o rig de separar a calça; (3) os marcadores automáticos
do rig do Meshy erravam cotovelo, ombro, virilha e tornozelo, e eu aceitei os da mulher média sem corrigir. Corrigir
só os marcadores não resolveu (a aba de tecido era da malha), então regenerei as duas com prompt mais rígido (2
variações cada, 80 créditos), descartei a variação em estilo desenho, rigue com marcadores revisados um a um e só
então gastei em textura. Verificação feita **no motor**, com mãos no alto, braços abertos, andar, correr e sentar
(`tools/capture_catalog_bodies.gd`), exatamente onde as anteriores falharam.

## Créditos Meshy

Gastos até aqui no trabalho todo: **330 de 800** (saldo 931): mecânico 50; 4 malhas 80 + 8 texturas 80 do primeiro
lote de pedestres; segundo lote feminino 80 (4 malhas) + 40 (4 texturas). Remesh e rig não cobram.

## Validação

- `tests/test_pedestrian_catalog.gd`: por corpo (um só mesh visível, sem AnimationPlayer, ≤ 26 ossos, 3.500–4.600
  triângulos, altura 1,76 ± 0,05, pés no chão, sempre um pé apoiado ao andar, nenhum osso a mais de 2 m, mãos no
  alvo < 0,14 m, bacia desce ao sentar, juntas das mortes do Mixamo) + escolha determinística, 400 identidades
  usando os 8 corpos, sexo compatível, guarda-roupa fixo procedural, 24 `Actor` reais com 1 modelo cada e todos com
  corpo do Meshy, montanha procedural. Todos passam; o erro de alcance das mãos fica entre 0,06 e 0,13 m (o corpo
  `f_medium_a` está a 6 mm do limite de 0,14 m).
- Regressão que continua verde: `test_mixamo_npc_death` (17), `test_hit_reaction`, `test_hit_presentation_lifecycle`,
  `test_meshy_mechanic_body` (17), `test_maciota_world`, `test_maciota_transition_safety` (37, inclui invulnerabilidade
  do mecânico e restrição de armas), `test_bridge_approach_terrain`, `test_native_driving`, `cold/test_admission`.
  `test_regions` continua falhando como antes (preexistente).
- Jogo real (`tests/diagnostics/duplicate_bodies_probe.gd`): 22 a 24 corpos do Meshy visíveis por ponto amostrado, sem
  corpo duplicado, sem malha antiga visível e sem atores sobrepostos. Capturas em `evidence/npc-meshy/closeup/`.

## Desempenho

RTX 4060 Laptop, Vulkan Mobile, 1280×720, VSync e limite de FPS desligados só nos processos de medição, 5–10 s de
aquecimento separado de 30 s de amostra; meta provisória de 60 FPS / 16,67 ms e tolerância de 5% em p95/p99. A
comparação usa o interruptor `CivilianBodyCatalog.enabled` / `GETECO_NO_MESHY_BODIES=1` (nenhum arquivo foi trocado).
Durante a medição não havia outro Godot em uso nem a aba do Meshy animando (a primeira rodada do jogo real começou
com a aba ainda animando; ela é a mais fraca e fica registrada).

**Palco com 80 pedestres andando** (`tests/measure/measure_pedestrian_crowd.gd`, 8 rodadas alternadas nas duas
ordens, uma do corpo antigo descartada como ruído, com p99 de 14,9 ms, restando 7):

| | p50 | p95 | p99 | draw calls |
|---|---|---|---|---|
| procedural | ~4,17 ms | ~4,75 | ~5,25 | 2.086 |
| Meshy | ~4,37 ms | ~4,97 | ~5,42 | 166 |
| diferença | +4,8% | +4,6% | +3% | −92% |

É o pior caso (todos os 80 à vista, parados na câmera): cerca de 2,5 µs a mais por pedestre, no CPU, ainda a
~230 FPS. Fica em +4,6–4,8%, abaixo do limite de 5% mas sem folga.

**Jogo real, Main.tscn** (`tests/measure/measure_pedestrian_game.gd`, 6 processos alternados new/old/old/new/new/old,
3 pontos, câmera do gameplay parada; 12 a 23 pedestres do Meshy entre ~50 corpos visíveis). Mediana de 3 processos:

| ponto | p50 antigo → novo | p95 | p99 | draw calls |
|---|---|---|---|---|
| rua 166/111 | 8,16 → 5,55 ms | 16,3 → 10,9 | 32,3 → 15,9 | 730 → 609 |
| início | 7,46 → 7,08 ms | 12,30 → 12,28 | 17,2 → 16,9 | 657 → 569 |
| Vértice | 4,84 → 4,88 ms | 11,89 → 11,89 | 14,8 → 14,9 | 298 → 304 |

Leitura honesta: **não há regressão detectável** no jogo real; a melhora aparente da rua (−32%) vem de dois
processos do corpo antigo terem pegado picos (p50 9,2 e 8,2 ms) e **não deve ser atribuída ao corpo novo**. O ruído
entre processos do mesmo corpo é de até 2×, com picos acima de 33 ms em ambas as condições (antigo: 41, 26 e 57
quadros; novo: 37 e 45). Máximos de 90 a 800 ms em um processo antigo e um novo são travadas de primeira visita/streaming,
que existem nas duas condições.

**Estado: aprovado só para o que foi medido** — pedestres parados na câmera, 3 pontos de Harbor/Vértice, 1280×720
nesta GPU, de dia. **Não medido:** corrida de carro em velocidade, caos com polícia, noite, chuva, pontes/túnel,
população maior que ~50 corpos, outras GPUs. Otimização possível se o palco com 80 incomodar: trocar o nó
`PoseDriver` de cada pedestre por um único coordenador (80 chamadas `_process` por quadro é o custo que sobra).

## Pendências

- Skate: `SkatePose` (arquivo com trabalho de outra sessão) usa `KIT.THIGH/ANKLE_HEIGHT` e `PELVIS_Y` fixos nas poses
  de skatista NPC; com o corpo do Meshy os pés ficam cerca de 6 cm mais fundos/altos no shape. Trocar por
  `model.thigh_len`, `model.ankle_height`, `model.pelvis_y` (já existem) quando aquela sessão terminar.
- Pedestres da montanha, uniformes e demais famílias seguem procedurais; acessórios (chapéu, mochila, óculos) do kit
  não existem nos corpos importados.
- Textura traz riscos finos de "desgaste" (prompt) nas camisas; mãos sem curvatura dos dedos; só 8 aparências base
  (+ matiz das roupas). Corpo masculino magro e idosos ainda não existem.
