# Armas em movimento: soqueira correndo e M4A1 mirando andando (19/10/2026)

Continuação de `evidence/pose-armas-20261019/` (924d8898). Lá ficaram de fora três falhas de
`tests/test_weapon_locomotion.gd` (320/323), idênticas no HEAD:

- `knuckles correndo`: "braço na frente do rosto Left ×18";
- `m4a1 mirando andando`: arma na pele 0,042 m no quadro 48 (limite 0,035);
- `m4a1 mirando de lado`: 0,036 m no quadro 48.

Nenhuma das duas vem da mudança do quadril parado de 5e7d0360 (12/10): as duas são em
movimento, onde `body_bob` vem do clipe e o repouso não entra.

## Soqueira correndo: o teste não fazia o que o jogo faz

Correndo sem golpe nem guarda, a soqueira pede `follow_clip` (b309807a, 07/10): os punhos vão
para a palma que o clipe de corrida traz. No jogo, `Actor` guarda essas palmas em `_clip_palms`
logo depois da locomoção, antes de a camada de arma endireitar a coluna. O teste (e a tira
`capture_melee_filmstrip.gd`) chama `_pose_locomotion` direto, `_clip_palms` fica vazio e o
padrão era `combat_palm_position` lido no meio de `_apply_combat_weapon_pose`, com a coluna já
na postura armada: o braço do clipe, feito para um tronco inclinado para a frente, girava junto
com o tronco endireitado e a mão subia.

Medido por quadro (diagnóstico em `diagnostico.patch`, `_face_detail`), correndo a 6,5 m/s:

| | palma esquerda à frente (y, z) | quadros com braço no rosto |
|---|---|---|
| como o teste fazia | até (1,58, −0,18): na altura da testa | 18 (antebraço esquerdo, 8–12 cm abaixo do centro da cabeça) |
| com a palma do clipe, como o jogo (`clip=1`) | até (1,35, −0,35): altura do peito | 0 |

Correção em `scripts/Actor.gd`: a palma do clipe é lida no começo de
`_apply_combat_weapon_pose`, antes de quadril/coluna/clavícula, quando `_clip_palms` não foi
preenchido (testes e capturas). No jogo `_clip_palms` sempre chega preenchido: o comportamento
do jogo não muda. O padrão antigo também calculava `combat_palm_position` da mão esquerda em
todo quadro, mesmo sem `follow_clip`; agora só lê palma quando precisa.

## M4A1 mirando andando/de lado: o degrau da coronha na gola

Onde (diagnóstico de pele com o ponto mais fundo, a peça e o osso do vértice mais próximo):
a quina de dentro (x −0,019 do modelo) do degrau da coronha retrátil, em z 0,14–0,17 e
y 0,016–0,04, entra na gola/peito direito (pele dos ossos `Spine01` e `RightShoulder`). Varia
com a passada: a arma fica presa ao bolso do ombro (calculado do repouso + `body_bob`) e o peito
real da passada vem até ela por 2 quadros em ~0,77 do ciclo. Mirando andando: 0,043 no pior quadro; de lado
0,037–0,038; parado mirando 0,032 (já na borda).

Desde quando: no worktree de 5e7d0360 (antes da coronha nova) o mesmo diagnóstico dá 0,030
(andando) e 0,018 (de lado). a4634240 (16/10) trocou a caixa da coronha (0,038 × 0,08 × 0,18)
pelo perfil com degrau; a medição usa um vértice de cada triângulo, e a caixa só tinha
vértices nos cantos (z 0,07 e 0,25): a quina do degrau é ponto novo exatamente onde encosta.

Correção em `gameplay/WeaponRigPose.gd`: `STOCK_POCKET_SHIFT["m4a1"] = (0, −0,015, 0,01)`
(espaço V1: 1,9 cm mais baixo e 1,3 cm à frente no V2), só na mira e na recarga, como o do rifle
de caça (com a arma baixa vale `STOCK_POCKET_SHIFT_READY`, zero para a M4).

Varredura do bolso (pior quadro, pele a cada 2 quadros dos 30 aos 79, mesma sequência do teste):

