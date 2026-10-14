# Ponte cidade–serra: acabamento (2026-10-14)

O usuário achou a ponte Harbor–Mountain feia ("textura flat, pilares flat"). Tudo em
`world/regions/WorldConnection3D.gd` (`_build_bridge_look`) e em `world/regions/bridge_look/`.
`GETECO_BRIDGE_LOOK=0` volta às caixas lisas de antes (`_build_bridge`, intocado).

## O que mudou

- **Concreto** (`bridge_concrete.gdshader`): procedural, em coordenadas de mundo (relativas ao
  meio da ponte, por precisão no renderizador Mobile), sem textura gerada na CPU. Manchas em três
  escalas, escorrido de chuva nas faces verticais, juntas de concretagem (camadas de 1,2 m e painéis
  de 2,4 m), banda molhada/esverdeada na linha d'água, fundo escurecido, juntas de dilatação sobre
  os apoios e placas de 2 m na calçada. A cor de cada peça vem do vértice.
- **Pilares**: bloco de fundação octogonal largo na linha d'água (com espuma do tamanho dele),
  fuste chanfrado que afina até o tabuleiro, fuste superior e capitel com remate; travessa sob o
  tabuleiro ligando cada par de pilares.
- **Tabuleiro**: fáscia clara com pingadeira, quatro longarinas (antes duas), mureta de concreto
  com topo chanfrado, montantes a cada 2 m, dois tubos intermediários e corrimão sextavado.
- **Postes**: mesmas posições e luzes; base na mureta, fuste octogonal, braço, carcaça escura e
  vidro aceso cuja borda aparece de cima (sem isso o poste sumia à noite na câmera do jogo).

## Contagens (nó `HarborMountainConnection`, script headless)

| | MeshInstance3D visíveis | superfícies | projetam sombra |
|---|---|---|---|
| ponte antes | 186 | 186 | 177 |
| ponte depois | 18 | 18 | 4 |
| nó inteiro (com túnel, inalterado) | 218 → 50 | 218 → 50 | 203 → 30 |

Depois = concreto ×3 trechos, aço ×3, vidro ×2, tabuleiro (`ContinuousBridgeDeck`) ×1, espuma ×8,
asfalto da emenda ×1. Os trechos (cortes em x = 456,25 e 508) existem porque o Mobile aplica no
máximo 8 luzes omni por objeto. ~13,5 mil vértices no total. Montagem na CPU (headless, ponte +
túnel): ~27 ms antes, ~31–35 ms depois.

**Colisão e luzes**: hash dos 48 shapes (tipo, tamanho/pontos, transform global, camadas) e das
12 OmniLight idêntico com o acabamento ligado e desligado.

## Capturas

`evidence/mountain-bridge-look/` (fora do Git), `*_antes_*` com `GETECO_BRIDGE_LOOK=0` e
`*_depois_*`, às 12h e 22h: `cima_vao`, `cima_conector` (câmera do jogo), `pilares`, `pilar_perto`,
`guarda_corpo` (câmera livre). Script: `tests/capture/capture_mountain_bridge.gd`.

## O que não foi medido / pendências

- Tempo de quadro **não foi medido** (pedido). O HUD da captura "depois" mostrou picos de
  ~0,4–0,9 s logo que a ponte aparece (o "antes" mostrou ~25–60 ms nas mesmas tomadas); a hipótese
  é compilação do shader novo, que o pré-aquecimento não conhece. Precisa de medição no export.
- Ao sol do meio-dia o concreto ainda lê claro; o detalhe aparece mais de perto e à noite.
- Peças editadas no editor de mundo (`WorldSessionEdits`, chave `connection`) agora são malhas
  agrupadas; edições salvas de peças antigas da ponte deixam de casar com o acabamento ligado.
- Túnel e encontros da serra não receberam o acabamento.

## Testes (headless, `--no-save`)

Passaram com o acabamento ligado: `test_regions`, `test_bridge_approach_terrain`,
`test_native_driving`, `cold/test_admission`, `test_coastal_protection`,
`test_dispatch_ground_owners`, `test_dispatch_ground_retention`, `test_mountain_tunnel_access`,
`test_mountain_tunnel_camera_safety`, `test_mountain_tunnel_paving`,
`test_road_network_connectivity`, `test_weather_atmosphere_integration`,
`urban_detail/test_harbor_fidelity_contract`, `test_road_access_drive` (`--no-traffic`).
Falham igual com `GETECO_BRIDGE_LOOK=0` (não são desta mudança): `test_north_gateway_integration`
(as mesmas 7 checagens) e `test_pursuit_region_seam` (aeronave/rapel/K9 antes da travessia).
