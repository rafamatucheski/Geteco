# Obras urbanas em níveis — plano (27/09/2026)

Pedido do usuário: viaduto e túnel dentro da cidade (Harbor). Ideias discutidas e
escolhidas em 27/09. A **passarela (4)** foi feita em 27/09; as outras três ficam
para as próximas sessões, na ordem abaixo. Coordenadas em metros do editor (X, Z).

## Estado atual que as obras precisam respeitar

- Rua do editor é plana: `points` só tem X/Z (`WorldEditData.validate_entity`).
- Trânsito cria cruzamento onde duas ruas se cruzam no plano
  (`NativeTrafficRoutes.gd:35`, `Geometry2D.segment_intersects_segment`).
  `WorldRoadJoins.resolve()` (ver `docs/edited-traffic.md`) já diz não unir "vias em
  alturas diferentes" — conferir como decide a altura antes de estender.
- Asfalto de rua é gerado em `NativeRegion._build_road_surfaces` a `top = .026`.
- Referência de obra elevada que já funciona: `HarborBridge3D.gd` (ponte da
  `foundry_avenue` sobre o canal, x≈200–290, z=25) e a subida da `mountain_pass`.
- Câmera ortográfica alta, olhando para o norte (`scripts/CameraRig.gd`); já existe
  silhueta de personagem oculto (`gameplay/PoliceOcclusionSilhouette.gd`,
  `world/city_look/occluded_silhouette.gdshader`).
- Postes/decoração de calçada automáticos: `CityChunkDressing._sidewalk_lamps` e
  `_building_surroundings` usam o retângulo de prédios — obra que cruza rua **não**
  pode entrar como `building` (por isso a passarela é `prop`).

## 4. Passarela de pedestres — FEITA em 27/09

- `world/urban_detail/UrbanFootbridge3D.gd`: tabuleiro a 5,6 m (4,5 m livres sob as
  vigas), vão livre = comprimento − 2 × (escada 8,7 m + patamar 1,6 m), escadas de 30
  degraus (18 × 29 cm, 32°), guarda-corpo com tela, colisão andável (rampa lisa sob os
  degraus) e paredes invisíveis nos guarda-corpos. 5 lotes MultiMesh, sem luzes.
- Editor: objeto `prop` modelo `footbridge` ("Passarela de pedestres" na biblioteca),
  largura 1,8–6 m e comprimento total 29–60 m; altura fixa.
- Teste: `tests/test_footbridge.gd` (altura livre, pilares fora da calçada, cápsula
  sobe/atravessa/desce, guarda-corpo segura, validação do documento).
- Colocada no mapa: `market_street` em x=126, z=78, rotação 0 (praça ao norte, piso
  livre entre a clínica e a `warehouse_way` ao sul). Backup do documento anterior:
  `world/editing/world_edits.json.antes-passarela-20260927`.
- Pedestres: `gameplay/crowd/FootbridgeCrossers.gd` (chamado no ciclo de população de
  `ProductionWorld`) mantém 3 civis por passarela carregada a até 90 m do jogador, em
  circuito de ida e volta pela escada e tabuleiro. Entram em `world.people` (reagem a
  tiro como os demais) e são repostos. Teste no jogo real:
  `tests/test_footbridge_crossers.gd -- --no-save` (5 rodadas: os 3 subiram,
  atravessaram e desceram em todas; em 1 rodada um civil ficou parado > 1 s, sem
  reproduzir nas outras 4 — provável encontro de frente no tabuleiro de 2,6 m).
- Pendências: sem iluminação própria à noite; civis comuns de calçada continuam não
  usando a passarela (só os do circuito).

## Base comum para 2, 1 e 3: nível/altura de rua (fazer primeiro)

1. **Esquema**: campo opcional por ponto `elevation` (m) ou `levels` na rua
   (`[[x, z, y], …]` aceito ao lado do formato atual). Validação em
   `WorldEditData` com limites (−8 a +12 m) e rampa máxima (ex.: 8 %).
2. **Superfície**: `_build_road_surfaces` e `ROUTE_GEOMETRY` interpolam Y por ponto;
   calçada/meio-fio acompanham ou são suprimidos no elevado/túnel.
3. **Grafo**: cruzamento só quando as duas vias têm a mesma altura no ponto
   (|Δy| < 1 m). Revisar `NativeTrafficRoutes`, `TrafficJunctions`, `YieldRoadModel`,
   `OvertakePlanner` e `CityChunkDressing` (faixas de pedestre e semáforos em
   junções).
4. **Editor**: campo "Altura" no ponto selecionado da rua e prévia 3D com rampa.
5. **Testes**: carro físico atravessando por cima e por baixo sem virar no
   cruzamento falso; NPC de trânsito idem; `test_edited_road_joins`.

## 2. Túnel do canal — FEITO em 28/09 (1ª versão)