| deslocamento (V1) | parado mirando | parado atirando | mirando andando | andando atirando | de lado | para trás | recarga andando |
|---|---|---|---|---|---|---|---|
| nenhum (HEAD) | 0,032 | 0,016 | 0,043 | 0,030 | 0,037 | 0,033 | 0,036 |
| y −0,015 | 0,015 | 0,020 | 0,020 | 0,038* | 0,022 | 0,021 | 0,020 |
| y −0,010, z +0,010 | 0,018 | 0,039 | 0,038 | 0,039 | 0,016 | 0,031 | 0,024 |
| z +0,015 | 0,032 | 0,032 | 0,034 | 0,032 | 0,038 | 0,032 | 0,027 |
| x +0,012 | 0,019 | 0,019 | 0,022 | 0,022 | 0,021 | 0,021 | 0,026 |
| **y −0,015, z +0,010** | **0,018** | **0,015** | **0,020** | **0,020** | **0,020** | **0,016** | **0,021** |

\* topo de trás do receptor contra a lapela, com os 5 vértices mais próximos a 8,7–9,1 cm e
profundidades de sinais opostos (−0,077 … +0,045): leitura de dobra da malha, não contato que
se veja; com +1 cm à frente some. Na escolhida os vértices mais próximos estão a 2–3 cm (leitura
confiável) e o contato é a base da coronha apoiada no peito. Andando com a arma baixa (0,027–0,028)
não muda em nenhuma linha. "Atirando" não existe no teste de locomoção; entrou na varredura
porque o jogo atira andando.

## Verificação (checkout principal, depois das duas correções)

- `test_weapon_locomotion` 323/323. Soqueira correndo sem defeito de anatomia (pele 0,013);
  M4A1 mirando andando 0,042 → 0,020, de lado 0,036 → 0,018, para trás 0,032 → 0,016, recarga
  andando 0,024 → 0,017. Todas as linhas das outras 14 armas idênticas às de antes; velocidade
  articular igual, salvo soqueira andando 16,4° → 17,2°/quadro (mão esquerda seguindo o balanço
  real do clipe; limite 35°).
- `test_firearm_rig` 192/192 (M4A1 parado 0,027, mirando 0,016, atirando 0,015, recarga 0,012;
  trocas de/para M4A1 0,015–0,031, limite 0,040; apoio ≤ 3 mm).
- `test_melee_moveset` 55/55; `test_weapon_presentation_contract` 150/150.
- `tools/run_core_suite.sh --no-build` 10/10 (contratos; não cobre pose de arma).

Capturas (fora do Git, nesta pasta), `antes/` = HEAD, `depois/` = com as correções, mesma
`capture_melee_filmstrip.gd`:
- `aim_knuckles_run.png` (perfil) e `aim_knuckles_run_front.png` (frente, rosto): antes o punho
  da frente chega à testa/queixo em metade das colunas; depois balança na altura do peito.
  O "antes" é o que o teste media, não o que o jogo mostrava (o jogo já usava a palma do clipe).
- `aim_m4a1_aimwalk_front.png` e `aim_m4a1_aimwalk_top.png`: subida à mira andando. Na tira inteira a
  diferença (1–2 cm) quase não aparece; `comparacao_m4a1_frente.png` junta as colunas 8, 10, 12 e 13
  (esquerda antes, direita depois; embaixo ampliado): antes o topo do degrau da coronha sobe na dobra
  da gola/ombro da jaqueta, depois a coronha fica no bolso do ombro, abaixo da gola, inteira à frente
  do peito. A vista de cima (`top`) não mostra o contato (fica sob o ombro).

## Não verificado

- Jogo de verdade: não abri o jogo. A soqueira no jogo não muda (o caminho do `Actor` usado
  pelo jogo é o mesmo); a M4A1 muda (coronha 1,9 cm mais baixa no ombro) e só foi vista na tira.
- A M4A1 com outros clipes de mira (agachado, NPCs) e `test_combat_flow` não rodados.
- Desempenho: só uma constante e, fora do jogo, duas leituras de palma; não medido.
