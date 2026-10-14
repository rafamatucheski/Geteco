# Redução de draw calls em paralelo — 2026-10-14

Plano para vários agentes ao mesmo tempo, no mesmo formato de `docs/otimizacao-paralela-20261013.md`.
Cada tarefa tem **dono de arquivos exclusivo**. A medição de desempenho é feita **uma vez, no fim, por um
só agente** (tarefa F2), porque medições concorrentes se contaminam.

## Por que (o que já está medido)

Logs de 123 sessões (13–14/10), janelas de 1 s com o jogo em foco. Mediana de draw calls por trecho de 64 m
no **export release**:

| Lugar | Draw calls | Quadro p50 |
|---|---:|---:|
| Ponte da fundição + canal (x 192–256, z 0–64) | **2.586** | 11,2 ms |
| Cais do Northstar (x 192–256, z 64–128) | **2.140** | 12,0 ms |
| Oeste do porto (hospital, polícia, rodoviária, restaurante) | 600–860 | 11–13 ms |
| Resto da cidade | 480–650 | 7–10 ms |
| Serra e sul do porto | 150–250 | 6,9 ms (limite de 144 Hz) |

Porto: mediana 480, p95 **1.461**. Serra: ~200. Fora dos pontos quentes a GPU gasta ~2,2 ms e o render na CPU
~1,3 ms: **o objetivo é tirar as quedas dos pontos quentes e dar folga**, não dobrar o fps da cidade inteira.

Censo dos trechos (`tests/measure/census_chunk_draws.gd`: superfícies visíveis entregues ao renderizador;
cada uma é ~1 draw call, mais 1 por cascata de sombra quando projeta sombra):

| Trecho | Superfícies | Com sombra | Maiores culpados |
|---|---:|---:|---|
| (3,0) ponte | 234 | 208 | `FoundryBridge3D` (`HarborBridge3D.gd`): **196 malhas soltas, todas com sombra** |
| (3,1) cais | 347 | 332 | ~35 pilhas de carga `ship_cargo` (cache de registros) × 6 malhas = 210; 51 peças soltas; navio (`PortShipDressing3D`, `NorthstarCargoHoist3D`) ~45 |
| (1,1) oeste | 486 | 281 | hospital 80, rodoviária 57, Apartments 42, helicóptero estacionado 36, árvores 35, polícia 34, oficina 33 |
| (0,1) oeste | 345 | 276 | mesas do `AnchorTable` (`HarborRestaurantTerrace3D`) **104**, lavanderia 83, CornerDiner 61, árvores 32 |

Referência de design: GTA Vice City (reVC) — cada pedaço do mapa é um modelo com texturas num dicionário
compartilhado (TXD), sombras de objetos são blobs/simples, LOD e fade a ~20 m, mobiliário instanciado.

## Regras comuns (todas as tarefas)

1. Leia `CLAUDE.md` e `AGENTS.md`. Comentários e logs em português; identificadores em inglês.
2. **Só edite os arquivos da sua tarefa** (coluna "Dono de"). Precisa mexer em outro? Pare e reporte.
   São da tarefa, sem autorização extra: testes e scripts de medição novos que ela cita, ajustes de leitura em
   testes existentes por causa da mudança (sem mudar a intenção), `evidence/<pasta da tarefa>/` e o relatório
   `docs/otimizacao-20261014/<ID>.md`.
3. **Arquivos bloqueados para todos**: `tests/measure/benchmark_west_route.gd`,
   `tests/measure/census_chunk_draws.gd` (use, não edite), `world/editing/world_edits.json`,
   `world/editing/*` e `addons/geteco_world_editor/*`.
4. **Interruptor obrigatório** por variável de ambiente (padrão de `world/urban_detail/GroundCut.gd`), ligado
   por padrão, `=0` restaura exatamente o caminho de hoje. Nome na tabela. A F2 usa isso para o antes/depois.
5. **Editor de mundo edita tudo** (`docs/world-editor.md`, seção de 10/10). Fundir ou instanciar não pode
   mudar o id das peças: **não renomeie nós, não mude a ordem nem a posição de construção** das fontes. Funda
   **depois** que o trecho terminou de montar e as edições foram aplicadas (o mesmo ponto em que
   `HarborBuildingBatch` funde os prédios hoje), escondendo/liberando as fontes só então. Posição/id nunca pode
   depender de transformação de MultiMesh (a prévia roda headless e lá ela devolve identidade). Rode
   `tests/test_world_units.gd` e `tests/test_play_here.gd`.