- `world/urban_detail/CanalTunnel3D.gd` (+ `canal_tunnel_wall.gdshader`): z=63, de
  x=140,75 (warehouse_way) a x=343,25 (east_union_avenue). Em z≈105 a casa Quayside
  (lugar com interior) fecha a vala; z=63 é o corredor livre entre ColdStorage e
  market_street. Na ilha a vala ocupa a exchange_lane (4,5 m, fora do grafo).
- Rampas de 12,5 % (40 m entre warehouse_way e cais não comportam 10 %), fundo a −6 m,
  vão livre ≥ 3,5 m, tubo com teto/parede sul de vidro sob o canal e o Northstar.
- Fora do grafo de ruas: sem cruzamento falso com a quay_boulevard; trânsito NPC não
  usa o túnel. Chão/mar/calçadas recortados por `CanalTunnel3D.carve_chunk`/`outside_land`
  e `HarborOcean` (WATER_CUT). Teste: `tests/test_canal_tunnel.gd -- --no-save`.
- Pendências: NPC/polícia no túnel, mapa/minimapa, campo "altura" no editor.
- **Câmera no túnel (28/09):** `scripts/CameraRig.gd` cresce `_tunnel_blend` com a
  profundidade do alvo (0,6→3,2 m) e, junto com o zoom, levanta a inclinação para 70°
  (`TUNNEL_OFFSET`, mesma distância ao foco). A 45° o chão ao sul da vala tapava o carro
  a partir de ~4,3 m de fundo. `world/urban_detail/TunnelCutaway.gd` deixa translúcido
  (alfa 0,14) o que fica entre a câmera e o tubo — laje/teto do trecho coberto, Northstar
  sobre o canal, prédios, postes, letreiros — e devolve tudo ao sair. No renderizador
  Mobile `GeometryInstance3D.transparency` não funciona: usa uma cópia do material por
  material de origem, com um alfa só atualizado por quadro; `ShaderMaterial` (mar, atores)
  fica de fora. Rescan a cada 0,4 s (~0,6 ms, pior 1,2 ms; medido com outras instâncias do
  Godot abertas, não é medição de desempenho limpa). Testes: `tests/test_tunnel_cutaway.gd`
  (sintético) e `tests/test_tunnel_camera.gd -- --no-save` (jogo real). Não coberto: carros
  de trânsito sobre o cais continuam opacos; materiais de origem que mudam durante o corte
  (luz noturna, chuva) só aparecem na cópia na próxima entrada.

### Plano original

- Traçado: lado oeste perto de `medical_garden_lane`/`warehouse_way` (≈ x 150, z 110)
  até a `courtyard_lane` na ilha (x 290, z 112), por baixo da água (≈ 100 m).
- Bocas nas duas margens com rampa descendo a −6 m (≈ 75 m de rampa a 8 %, conferir
  espaço; pode exigir mover prédios/decoração perto das margens).
- Estrutura: caixa de concreto com paredes, teto, faixas, iluminação interna emissiva
  (sem luzes dinâmicas por segmento — orçamento de desempenho).
- Câmera: dentro do túnel o carro fica sob a água/teto. Opções a testar: água e teto
  do trecho ficam semitransparentes quando o jogador entra, ou silhueta do veículo
  pelo shader de oclusão existente.
- Verificar: o mar/canal (`harbor-ocean.md`) não pode desenhar por cima da boca;
  colisão do fundo; polícia e trânsito usando o túnel; mapa/minimapa.

## 1. Elevado da rodovia — depois do túnel

- Continuação da `map2_highway_inbound/outbound` (x 368/382) do fim atual em
  z = −125 até a `foundry_avenue` (z = 25), passando **por cima** da
  `northbank_gateway_avenue` (−125), `northbank_civic_avenue` (−69) e
  `northbank_neighborhood_street` (−22). Rampa de descida antes da `foundry_avenue`.
- Estrutura: tabuleiro com pilares a cada ~20 m, guarda-rodas, juntas; reaproveitar
  materiais de `HarborBridge3D`.
- Conflito: faixa x 360–390 cruza quarteirões do Northbank — listar prédios a mover
  e mostrar ao usuário **antes** de mexer.
- Verificar: trânsito sobe e desce, polícia persegue pelo elevado, sombras sob o
  tabuleiro, postes automáticos não nascem no tabuleiro.

## 3. Viaduto sobre o trilho do porto sul — por último

- Trilhos: `OriginalSouthPort.rails()` gera registros `south_port_rail`
  (`NativeRegion.gd:182`). Mapear onde cruzam `south_port_access/north/west/east`.
- Escolher o cruzamento mais longo ou mais visível e elevar só aquele trecho (≈ 60 m),
  com a mesma base de nível.

## Riscos gerais

- Desempenho: medir Main renderizada antes/depois (nunca headless), p50/p95/p99 em ms.
- Documento do editor: nunca gravar `world_edits.json` com o editor aberto (ele não
  recarrega e sobrescreve no próximo salvar).
- Outras sessões mexem em `world/editing/` e no addon do editor ao mesmo tempo.
