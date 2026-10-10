# Pedestres genéricos com corpo do Meshy (10/10/2026)

Segunda etapa depois do piloto do mecânico ([npc-meshy-piloto-20261010.md](npc-meshy-piloto-20261010.md)):
os pedestres da rua, criados em `scripts/Actor.gd`, passam a usar um catálogo de 8 corpos importados do Meshy.
Desempenho **não** foi medido nesta etapa (ver "Pendências").

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

## Pendências

- **Desempenho dos pedestres: não medido.** É a próxima etapa pedida.
- Skate: `SkatePose` (arquivo com trabalho de outra sessão) usa `KIT.THIGH/ANKLE_HEIGHT` e `PELVIS_Y` fixos nas poses
  de skatista NPC; com o corpo do Meshy os pés ficam cerca de 6 cm mais fundos/altos no shape. Trocar por
  `model.thigh_len`, `model.ankle_height`, `model.pelvis_y` (já existem) quando aquela sessão terminar.
- Pedestres da montanha, uniformes e demais famílias seguem procedurais; acessórios (chapéu, mochila, óculos) do kit
  não existem nos corpos importados.
- Textura traz riscos finos de "desgaste" (prompt) nas camisas; mãos sem curvatura dos dedos; só 8 aparências base
  (+ matiz das roupas). Corpo masculino magro e idosos ainda não existem.