6. **Fica separado, nunca fundido**: porta, vidro, letreiro/neon que acende, peça com script de interação,
   contêiner saqueável (`LootablePortContainer`), quebrável (`FragileProps3D`), tudo o que `TunnelCutaway` e
   `ExteriorReveal` procuram, colisão (fundir só o visual; colisão continua como está ou vira menos caixas
   exatas, nunca maiores).
7. **Não meça tempo de quadro nem fps.** Contagens (superfícies, malhas, sombras, materiais, nós) podem,
   inclusive headless: use `census_chunk_draws.gd` antes/depois no trecho da tarefa. **Capturas visuais**
   (renderizador real, não headless) do lugar antes/depois são obrigatórias, de dia e à noite; PNGs ficam em
   `evidence/<pasta>/` fora do Git, o relatório cita os caminhos.
8. `GODOT="D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"`;
   testes: `"$GODOT" --path . --script res://tests/<nome>.gd -- --no-save`. `dotnet build Harbor.csproj` se mexer em C#.
   Censo: `"$GODOT" --headless --path . --script res://tests/measure/census_chunk_draws.gd -- --no-save "--chunks=3,0;3,1"`.
9. Verificação mínima antes do commit: `test_regions`, `test_bridge_approach_terrain`, `test_native_driving`,
   `cold/test_admission`, `test_world_units`, `test_tunnel_cutaway` e os testes da tarefa. Falha que também
   acontece com o interruptor desligado não é sua: registre.
10. **Commit só dos seus arquivos** (`git add` explícito, nunca `-A`), mensagem em português com porquê,
    contagens, o que foi verificado e o que não foi. Nunca `git stash/checkout/reset/clean`, nunca push, nunca export.
11. **Relatório** em `docs/otimizacao-20261014/<ID>.md`: arquivos, interruptor, o que mudou, censo antes/depois,
    capturas, testes, o que não foi verificado, riscos visuais para o testador.

## Tarefas

Fase 1 roda toda em paralelo. Fase 2 começa só depois que a fase 1 estiver commitada.

| ID | Fase | Tarefa | Dono de | Interruptor |
|---|---|---|---|---|
| D1 | 1 | Sombra por casca: uma malha de silhueta por trecho projeta a sombra; detalhes param de projetar | novo `world/chunk_shadow/*`, chamada em `world/regions/NativeRegion.gd` (só a ligação no fim do trecho) | `GETECO_SHADOW_SHELL=0` |
| D2 | 1 | Ponte da fundição fundida por material | `world/urban_detail/HarborBridge3D.gd` | `GETECO_BRIDGE_MERGE=0` |
| D3 | 1 | Cais do Northstar: pilhas de carga em MultiMesh e navio estático fundido | `assets/regions/source/world/harbor/HarborPortModel3D.gd`, `world/regions/PortShipDressing3D.gd`, `world/regions/NorthstarCargoHoist3D.gd`, `world/regions/OriginalSouthPort.gd` | `GETECO_PORT_MERGE=0` |
| D4 | 1 | Mobília, terraços e árvores: fusão/instância e sem sombra nos miúdos | `world/urban_detail/{HarborRestaurantTerrace3D,HarborPublicRealm3D,HarborProp3D,HarborPropInstancing}.gd` | `GETECO_FURNITURE_MERGE=0` |
| D5 | 1 | Assar mais tipos de prédio (estende a P6) | `world/urban_detail/UrbanBuildingFactory.gd`, `world/urban_detail/HarborBuildingBatch.gd`, `tools/building_bake/*`, `assets/buildings/baked/*`, `assets/regions/source/world/harbor/hospital/*` | `GETECO_BAKED_BUILDINGS=0` (já existe) |
| D6 | 1 | Auditoria e deduplicação de materiais (prepara o atlas) | `assets/urban_detail/UrbanMaterials.gd`, `world/city_look/CityLookMaterials.gd`, novo `tools/material_audit/*` | `GETECO_MATERIAL_DEDUPE=0` |
| D7 | 2 | Trecho assado: geometria estática restante do trecho numa malha por material | novo `world/chunk_bake/*`, `world/regions/NativeRegion.gd` | `GETECO_CHUNK_BAKE=0` |
| F2 | fim | Integração, censo, benchmark (inclui rota pela ponte e cais) e export | benchmark, evidências | Claude |

---

### D1 — Sombra por casca

- **Começo**: em `NativeRegion.gd`, ache onde o trecho termina de montar (`_build_chunk` e a finalização
  que agenda `HarborBuildingBatch`). Rode o censo em (3,0), (3,1), (1,1), (0,1) e anote "com sombra".
