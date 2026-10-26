# Três melhorias baratas das regiões atuais (26/10/2026)

Origem: [Carta do Mundo 2.0](design/mapa-mundo-v2-20261026.html). Das 18 melhorias propostas ali para
Harbor, Mar do Sul, Serra e Deserto, estas três são as mais baratas porque quase tudo já existe no
código. Nada foi implementado. As estimativas vêm de leitura do código, não de medição.

## Como foi a escolha

| Melhoria | Custo | Motivo |
| --- | --- | --- |
| **Cratera do meteoro com caverna** | muito baixo | Uma entrada nova em `DesertWilds.SITES`; caverna, achado, recibo, munição e torre de rádio já funcionam |
| **Refúgio da Serra** (sem avalanche) | baixo | Molde da `ForgeHermitCabin` + fonte de calor + descanso igual ao do Motel Oásis |
| **Observatório da serra** | baixo a médio | O binóculo do mirante costeiro é quase genérico; o risco é o vazio ao longe |
| Drive-in Estrela | médio | Prédio novo, tela e um evento noturno |
| Cemitério de Aviões | médio | O avião existente é o modelo pesado do acidente; precisaria versão leve e pré-aquecimento |
| Oásis das Palmeiras | médio | Água no deserto e uma vila; o nome também colide com o Motel Oásis |
| Lago congelado | médio | Atrito no gelo mexe na física dos carros; pesca hoje é do Lago Sereno |
| Tempestade de areia | médio a alto | Estado novo de clima, partículas pré-aquecidas, minimapa |
| Northgate na beira d'água | médio a alto | Mexe na linha, nas viagens e nos saves |
| Estação do Cume, avalanche | médio a alto | Ferrovia nova / evento físico na corrida |
| Assalto à ponte, Harbor Antigo, obras em níveis, balsa, ilha, naufrágio | alto | Missão nova, bairro novo, geometria em níveis ou sistemas que não existem (lancha, mergulho, destino da balsa) |

## 1. Cratera do meteoro com caverna de cristais (Deserto)

**O que é.** Um anel de rocha queimada no deserto, com uma caverna no meio. Dentro, cristais (o achado)
e um bilhete. Responde ao pedido de mais cavernas no deserto.

**O que já existe e é reaproveitado.**
- `runtime/desert/wilds/DesertWilds.gd`: cada lugar é uma linha em `SITES`. Monta a ~110 m, solta a
  ~150 m, um passo por quadro. O achado sai uma vez por save, com recibo (`claim_cave`), e a caixa de
  munição repõe uma vez por dia de jogo.
- `runtime/desert/wilds/CaveBuild.gd`: o morro de ~22 × 20 m, as paredes, o interior e as pedras soltas.
- `runtime/desert/roadside/RoadsideSecrets.gd`: a torre de rádio já aponta toda caverna não saqueada.
  A cratera entra no mapa por ela sem código novo.
- `DesertWilds.reserved()` já impede cacto e enfeite dentro da caverna.
- Interruptor `GETECO_DESERT_WILDS=0` para o A/B.

**Passos.**
1. Escolher o ponto com a mesma varredura usada nos outros `SITES` (`DesertRegion._decoration_clear`:
   22 m livres, longe de estrada, chão plano). Pelo desenho, no noroeste vazio, longe do cânion e das
   cavernas que já existem.
2. Acrescentar a entrada `cave_crater` em `SITES`, com `loot: "cash"` e um bilhete próprio. Se os
   cristais tiverem que ser um item de verdade, isso é outro custo (catálogo, inventário, venda). A
   versão barata paga em dinheiro.
3. Em `CaveBuild`, um anel de rocha ao redor do morro (pedras escuras, sem mexer no relevo). O anel
   entra no mesmo lote de geometria do morro, montado no mesmo passo. Um raio maior que `CAVE_RADIUS`
   exige uma reserva própria em `reserved()`.
4. Um brilho fraco nos cristais com material sem luz própria (emissão no material, pré-aquecido junto
   com as outras pedras). Nenhuma luz nova. Se alguém quiser uma luz, ela passa pelo `LightBudget`.
5. Estender `tests/test_desert_wilds.gd`: a caverna aparece, o recibo sai uma vez, a torre aponta e
   para de apontar depois do saque.

**Desempenho.** Mesmo custo de montagem de uma caverna atual, mais o anel. Medir no export release com
`GETECO_DESERT_WILDS` ligado e desligado, passando pela cratera. O passo de montagem precisa ficar com
o span existente e abaixo de ~2 ms.

**Escolha que fica com você.** Cristal como dinheiro (barato) ou como item vendável (mais caro).

## 2. Refúgio da Serra (Serra Gelada)

**O que é.** Uma cabana de madeira sem interior, com fogueira, banco e um catre. A fogueira esquenta
(o sistema de frio da serra) e o catre deixa dormir até as 7h, curar e salvar, de graça. A avalanche
que aparecia junto na carta fica de fora: é outro custo.

**O que já existe e é reaproveitado.**
- `world/mountain_detail/forge/ForgeHermitCabin.gd` (89 linhas): cabana sem interior, pátio,
  fogueira, `FOOTPRINT` reservado no terreno e trilha de acesso (`approach()`). É o molde.
- `world/regions/NativeRegion.gd`: registra a cabana (`_record`), reserva o terreno
  (`terrain.configure(..., FOOTPRINT)`), acrescenta a trilha (`walkways`) e monta a cabana no streaming.
  O refúgio repete esses quatro ganchos.
