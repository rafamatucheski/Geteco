# NPC com corpo do Meshy — piloto do mecânico (10/10/2026)

Piloto: o mecânico do Maciota. Substitui o corpo procedural antigo (13 peças visíveis + 21 escondidas
mantidas por `RigBodySwap`) por **um único corpo**: malha e esqueleto gerados no Meshy, posados pela
mesma IK procedural do `CivilianModel`. As famílias restantes **não** foram migradas.

## O que entrou

| Peça | Arquivo |
|---|---|
| Corpo único (extends `CivilianModel`) | `assets/civilians/MeshyRigBody.gd` |
| Mecânico, sem geometria antiga e sem o `_process` que girava os pivôs | `assets/maciota/MechanicModel.gd` |
| GLB do jogo: 4.092 triângulos, 24 ossos, textura 1024 (594 KB) | `assets/civilians/meshy/mechanic/mechanic.glb` |
| GLBs completos (78 ossos, clipes Walking/Running do Meshy), ignorados pelo Godot | `assets/civilians/meshy/mechanic/source/` |
| Medidas do corpo viraram variáveis de instância (padrão = valores do kit) | `assets/CivilianModel.gd` |
| Ferramenta que poda ossos não animados e reduz a textura | `tools/meshy_slim_glb.py` |
| Contrato, medição A/B e sonda de duplicidade | `tests/test_meshy_mechanic_body.gd`, `tests/measure/measure_meshy_body.gd`, `tests/diagnostics/duplicate_bodies_probe.gd` |

## Como funciona (e por que não há corpo escondido)

`MeshyRigBody` mantém a árvore de juntas do `CivilianModel` (`Pelvis`, `Spine`, `Head`, `left_upper_leg`,
`LeftForearm` …) **sem malha**: elas só carregam a pose calculada pela IK. Um nó `PoseDriver` copia, a cada
quadro em que alguma junta mudou, a rotação delas para os ossos do GLB. Por isso continuam valendo, sem
reescrever nada: locomoção por distância percorrida, pé plantado, `hand_targets`/`hand_provider` (arma, maca),
`sit_amount`, `take_hit`, `activity`, e as juntas que `MixamoDeath` e `CharacterFallPresentation3D`
procuram pelo nome. O driver roda num nó próprio porque o modelo pai pára de processar quando o ator morre
e a queda escreve nas juntas depois disso.

Detalhes que importam para quem for migrar outra família:

- O "Left" do Mixamo/Meshy fica em +X; o `left_*` do `CivilianModel` fica em -X. O mapeamento usa o lado.
- Cada osso recebe `rotação_da_junta × neutro`, onde `neutro` leva o osso do repouso (pose A) para
  "pendurado em -Y" pelo menor arco. Mãos recebem 70° de rolagem para a palma olhar a coxa.
- A IK usa as medidas do próprio esqueleto (`thigh_len`, `shin_len`, `ankle_height`, `upper_arm_len`,
  `forearm_len`, `pelvis_y`). O tornozelo desse boneco fica a 0,146 m do chão (bota alta), contra 0,085 m do kit;
  sem isso os pés flutuariam ~10 cm.
- O GLB é centralizado pela média dos quadris e escalado para 1,76 m.
- Ossos que nunca giram sozinhos (dedos, pontas, cadeias `Bone_NNN`) foram podados de 78 para 24: o peso deles
  passa ao pai, que se move junto, então a pele é idêntica. O custo do `Skeleton3D` de 78 ossos era medido.

## Origem no Meshy

Conta Pro; teto autorizado de 800 créditos; **gastos 50**: 2 malhas texto→3D (Meshy 6, A-Pose, 20 cada;
a 1ª saiu com pose torta), 1 textura (Meshy 7, 2K, PBR desligado, 10). Remesh para 4.000 triângulos e rig
humanoide não cobraram. Download: GLB, esqueleto Mixamo, "Personagem Rigged", "Todos Adicionados".

Prompt da malha (versão usada): *Realistic adult male auto mechanic, full body, symmetrical strict A-pose: both
arms straight and relaxed, angled about 35 degrees away from the torso, hands open with palms facing the
thighs, legs straight and slightly apart, feet flat, head facing forward, neutral expression. Natural human
proportions 1.76 m tall, medium build. Short dark brown hair, trimmed full dark beard, tan skin. Faded teal-blue
work coveralls with chest pockets, front zipper, reinforced knee patches, sleeves rolled to the forearm, dark
leather belt. Black leather work boots. Clean game-ready crowd NPC, simple silhouette, no tools, no props, no hat,
matte fabric, plain colors.* A foto de referência não pôde ser enviada (o navegador embutido não tem diálogo
de arquivo); o resultado veio só do texto. A pose saiu com os braços mais abertos que 35°.

## Geometria (antes → depois)

| | Antes | Depois |
|---|---|---|
| Malhas visíveis | 13 (ArrayMesh) | 1 (skinned) |
| Triângulos visíveis | 4.188 | 4.092 |
| Malhas escondidas mantidas | 21 (2.520 triângulos) | 0 |
| Ossos/juntas | 13 juntas Node3D sem esqueleto | 13 juntas sem malha + 24 ossos |
| Textura | cores por `instance uniform` | 1 JPEG 1024 (248 KB) |
| Draw calls, 40 mecânicos | 1.046 | 86 |

## Validação

