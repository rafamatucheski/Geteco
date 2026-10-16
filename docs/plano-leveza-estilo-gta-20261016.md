# Plano: jogo leve no estilo GTA III / Vice City — 2026-10-16

Objetivo: o custo do mundo vem de **pouca coisa pronta e compartilhada** (modelos já montados,
poucos materiais, textura no lugar de malha), e não de montagem em tempo de jogo. O alvo não é
mais a mediana de quadro (já ≤ 16,7 ms nas rotas medidas) e sim **nenhum quadro grande**.

Tudo aqui parte de números que outras sessões já mediram (`docs/otimizacao-20261014/F2.md`,
`docs/perf-cross-20261015-phase2.md`) ou do que o código mostra. Onde for hipótese, está marcado
**[hipótese]**. Esta sessão não mediu desempenho.

## Quem faz o quê (para ninguém se atropelar)

| Frente | Dono | Mexe em |
|---|---|---|
| A. Gerar texturas (fachadas, portas, telhados, noite) | Codex / outro lugar | só `output/imagegen/` |
| B. Ligar texturas ao jogo (kit de fachada pintada, vãos, portas, testes) | esta sessão | `world/urban_detail/Painted*`, `tools/painted_facades_*.json`, `assets/facades/*`, testes `test_painted_*` |
| C. Picos, streaming, pipelines, fusão por trecho | sessão de desempenho | `NativeRegion.gd`, `world/chunk_bake/*`, `HarborBuildingBatch.gd`, `UrbanBuildingFactory.gd` (editado por mim em 1ef7668c e 0dbf1937: avisar), ponte, mobília, props, `tools/run_godot_locked.sh` |

Regras comuns: Godot só pela fila `tools/run_godot_locked.sh` (fui direto ao binário até aqui, com
o usuário avisado; daqui para frente uso a fila). Quem não é da frente C não mede desempenho.
Commit só dos próprios arquivos, nunca `git add -A`.

## Frente 1 — Prédios inteiros em textura (B, esta sessão)

Por que: prédio de caixas custa 40–150 superfícies (hospital 80, CornerDiner 61, lavanderia 83,
Apartments 42 no censo de 14/10); prédio pintado custa ~5 (paredes, telhado, cornija, portas) e
não monta nada em runtime. Já medido nas casas: 176 → 34 nós.

Estado: no jogo — casas Cobra/Patrol, sobrados, deserto, serra e 7 prédios do porto (lavanderia,
marcenaria, mercado, escritório de frete, aquário, museu, câmara fria).

Falta, por ordem de ganho:
1. Os que já têm imagem e só precisam de decisão/encaixe: lanchonete, mercado-ilha, cinema, café
   (letreiros diferentes do nome no jogo: pedir regeneração, ver `prompt-codex-tudo.txt`);
   mercearia, galpão portuário, estação de ônibus (achar o id do prédio no jogo).
2. Construtores especiais que a fachada pintada hoje não atende: delegacia (`PoliceStationDressing`),
   bombeiros (baia de viaturas), clínica (hospital com fachada própria), banco (marco),
   oficina e garagem (`UrbanServiceBuilding`), garagem do Maciota (caixas 3D com interior e
   colisão; pacotes `garagem-piston` e `anexo-piston` pedidos). Cada um precisa de um encaixe
   próprio sem quebrar acesso, colisão nem reveal do interior.
3. Prédios altos: o kit não empilha térreo/andar/topo. Precisa de modo "alto" (módulo vertical
   repetido sem emenda) antes de usar os 7 pacotes altos.

Critérios por prédio (testados em `test_painted_harbor_buildings`): uma só entrada por vão, porta
dupla com as duas folhas abrindo juntas, base rente ao chão, largura = catálogo/interior, nenhuma
porta fora do kit. Capturas de dia e noite olhadas. Interruptor: `GETECO_PAINTED_FACADES=0`.

## Frente 2 — Detalhe de rua vira textura (B/C, medir antes) **[hipótese]**

Candidatos: faixas, rachaduras, bueiros, faixa de pedestre, manchas (hoje parte vem de
`HarborRoadGeometry3D.gd`, 801 linhas, não lido por inteiro). Meio-fio e degrau continuam
geometria (colisão e soleira). Antes de trocar: um censo de superfícies por tipo de peça da rua.
Também tornar explícito o tipo de piso por área (calçada, asfalto, grama) em vez de deduzi-lo
pelo nome do colisor (`VehicleSurfaceProbe` / `SurfaceResolver3D`), como o `SURFACE_PAVEMENT`
por triângulo de colisão do GTA III.

## Frente 3 — Árvores, mobília, carga (C)

Árvores 32–35 malhas por trecho; terraço do AnchorTable 104 superfícies; ~35 pilhas de carga no
cais (dados de 14/10). Caminho: MultiMesh por espécie/modelo, cópia plana de longe, peças
pequenas sem sombra. Dono: frente C (arquivos reservados lá).

## Frente 4 — Menos materiais e pipelines (C)

Os picos mais feios (100–700 ms) são compilação de pipeline no meio do jogo; o cache de
pipelines do release tem 218 MB e cresce a cada rodada. Menos materiais distintos (cor por
vértice, mesma instância para parâmetros iguais) e aquecimento sob a cortina de carregamento.
O fachada pintada ajuda: um material por parte e por estilo, em vez de dezenas por prédio.

## Frente 5 — Fusão offline em vez de em runtime (C)

`chunk.cell_merge` ainda custa 96–146 ms de _process por trecho. A ideia do GTA: gravar o
resultado em disco por trecho, com chave que inclua a assinatura das edições do editor, e
cair no caminho atual quando a edição for nova.

## Frente 6 — Medição (C, no fim)

Um censo de **triângulos e vértices** por tipo de objeto (prédio, ponte, guarda-sol, árvore)
não existe; só há contagem de superfícies. Escrever no estilo `census_chunk_draws.gd` (soma de
`Mesh.get_faces()` por dono), rodando só pela fila. Depois, rodadas de release em fila, duas por
cenário. Esta sessão não mede.

## Ordem sugerida

1. B: ligar lanchonete, mercado-ilha, cinema, café quando os letreiros novos chegarem; achar ids.
2. B: encaixe de delegacia, bombeiros, clínica, oficina, garagem do Maciota (um de cada vez).
3. C em paralelo: pipelines/aquecimento e fusão offline (frentes 4 e 5), que atacam os picos.
4. B: modo "prédio alto" no kit, depois os 7 prédios altos.
5. Frente 2 só depois do censo da rua.
6. Frente 6 no fim, com tudo commitado.

## O que não foi verificado

Nenhum ganho de desempenho dos prédios pintados do porto foi medido; a estimativa vem das casas
(176 → 34 nós). Noite, passagem a pé pela porta dupla e o efeito do prédio mais estreito (menor
que a pegada antiga) nos vizinhos não foram verificados.
