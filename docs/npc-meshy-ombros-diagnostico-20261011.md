# Diagnóstico e candidatos de pesos dos ombros — 11/10/2026

Atualização da sessão principal: a correção proximal do ombro masculino e o colapso dos dois helpers foram integrados, junto do reparo de mãos. A prova cinemática no Godot passou para joelhos/tornozelos em repouso, passo, sentado e queda. O terno de produção tem agora 24 ossos. Resultado e limites da entrega em [npc-meshy-refino-20261011.md](npc-meshy-refino-20261011.md); abaixo permanece o registro da investigação e dos candidatos.

**Estado: análise offline e candidatos, sem aprovação visual ou de performance.** Nenhum GLB de produção foi alterado por esta análise. A validação renderizada fica com a sessão principal para não iniciar motores concorrentes.

## O que os dados mostram

O `MeshyBodyRig` mantém `Shoulder` na orientação de repouso do pai, enquanto leva `Arm` e `ForeArm` da pose de repouso para a pose procedural. Uma influência de `Shoulder` sobre a manga pode assim prender parte do tecido no alto enquanto o braço desce. É uma hipótese de causa, não uma comprovação visual para cada corpo.

O ângulo foi medido entre o segmento `Arm → ForeArm` do GLB e o eixo vertical para baixo. Os pesos abaixo são médias dos vértices dentro de uma esfera de raio 15 cm centrada no `Arm`, com altura normalizada para 1,76 m. L/R são os nomes do esqueleto Meshy, invertidos em relação aos lados do `CivilianModel`.

| Corpo | Ângulo L/R | Peso Shoulder L/R | Peso Arm L/R | Ossos |
|---|---:|---:|---:|---:|
| suit_m | 36,56° / 35,05° | 0,158 / 0,243 | 0,619 / 0,414 | 26 |
| suit_f | 13,44° / 13,44° | 0,165 / 0,179 | 0,509 / 0,554 | 22 |
| country_m_a | 66,69° / 66,69° | 0,442 / 0,463 | 0,313 / 0,336 | 22 |
| country_m_b | 64,98° / 64,98° | 0,448 / 0,453 | 0,305 / 0,336 | 22 |
| country_f_a | 38,12° / 37,54° | 0,240 / 0,266 | 0,456 / 0,475 | 22 |
| country_f_b | 37,32° / 37,05° | 0,228 / 0,269 | 0,440 / 0,472 | 22 |
| patrol_m | 39,82° / 39,82° | 0,429 / 0,391 | 0,424 / 0,488 | 22 |
| patrol_heavy | 68,02° / 68,02° | 0,428 / 0,437 | 0,380 / 0,437 | 22 |
| f_medium_a | 62,87° / 62,87° | 0,601 / 0,675 | 0,277 / 0,206 | 22 |
| f_medium_b | 64,44° / 64,44° | 0,570 / 0,658 | 0,291 / 0,210 | 22 |
| m_medium_a | 36,68° / 36,68° | 0,237 / 0,230 | 0,659 / 0,645 | 24 |

Isso limita a explicação anterior de “braços muito abertos”: `suit_f` tem o braço muito menos aberto que `patrol_m`. A roupa, a distribuição dos pesos e a relação entre geometria e pivôs precisam ser avaliadas juntas. O terno masculino tem pesos e número de vértices da região bastante assimétricos. As médias não demonstram por si só um erro de peso.

## Candidatos preservando pivôs

A ferramenta nova `tools/meshy_shoulder_weights.py` produz um GLB separado e recusa sobrescrever o original ou um candidato existente. Para gerar um caso:

```powershell
python tools/meshy_shoulder_weights.py assets/civilians/meshy/police/suit_m.glb --destination evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_experiment.glb --strength 0.55 --report evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_experiment.json
```

O candidato transfere parte do peso de `Shoulder` para `Arm` somente em uma faixa exterior da manga, com transições `smoothstep`: posição lateral de −2,5 a +7,5 cm relativa ao ombro; distância axial de −6 a +12 cm, caindo novamente de 14 a 20 cm; distância radial com queda de 11 a 17 cm. Essas distâncias usam escala de altura 1,76 m. A máscara preserva a maior parte do tronco/gola e a região distante da manga. Não altera posições, pivôs, ossos ou triângulos.