Funcional (todos passam, com `APPDATA` isolado quando o teste exige):
`test_meshy_mechanic_body` 17/17; `test_maciota_transition_safety` 37 verificações — inclui "Mechanic e corpo
herdam proteção", "sem rotina de dano" e proteção após dano direto, contínuo e explosão externa, mais
todas as restrições de arma da garagem; `test_maciota_workshop_session`; `test_maciota_world`;
`test_mixamo_npc_death` 17/17; `test_hit_reaction`; `test_hit_presentation_lifecycle`; `test_garage_rewards`
47; `test_bridge_approach_terrain`, `test_native_driving`, `cold/test_admission`.

**`test_regions` falha, mas já falhava**: acessa `room.model` num `HarborBuildingPlace`, propriedade que o
`HEAD` desse arquivo não tem; não toquei em lugares.

Valores medidos no contrato: altura 1,760 m; pés em pé a 0,025 m; andando a 1,4 m/s o pé de apoio desliza
0,19 m/s; mãos chegam ao alvo com 6 cm de erro; sentar baixa a bacia de 0,93 para 0,53 m.

Visual: `evidence/npc-meshy/pilot-mechanic/` (parado de frente/lado/costas, andando, correndo, sentado, mãos
no alvo, reação a tiro; antigo à direita, novo à esquerda), e a garagem renderizada em `perf-garage-8/`.

## Desempenho — **não aprovado, não é regressão confirmada**

RTX 4060 Laptop, Vulkan Mobile, 1280×720, VSync e limite de FPS desligados só no processo, 5 s de aquecimento
+ 30 s por rodada, antigo e novo alternados na mesma sessão, em ambas as ordens. Medianas das rodadas com o
asset final (24 ossos):

| Cenário | Corpo | n | p50 | p95 | p99 |
|---|---|---|---|---|---|
| 40 mecânicos andando, palco | antigo | 9 | 2,66 ms | 3,37 | 5,22 |
| | novo | 9 | 2,77 ms | 4,10 | 5,21 |
| Garagem real, 1 mecânico | antigo | 10 | 2,01 ms | 3,19 | 3,71 |
| | novo | 10 | 2,25 ms | 3,74 | 4,82 |

Leitura honesta: diferenças de +4 a +30% nas medianas, mas a variação entre rodadas do **mesmo** corpo é de
±15%, com outros processos Godot abertos (editor e jogos, quase ociosos) durante todas as medições. Na janela
mais quieta o novo empatou ou ganhou (p99 3,3 contra 5,4 ms). Tudo fica entre 2 e 5 ms, muito abaixo dos
16,67 ms. O que se demonstrou:

- sem a cópia de pose o corpo novo fica em p50 ≈ 1,6 ms com 40 NPCs, abaixo do antigo (≈ 2,4 ms em outra execução da mesma janela; não foram rodadas lado a lado);
- a cópia custou ~1 ms por quadro para 40 NPCs com 78 ossos e ~0,6 ms com 24 (a poda ajudou);
- na garagem, com 1 NPC, "parado" e "posado" custam o mesmo, e malha oculta ou sem sombra não se distinguem do
  ruído — a diferença pequena da garagem não é custo por NPC e a causa **não foi identificada**.

Pendente para fechar: repetir a garagem em máquina sem outros Godot abertos e com mais rodadas, e só então
decidir. Resultados brutos em `evidence/npc-meshy/perf-*/` (não versionados).

## Duplicidade de personagens

Sonda `duplicate_bodies_probe.gd` em Main real (início, rua 166/111, Vértice/Digo, garagem), 14 s por ponto:

| Ocorrência | Resultado |
|---|---|
| A) dois corpos visíveis no mesmo modelo | 0 (um falso positivo inicial: dois funcionários distintos de `Vertice`, a 7 m) |
| B) malha antiga visível em modelo com corpo novo | 0 fora da lista `keep`; as 2 da garagem são o cajado do Maciota, mantido de propósito |
| C) dois atores sobrepostos (< 0,25 m) | 0 |
| Geometria antiga escondida | 56 a 149 malhas por ponto (por design do `RigBodySwap`; não é renderizada) |

Isso cobre 4 pontos, não o mundo. Nenhum caso real de sobreposição visível foi reproduzido; para investigar um
caso concreto, rodar a sonda no lugar onde ele aparece. Causas possíveis por categoria: A = modelo que monta um
`CivilianModel` e também recebe `RigBodySwap.install`; B = peça criada **depois** do `install` (a ocultação só
alcança o que já existia); C = o mesmo `persistent_id` instanciado duas vezes (streaming + restauração de save).

## Pendências explícitas

- Famílias restantes continuam com corpo antigo escondido: polícia, bombeiro, paramédico, agente funerário,
  residentes de serviço/médico, Neco, Maciota, caixas, Cobras, montanha (`WinterResidentModel._process` ainda
  atualiza membros antigos). Cada uma tem armas/maca/acessórios que precisam de âncoras no esqueleto novo.
- Variedade de corpos (alto, magro, gordo, mulher, tons de pele, terno, motoqueiro): exige um GLB por
  biotipo (ou escala de ossos + material) e roupas; não gerado.
- Dedos ficam esticados (sem curvatura); remendos dos joelhos esticam na corrida; a textura veio sem mapas PBR.
- Os clipes de andar/correr do Meshy foram baixados mas **não usados**; a pose vem da IK. Não se comparou lado
  a lado com os clipes.
- Desempenho: ver acima.