- `runtime/cold/OriginalHeatSources.gd`: a lista de fontes de calor. As coordenadas são em pixels V1:
  `ponto_v1 = posição_mundo × 16 − OFFSET`. Conferido com o Mestre Aurélio: (702,6; −841,6) × 16 −
  (4300; −4960) = (6941,6; −8505,6).
- O descanso: `DesertRoadside._rent_room` (dorme até as 7h, cura, salva) e o "Descansar até as 20h"
  do Horizonte em `DesertRuntime`. Ambos bloqueiam com estrela de polícia ou save bloqueado.

**Passos.**
1. Escolher o lugar: na trilha entre a Vila e as pistas, perto da largada da Descida da Meia-Noite.
   Precisa de chão que o terreno possa aplanar e não pode ficar no traçado da corrida nem do jipe.
2. `world/mountain_detail/MountainRefuge.gd` no molde da cabana do Aurélio: `CENTER`, `FOOTPRINT`,
   `FIRE`, `approach()`, geometria em lote (`GEO`), sem morador.
3. Os quatro ganchos em `NativeRegion` e uma linha `mountain_refuge` em `OriginalHeatSources`.
4. Descanso: em vez de copiar o código do motel uma terceira vez, extrair um ajudante pequeno (por
   exemplo `rest_until(session, hour)`) e usá-lo no Motel Oásis, no Horizonte e no refúgio. A
   extração mexe em dois fluxos que já funcionam e precisa dos testes deles verdes.
5. Marcador no mapa em `WorldMapData._mountain_markers` (ícone `home`).
6. Teste novo `tests/test_mountain_refuge.gd`: a fogueira aparece como fonte de calor, o descanso leva
   às 7h, cura e salva, e recusa com estrela de polícia. Rodar também os testes do roadside e do deserto
   que cobrem os descansos atuais.

**Desempenho.** A fogueira é a única coisa nova com custo: partícula ou chama pré-aquecida (como a do
Aurélio) e, se tiver luz, pelo `LightBudget`. Interruptor `GETECO_MOUNTAIN_REFUGE` para o A/B no
export release, na rota da serra.

**Escolha que fica com você.** O ponto exato, e se o descanso é de graça (proposta) ou cobra algo.

## 3. Observatório da serra (Serra Gelada)

**O que é.** Um mirante no alto das pistas, na chegada do teleférico, com um binóculo fixo. De lá se vê
a serra, o mar e o deserto ao longe. Na edição 2.0 é o lugar de onde se vê a neblina de Brumal; até
Brumal existir, o binóculo só aponta para o que já existe.

**O que já existe e é reaproveitado.**
- `runtime/coastal_lookout/CoastalBinoculars.gd`: entra e sai do binóculo, zoom de 46° a 12°, giro
  limitado, câmera própria e máscara (`BinocularOverlay`, `binocular_mask.gdshader`). Empresta só a
  entrada; não mexe em posição nem em save.
- `runtime/coastal_lookout/CoastalLookoutRuntime.gd`: monta os modelos fora da árvore sob a cortina,
  em partes com um quadro entre elas (a auditoria de 16/10 achou 11 s num quadro só antes disso). Usa
  `DesertHorizon` e `LookoutDistantCity` como cenário distante.
- `tests/test_coastal_binoculars.gd` e `tests/test_lookout_panorama.gd` como base dos testes.

**O acoplamento a resolver.** O binóculo exige `region_id == "harbor"` (`CoastalBinoculars._eligible`,
linha 49) e o runtime também (`CoastalLookoutRuntime`, linha 112). É preciso passar a região e o lugar
na configuração em vez de fixar Harbor, mantendo o comportamento atual do mirante costeiro.

**O risco principal.** Câmera longe mostra vazio onde o streaming não carregou nada (visto no trailer de
17/10). O mirante costeiro resolveu isso com cenário distante próprio. O observatório precisa do mesmo:
1. limitar o giro do binóculo a uma faixa que o jogador realmente veja carregada; e
2. ver se `DesertHorizon` e `LookoutDistantCity` servem vistos da serra. Se não servirem, isso vira o
   item mais caro deste plano e deve ser medido antes de seguir.

**Passos.**
1. Generalizar `CoastalBinoculars` (região e lugar por configuração). Rodar os testes do mirante
   costeiro antes de seguir.
2. `world/mountain_detail/MountainObservatory.gd`: plataforma de pedra com guarda-corpo e o pedestal
   do binóculo, ao lado da estação de cima do teleférico. Reserva de terreno como as outras cabanas.
3. Runtime pequeno da serra, ou um segundo modo do runtime do mirante, que monta os modelos sob a
   cortina, como o costeiro.
4. Fotos pelo binóculo em quatro direções, de dia e de noite, para conferir se há vazio.
5. Marcador no mapa e teste próprio copiado de `test_coastal_binoculars.gd`.

**Desempenho.** Nada pesado na primeira aparição: os modelos são montados sob a cortina e retidos. A
troca de câmera não pode compilar shader (a máscara do binóculo já está no jogo). Interruptor
`GETECO_MOUNTAIN_LOOKOUT` para o A/B no export release.

**Escolha que fica com você.** Se o observatório espera Brumal existir para ter algo a mostrar ao norte,
ou se sai antes, apontando só para o mar e o deserto.

## Ordem sugerida

1. **Cratera:** quase só dados, valida rápido.
2. **Refúgio:** introduz o ajudante de descanso, que depois serve a outros lugares.
3. **Observatório:** começa pela prova do vazio ao longe; só segue se o cenário distante funcionar.

Cada uma fecha com `tools/run_core_suite.sh` antes do commit e com A/B no export release pelo próprio
interruptor `GETECO_*`, conforme [HOW-TO-DEVELOP](HOW-TO-DEVELOP.md).