Foram geradas duas intensidades experimentais para os seis corpos, dentro de `evidence/npc-meshy/refinement-20261011/shoulder-candidates/`:

- `{suit_m,suit_f,country_m_a,country_m_b,country_f_a,country_f_b}_conservative.glb`: transferência máxima teórica de 55% do peso Shoulder, modulada pela máscara.
- Os mesmos nomes com `_medium.glb`: máximo teórico de 85%, para comparação. Nenhuma das duas intensidades foi escolhida para produção.

Cada GLB acompanha um JSON com os índices dos vértices afetados e a influência transferida. Os relatórios `*_diagnostic.json` incluem também os corpos de comparação.

| Corpo | Vértices / triângulos / ossos | Vértices afetados L/R, nas duas intensidades |
|---|---:|---:|
| suit_m | 3.912 / 4.146 / 26 | 149 / 97 |
| suit_f | 4.125 / 4.112 / 22 | 101 / 120 |
| country_m_a | 3.747 / 4.144 / 22 | 86 / 98 |
| country_m_b | 3.743 / 4.144 / 22 | 86 / 97 |
| country_f_a | 3.769 / 4.156 / 22 | 152 / 134 |
| country_f_b | 3.770 / 4.156 / 22 | 164 / 145 |

## Por que não dividir rotação indiscriminadamente

As clavículas têm cerca de 10,7 a 18,5 cm nos corpos analisados. Girar `Shoulder` move a origem do `Arm`: uma rotação perpendicular de 20° nessa distância pode deslocar o pivô entre 37 e 64 mm. A IK atual usa o pivô original do braço e comprimentos originais; alterar a hierarquia sem compensar também as posições pode ultrapassar o requisito de contato de mão menor que 30 mm.

A base global de `Arm` já é calculada independentemente no driver. Apenas dividir seu quaternion com `Shoulder` não garante preservar nem posição nem contato. Uma solução pelo driver precisaria reconstruir essa relação e medir mãos, repouso, caminhada, mira, recuo, recarga, corrida, queda e morte. Reponderação offline é a primeira experiência por preservar os pivôs e não acrescentar processamento por quadro.

## Comprimentos dos braços da polícia

Medidas do GLB normalizadas à mesma altura de 1,76 m, em milímetros. Alcance é a soma `Arm → ForeArm` e `ForeArm → Hand`, sem extensão artificial. No espaço local de `CivilianModel`, L Meshy corresponde ao braço procedural +X e R ao braço −X. `RigBodySwap` gira esse corpo em PI dentro do `PoliceModel`; portanto o punho direito da arma policial corresponde a `RightHand` Meshy/índice 0 do corpo, e o apoio esquerdo a `LeftHand` Meshy/índice 1. Os sete esqueletos têm a cadeia direta `Arm → ForeArm → Hand`, sem intermediários auxiliares nesses segmentos.

| Corpo | Braço superior L/R | Antebraço L/R | Alcance L/R |
|---|---:|---:|---:|
| patrol_f | 215,308 / 208,988 | 268,713 / 257,326 | 484,020 / 466,313 |
| patrol_heavy | 191,212 / 199,476 | 262,620 / 261,485 | 453,832 / 460,961 |
| patrol_m | 247,716 / 232,641 | 241,507 / 242,130 | 489,223 / 474,770 |
| suit_f | 238,962 / 227,565 | 249,963 / 257,718 | 488,925 / 485,283 |
| suit_m | 223,287 / 208,133 | 233,168 / 239,656 | 456,454 / 447,788 |
| tactical_black | 243,081 / 238,251 | 296,789 / 294,299 | 539,871 / 532,550 |
| tactical_gray | 205,399 / 204,002 | 219,487 / 203,539 | 424,886 / 407,541 |

O limite fixo de alcance de 594 mm é maior que o alcance de todos esses braços. Para `tactical_gray` R, excede o alcance do esqueleto em 186,459 mm. A média dos lados também não representa exatamente nenhum dos dois braços; a maior diferença de alcance entre os lados é 17,707 mm em `patrol_f`. Esses dados justificam verificar a IK e o ponto de contato por lado. A remoção da extensão legada e a correção da IK serão implementadas/validadas pela sessão principal; não fazem parte da ferramenta de pesos. Dados completos: `police_arm_lengths.json` junto dos candidatos.