- **Meio**: depois do trecho pronto, monte **uma** `MeshInstance3D` por trecho com
  `cast_shadow = SHADOW_CASTING_SETTING_SHADOWS_ONLY`, feita das caixas/volumes principais dos prédios, ponte,
  navio e pilhas de carga (AABB transformado de cada fonte grande, ou a malha simplificada dela). Desligue
  `cast_shadow` nas fontes que a casca cobre. Peças pequenas (< 1,5 m) não entram na casca nem projetam.
  Árvores ficam como estão nesta tarefa. Atores e veículos não mudam.
- **Fim**: censo antes/depois; captura de dia (sol baixo e alto) nos quatro trechos e na ponte.
- **Aceitar se**: sombras por trecho caem para poucas superfícies; a forma da sombra dos prédios continua
  reconhecível; nada flutua sem sombra que antes tinha (prédio, ponte, navio).
- **Risco para o testador**: sombra "quadrada" demais ou sombra que não acompanha um volume.

### D2 — Ponte da fundição fundida

- **Começo**: `HarborBridge3D.gd` monta `FoundryBridge3D` com 196 `MeshInstance3D`. Liste quais peças são
  estáticas e quais têm papel (colisão, corte do túnel, iluminação, caminho de pedestre).
- **Meio**: funda as malhas estáticas por material (`SurfaceTool`/`ArrayMesh`, como `HarborBuildingBatch` e
  `tools/fleet_fixups`), no fim da montagem; mantenha colisões e qualquer peça que `TunnelCutaway` ou o canal
  usem. Se o mesmo material aparece em cópias com só a cor diferente, use cor por vértice.
- **Fim**: censo (3,0) antes/depois; capturas de cima e de baixo da ponte, de dia e à noite, e passando de carro
  pelo túnel/canal.
- **Aceitar se**: ponte de ~196 para ≤ 15 superfícies; visual igual; travessia de carro e a pé igual
  (`test_bridge_approach_terrain`, testes do canal/túnel).
- **Risco para o testador**: peça da ponte sumida, ponte "piscando" ao passar pelo túnel.

### D3 — Cais do Northstar

- **Começo**: `ship_cargo` é montado por `HarborPortModel3D.gd`/`OriginalSouthPort.gd` e fica no cache de
  registros de `NativeRegion` (`CACHED_PORT_MODELS`, meta `record_cache_key`): ~35 pilhas de 6 malhas no trecho
  (3,1). O navio: `PortShipDressing3D.gd` (detalhe e guindaste), `NorthstarCargoHoist3D.gd`.
- **Meio**: pilhas iguais viram **MultiMesh por modelo/material** (uma chamada para todas as pilhas iguais),
  respeitando a regra 5: a lista de colocações é decidida antes do MultiMesh nascer e o id da peça não vem do
  MultiMesh. As que forem saqueáveis ou se mexem (guincho, carga em movimento) ficam separadas. Partes estáticas
  do navio fundem por material. Funciona com o cache de registros (o nó guardado e reaproveitado continua válido).
- **Fim**: censo (3,1) antes/depois; capturas do cais de dia e à noite; o guincho e a carga do Northstar
  funcionando (testes do Northstar/porto que o grep achar).
- **Aceitar se**: (3,1) de ~347 para ≤ 120 superfícies; cache de registros continua funcionando ao sair e
  voltar; carga e guincho intactos.
- **Risco para o testador**: contêiner que some ao voltar ao cais, carga que não reage.

### D4 — Mobília, terraços e árvores

- **Começo**: `HarborRestaurantTerrace3D.gd` (AnchorTable: 104 malhas), `HarborPublicRealm3D.gd`,
  `HarborProp3D.gd` (árvores: 32–35 malhas por trecho), `HarborPropInstancing.gd` (instância de postes de hoje).
- **Meio**: mesas, cadeiras, guarda-sóis e floreiras iguais viram MultiMesh por modelo, no mesmo esquema de
  `HarborPropInstancing` e respeitando a regra 5 (edita-se a lista antes do lote nascer). Árvores iguais viram
  MultiMesh por espécie (tronco e copa). Miúdos (< 1,5 m) sem sombra. Quebráveis ficam fora.
- **Fim**: censo (0,1) e (1,1) antes/depois; capturas do terraço e de uma rua arborizada, dia e noite, e com
  vento se as árvores balançam.
- **Aceitar se**: terraço de 104 para ≤ 12 superfícies; árvores de ~35 para ≤ 6 por trecho; editor ainda
  move/apaga uma mesa e uma árvore (`test_world_units`, testes de props do editor).
