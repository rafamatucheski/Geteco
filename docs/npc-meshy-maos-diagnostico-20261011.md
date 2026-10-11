# Mãos do terno masculino: pesos e candidato de reparo — 11/10/2026

Atualização da sessão principal: o reparo incremental foi integrado ao terno masculino. A orientação dirigida de punho experimental foi rejeitada e removida; foi mantido o roll existente do antebraço. Os 56 casos de contato de SMG/M4 passaram, incluindo corrida estabilizada. Resultado e limites em [npc-meshy-refino-20261011.md](npc-meshy-refino-20261011.md); abaixo permanece o registro da investigação offline.

**Candidato offline, pendente de captura/seleção pela sessão principal.** Originais e runtime não foram alterados nesta investigação. Nenhum motor foi iniciado.

## Causa encontrada

A captura `evidence/npc-meshy/refinement-20261011/grip-oriented/suit_m-aim-side.png` mostra os dedos ainda acompanhando o antebraço apesar da orientação dirigida do osso `Hand`. O GLB tem a marca `hands_curled: 55`, mas o importador só curva vértices com peso total `Hand >= 0,6`. No terno masculino, a maior parte da geometria distal da mão está pesada em `ForeArm`, portanto não responde integralmente ao punho e não foi curvada pelo importador.

Foi definida uma região distal reproduzível: projeção de +25 a +160 mm a partir de `Hand`, ao longo de `ForeArm → Hand`, com distância radial menor que 90 mm; altura normalizada para 1,76 m. L/R são nomes Meshy. No policial, `RightHand`/índice 0 sustenta a empunhadura direita e `LeftHand`/índice 1 sustenta o guarda-mão, devido à rotação PI do corpo no `RigBodySwap`.

| Corpo | Vértices distais L/R | Média Hand L/R | Dominância Hand na região |
|---|---:|---:|---|
| suit_m | 146 / 138 | 0,260 / 0,270 | 35 / 35 vértices; restantes 111 / 103 dominados por ForeArm |
| suit_f | 142 / 126 | 0,995 / 0,998 | Todos |
| patrol_m | 76 / 80 | 0,995 / 0,994 | Todos |
| patrol_f | 140 / 141 | 0,999 / 0,997 | Todos |
| patrol_heavy | 164 / 161 | 0,993 / 0,991 | Todos |
| tactical_gray | 82 / 79 | 0,996 / 0,990 | Todos |
| tactical_black | 151 / 115 | 0,987 / 0,993 | Todos |
| country_m_a | 152 / 162 | 0,992 / 0,997 | Todos |
| country_m_b | 147 / 162 | 0,995 / 0,994 | Todos |
| country_f_a | 143 / 136 | 0,999 / 0,998 | Todos |
| country_f_b | 144 / 134 | 0,998 / 0,999 | Todos |

Os outros dez corpos não reproduzem essa fraqueza na região analisada. Essa conclusão não certifica todos os pesos da anatomia. Dados: `evidence/npc-meshy/refinement-20261011/shoulder-candidates/hand_weight_diagnostics.json`.

## Reparo experimental

`tools/meshy_repair_hand_weights.py` transfere `ForeArm → Hand` com uma transição suave junto ao punho: projeção axial de −5 a +25 mm, queda radial de 80 a 110 mm e queda axial distal de 170 a 200 mm. Preserva a soma e não descarta influências existentes para abrir slots. Mantém todos os outros ossos intactos.

Em seguida curva em 55° somente os vértices que passaram de `Hand < 0,6` para `Hand >= 0,6`. A dobradiça segue o algoritmo existente, a 42% da extensão axial da mão; direção de palma usada é +Z no repouso. Vértices anteriormente elegíveis ficam com posições/normais exatamente iguais para não receberem uma segunda curva. A marca independente `hand_weights_repaired_v1` torna o reparo idempotente.

```powershell
python tools/meshy_repair_hand_weights.py assets/civilians/meshy/police/suit_m.glb evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_hand_repair.glb --report evidence/npc-meshy/refinement-20261011/shoulder-candidates/suit_m_hand_repair.json
```

O comando recusa sobrescrever original ou destino existente. O candidato já foi gerado; os JSONs registram índices individuais.

| Medida | Left | Right |
|---|---:|---:|
| Elegíveis antigos Hand >= 0,6 | 22 | 26 |
| Elegíveis após reparo | 181 | 192 |
| Novos elegíveis | 159 | 166 |
| Vértices novos efetivamente curvados | 120 | 105 |
| Média Hand da região distal após reparo | 0,998 | 0,985 |
| Comprimento axial usado para curva | 182,984 mm | 182,665 mm |
| Deslocamento máximo de geometria nas pontas | 100,793 mm | 106,372 mm |

Essa curva não articula dedos individuais, não inclui tratamento próprio do polegar e não prova que a palma/empunhadura se encaixem. A extensão selecionada é maior que a do algoritmo anterior, porque os dedos antes dominados por `ForeArm` não participavam da seleção. A fronteira entre a curva antiga e a nova exige inspeção de perto.

## Verificação offline

Seguindo `testes-com-criterio`, o candidato foi reaberto após serialização. Verificados: nós/hierarquia, lista de ossos, inverse bind, índices de triângulos, UVs e imagens idênticos; pesos dos ossos fora de `Hand`/`ForeArm` idênticos; soma de pesos preservada com erro menor que 1e-6; posições/normais dos antigos elegíveis exatamente iguais. A reaplicação gerou `suit_m_hand_repair_idempotent.glb`, byte a byte idêntico ao candidato. Evidência em `suit_m_hand_repair_validation.json`.

Pendente: captura renderizada com SMG/M4, frente/lado/costas, mira, recuo, recarga e corrida; verificar que a mão acompanha o punho sem ruptura da malha. Distância do osso do punho ao grip não comprova distância da superfície da palma ao contato. Não foram executados testes Godot, benchmarks ou aprovada nenhuma geometria para produção.

## Origem do braço e custo do driver

O ajuste da sessão principal usa `get_bone_global_pose(parent).origin` em espaço local do Skeleton e calcula o alvo removendo `glb_root.position` e dividindo por `_scale`. Esses espaços são compatíveis nos GLBs atuais, que têm malha/root em transformação identidade e escala uniforme aplicada externamente. Esse raciocínio não estabelece suporte para imports arbitrários com transforms adicionais ou escala não uniforme.

Há duas consultas do pai do braço por sincronização. Como o driver já escreve rotações na mesma cadeia, essas leituras podem exigir atualização interna do esqueleto; o custo não foi medido. Uma alternativa a avaliar é manter origens globais no cache junto das bases em ordem pai → filho, calculando `parent_origin + parent_basis * local_origin`, sem consultar Skeleton no meio das escritas. Essa é uma sugestão, não uma otimização implementada ou comprovada.