## Verificações realizadas e pendentes

Foi seguida `testes-com-criterio` para a verificação dirigida da ferramenta. Os 12 candidatos foram reabertos em Python e comparados com seus originais após a serialização. Passaram: igualdade exata de nós, hierarquia, lista de ossos, matrizes inverse bind, índices de triângulos, posições, normais, UVs e demais atributos fora dos pesos/índices de influência; imagens embutidas idênticas; soma de pesos preservada com erro máximo menor que 1e-6; pesos não negativos. Nenhum vértice precisou descartar uma influência para acrescentar `Arm`. Foram verificados também a recusa de destino igual ao original e de intensidade fora de [0,1].

**Pendente:** importar os candidatos no Godot .NET e comparar frente/costas/lado em repouso, caminhada e mira. Verificar deformação da gola, manga e axila, incluindo efeito inverso quando o braço sobe; medir contato de mão real. Não foi iniciada nenhuma instância Godot nesta análise. Não foram executados testes do jogo, medição de frame time ou validação de luzes. Nenhum resultado offline aprova a silhueta ou o desempenho do jogo.

Defeito adjacente a verificar separadamente: `suit_m` conserva `Bone_004` e `Bone_002` entre `UpLeg` e `Leg`. A cadeia atual do driver não inclui esses intermediários da coxa, embora inclua o intermediário antes de `Foot`. A base do pai da canela pode ficar sem cálculo. Não foi alterado aqui; exige inspeção no motor e cobertura de sentar/caminhar/morrer.

## Segunda investigação: ForeArm indevido no topo do terno masculino

A sessão principal comparou capturas em `shoulder-compare/`: os candidatos iniciais `conservative`/`medium` não corrigiram a asa do `suit_m`. As matrizes dos ossos na pose renderizada foram exportadas em `pose-diagnostics/suit_m-aim-bones.json`, permitindo reconstruir o skin offline com `pose_global * inverse_bind` e os pesos originais. O erro de reconstrução da pele de repouso contra as posições originais foi apenas 0,000168 mm, validando os espaços usados nessa análise.

**A causa dominante encontrada é outra:** vértices do topo do ombro e da gola do `suit_m` carregam até 50–54% de peso `ForeArm`. A rotação do cotovelo arrasta essa roupa. Exemplo: vértice 628, no topo do ombro Meshy Right, tem `Shoulder=0,251`, `Arm=0,205`, `ForeArm=0,544`; passa de aproximadamente `[-187,8; 1436,3; -165,5]` mm no repouso para `[-395,4; 1360,1; -155,1]` mm na pose de mira. Outro vértice perto da gola, 743, tem `Neck=0,052`, `Shoulder=0,375`, `Arm=0,100`, `ForeArm=0,474`. Isso explica por que mudar somente `Shoulder → Arm` não resolveu a asa.

A cobertura dos onze GLBs polícia/country usou uma esfera de 240 mm centrada em `Arm`, considerando somente vértices acima de `Arm + 25 mm`. `suit_m` tem 34 vértices em cada lado com peso `ForeArm > 0,20`. Nenhum dos outros dez GLBs apresenta isso nessa região: máximos de 0,020–0,034 em country masculino e até 0,007 nos demais. Portanto essa correção não foi generalizada. Dados individuais em `upper_shoulder_forearm_diagnostics.json`.

### Novo candidato específico

A mesma ferramenta ganhou `--mode proximal-forearm`, para redistribuir `ForeArm` da faixa proximal para `Spine2`/`Shoulder`/`Arm`. A máscara axial fica integral até +25 mm a partir de `Arm` e cai suavemente até +130 mm; a máscara radial por distância ao pivô fica integral até 150 mm e cai até 270 mm. A porção interior ao tronco ganha `Spine2` gradualmente (até 85% da transferência). O topo exterior divide a influência restante em até 75% `Shoulder`, com o restante em `Arm`; mais abaixo a participação de `Arm` cresce. Essa regra procura retirar o cotovelo da gola mantendo uma transição da manga. Ainda exige avaliação visual.

```powershell
python tools/meshy_shoulder_weights.py assets/civilians/meshy/police/suit_m.glb --destination evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_shoulder_proximal.glb --mode proximal-forearm --strength 1.0
```