- **Risco para o testador**: árvore sem balanço, mesa que não quebra mais quando batida.

### D5 — Assar mais tipos de prédio

- **Começo**: relatório `docs/otimizacao-20261013/P6.md` e `tools/building_bake/*` (só `UrbanCommercialBuilding`
  hoje). Censo no oeste: hospital (`HarborHospitalModel3D`) 80, lojas (`UrbanShopfrontBuilding`: lavanderia 83,
  CornerDiner 61), oficina (`UrbanIndustrialBuilding`) 33, polícia (`UrbanServiceBuilding`) 34.
- **Meio**: estenda o bake aos tipos acima, com o mesmo contrato da P6: chave por id/dimensão/semente, fallback
  automático quando a fonte do gerador muda, proxy LOD a 50 m, portas/vidros/letreiros separados, colisão com
  as mesmas caixas exatas. Regenere os assados.
- **Fim**: censo (0,1) e (1,1) antes/depois; contratos do bake (geometria igual, acesso, portas) para cada
  tipo; capturas de perto e atravessando 48–52 m.
- **Aceitar se**: cada tipo cai ≥ 25% em superfícies; acesso a prédios igual (`test_harbor_building_access`,
  `test_harbor_access_exteriors`, `urban_detail/test_urban_building_factory`).
- **Risco para o testador**: prédio diferente, porta que não abre, troca visível do LOD a 50 m.

### D6 — Auditoria e deduplicação de materiais

- **Começo**: ferramenta `tools/material_audit/audit.gd` que, por trecho, conta materiais distintos e agrupa
  os que diferem só em cor/albedo, rugosidade ou parâmetro escalar.
- **Meio**: em `UrbanMaterials.gd`/`CityLookMaterials.gd`, materiais iguais passam a ser **a mesma instância**
  (cache por parâmetros), e variação só de cor passa para cor por vértice ou `instance_shader_parameter` onde o
  shader permitir. Isso deixa a fusão de prédios e a D7 juntarem mais. Não troque shaders nem a aparência.
- **Fim**: relatório da auditoria (materiais por trecho antes/depois, top 20 duplicados); censo dos quatro
  trechos; capturas de dia, noite e chuva (o molhado da chuva usa esses materiais).
- **Aceitar se**: materiais distintos por trecho caem ≥ 30%; nenhuma mudança visual nas capturas; testes de
  iluminação e clima (`test_city_local_lighting`, `test_weather_*`, `test_coastal_*`) passam.
- **Risco para o testador**: cor de prédio trocada, chuva sem brilho num material.

### D7 — Trecho assado (fase 2)

- **Começo**: só depois de D1–D6 commitados. Censo dos quatro trechos já com elas.
- **Meio**: no fim da montagem do trecho (depois das edições aplicadas e das fusões das outras tarefas), junte
  **toda a geometria estática restante** do trecho em uma malha por material, respeitando as regras 5 e 6.
  Cache em disco por trecho opcional, com chave que inclua a assinatura das edições do trecho (edição nova →
  monta pelo caminho de hoje até regenerar). Atenção ao corte do túnel e ao `ExteriorReveal`.
- **Fim**: censo antes/depois em pelo menos 8 trechos (os quatro acima, serra e deserto); custo de montagem do
  trecho medido headless **como indicativo** (mediana de 10), único tempo permitido; capturas.
- **Aceitar se**: trecho comum ≤ 250 superfícies e ponte/cais ≤ 300; montagem não fica mais lenta que hoje;
  editor e "Jogar aqui" funcionam.
- **Risco para o testador**: travada ao entrar num trecho novo, peça que não some no corte do túnel.

### F2 — Integração, medição e release (Claude, no fim)

Censo de todos os trechos tocados; benchmark controlado no circuito do oeste **e numa rota nova pela ponte e
pelo cais**, com todos os interruptores desligados × ligados × um por vez; dia, noite e chuva; editor e export.
Relatório final em `docs/otimizacao-20261014/F2.md` e export para o teste do usuário.

## O que esperar no fim (estimativa, a confirmar na F2)

| | Hoje | Fase 1 | Fase 1 + D7 |
|---|---:|---:|---:|
| Trecho comum (draw calls na tela) | 480–860 | ~250–400 | ~100–200 |
| Ponte / cais | 2.100–2.600 | ~500–700 | ~200–300 |

Fora dos pontos quentes o ganho de fps é moderado (a CPU de lógica domina); nos pontos quentes as quedas de
11–12 ms devem sumir.
