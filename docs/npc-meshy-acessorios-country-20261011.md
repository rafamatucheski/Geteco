# Acessórios de cabeça e o pessoal country do motocross (11/10/2026)

Continuação de [npc-meshy-policia-20261010.md](npc-meshy-policia-20261010.md).

## Acessórios

`assets/civilians/MeshyAccessories.gd` desenha peças pequenas e compartilhadas com o mesmo construtor do kit
(boné, gorro, fedora, chapéu de vaqueiro novo, chapéu de palha novo, óculos escuros). `MeshyBodyRig.attach_accessories`
prende cada peça ao osso `Head` com um `BoneAttachment3D`: a peça segue a cabeça na animação, na queda e na morte.
O alinhamento usa o topo da malha do corpo (`KIT_CROWN`), então serve a qualquer corpo do Meshy.

- `CivilianModel.body_accessories` (lista de `{kind, color, band}`) é definida antes de entrar na árvore;
  `RigBodySwap` repassa `look.body_accessories` (polícia).
- Pedestres de rua: `CivilianBodyCatalog.roll_accessories` sorteia por identidade ~20% chapéu/boné/gorro e ~14%
  óculos escuros (medido: faixa esperada no teste).
- Polícia: detetive pode usar fedora (55% homem, 35% mulher) e o FBI óculos escuros (85%), via `accessories` em
  `PoliceBodyCatalog.ENTRIES`.

## Pessoal country

`assets/civilians/meshy/country/` tem 4 corpos novos (2 homens com chapéu de vaqueiro na malha, 2 mulheres sem
chapéu; camisa xadrez, jeans, botas), ~4,1 mil triângulos, 22 ossos, textura 1024. `CountryBodyCatalog.apply`
(identidade → corpo, brilho/matiz suaves, chapéu de vaqueiro/palha só nas mulheres, óculos 22%) é chamado pelo
`MotocrossSpectator`, que cobre arquibancadas, boxes e beira de pista. `GETECO_NO_MESHY_BODIES=1` volta ao corpo do kit.

## Créditos

Duas malhas (40), 4 texturas (40) e 2 de teste da fila anterior: 680 gastos de 800 autorizados no total do trabalho
de NPCs (saldo 601). Remesh e rig grátis.

## Verificação

- `tests/test_meshy_accessories.gd`: 291 verificações (cada corpo × 6 peças: altura junto ao topo do crânio, centrada,
  presa ao osso, um corpo + uma peça visíveis, gira junto com a cabeça) + sorteio determinístico e proporções.
- `tests/test_country_catalog.gd`: contrato completo dos 4 corpos (altura, pés no chão, andando, mãos no alvo,
  sentar) e 24 espectadores reais do parque (todos com corpo do Meshy, sentados baixos, em pé altos, rollback).
- Regressão verde: `test_police_meshy_body` (ignora peças `Acc_`), `test_pedestrian_catalog`, `test_meshy_mechanic_body`,
  `test_mixamo_npc_death`.
- Capturas: `evidence/npc-meshy/accessories/` e `evidence/npc-meshy/country/` (fora do Git).
- Desempenho (palco de 80 pedestres com acessórios, 6 rodadas alternadas): mediana p50 4,70–5,16 ms (Meshy) contra
  4,27–6,81 ms (kit), draw calls 189 contra 2084; muito ruído entre rodadas, sem veredito. Medição do parque de
  motocross em jogo real **não** foi feita.

## Pendências

- Ombro "em asa" nos corpos com braços muito abertos (terno e country); dedos esticados.
- Só 2 homens e 2 mulheres country; falta idoso/magro e roupa de piloto/mecânico de paddock.
- Peças de cabeça não têm LOD próprio; os espectadores já param o próprio IK (`still`).
- Óculos/chapéu não foram revistos no jogo real, só em palco e testes.