Foram gerados `suit_m_shoulder_proximal.glb` (só ombro) e `suit_m_refined.glb` (ombro aplicado ao candidato de mãos descrito em `npc-meshy-maos-diagnostico-20261011.md`). Foram afetados 290/183 vértices L/R, com transferência total de influência de 32,714/30,666. Nós, pivôs, inverse bind, triângulos, geometria e pesos `Hand` permanecem exatamente como no respectivo arquivo de entrada. O combinado conserva a marca idempotente do reparo de mãos. Após serialização, erro máximo da soma de influências: 3,68e-8. Relatório `suit_m_shoulder_proximal_validation.json`.

### Simulação com a mesma pose exportada

A amostra de arestas foi definida pelos dois extremos dentro de uma esfera de 260 mm do `Arm`, posição original y acima de 1,19 m e comprimento original maior que 1 mm. Os números são razões comprimento posado/repouso, não métricas de performance.

| Lado | p95 original → candidato | Máximo original → candidato |
|---|---:|---:|
| Left | 1,4304 → 1,3090 | 2,4505 → 2,3678 |
| Right | 1,9916 → 1,0896 | 4,6769 → 1,6171 |

O vértice 628 deixa x = −395,4 mm e passa a x = −202,9 mm, removendo 192,5 mm do arraste lateral; y aproxima-se do repouso, de 1360,1 para 1433,2 mm. O combinado com mãos gera os mesmos números no ombro. **Há resíduo significativo à esquerda: o candidato não está aprovado por essa simulação.** Captura de frente/costas/lado, repouso/caminhada/mira e movimento temporal continua obrigatória. Evidência de skin e comparações em `pose-diagnostics/suit_m_shoulder_skin_offline.json` e `suit_m_shoulder_candidates_simulated.json`.

## Candidato para intermediários não dirigidos da coxa

A ferramenta nova `tools/meshy_collapse_rig_helpers.py` produz `suit_m_collapsed.glb` a partir do GLB de produção já atualizado pela sessão principal com mãos/ombros. O candidato remove exclusivamente `Bone_002` e `Bone_004`, os intermediários entre `UpLeg` e `Leg`; mantém `Bone_012` e `Bone_016` antes dos pés. O skin passa de 26 para 24 ossos.

```powershell
python tools/meshy_collapse_rig_helpers.py assets/civilians/meshy/police/suit_m.glb evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_collapsed.glb --helpers Bone_002,Bone_004 --report evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_collapsed.json
```

O CLI exige uma allowlist explícita; o código recusa qualquer nome além desses dois, helpers fora de `UpLeg → helper → Leg`, arquivos com animações, mais de um skin e sobrescrita de original/destino existente. O local do filho vira `helper_local * child_local`, preservando o global de repouso. Os pesos do helper passam para `UpLeg` sem truncar influências; são removidas somente as entradas correspondentes de inverse bind, com reindexação dos nós/joints. Metadados de reparos anteriores permanecem e a marca `rig_helpers_collapsed_v1` impede repetição.

Justificativa da pele: como o helper não recebe pose independente, `helper_pose = parent_pose * helper_rest`; sua skin matrix `helper_pose * IBM_helper` equivale à do pai mantido. Isso não vale para helpers animados separadamente; por isso a ferramenta não opera em GLBs com animações.

Verificação offline dirigida, após serialização: todos os globals de repouso dos nós mantidos preservados com erro máximo de matriz 2,22e-16; posições/normais/UVs/índices/texturas e inverse bind dos joints mantidos exatos. Em 12 poses determinísticas com rotações grandes e translações de quadril, helpers sem pose independente, erro máximo de matriz dos mantidos 3,89e-16 e deslocamento máximo do skin 0,0000455 mm. Soma de pesos preservada com erro menor que 1e-6. Reaplicação para outro arquivo foi byte a byte idêntica. Também foram verificadas a recusa de original, allowlist vazia/repetida e helper dos pés. Evidência em `suit_m_collapsed_validation.json`.

**Pendência:** prova cinemática no Godot .NET de caminhada, sentar, queda/morte e contatos, porque os globais desejados do driver real e seus pais agora precisam ser observados no motor. Esta investigação não executou Godot nem alterou produção. A equivalência offline não certifica o comportamento anterior de um driver que deixava os intermediários sem cálculo.
