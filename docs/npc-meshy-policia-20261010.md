# Polícia com corpo do Meshy (10/10/2026)

Continuação de [npc-meshy-pedestres-20261010.md](npc-meshy-pedestres-20261010.md). Os 5 escalões do
`PoliceModel` (patrulha, detetive, SWAT, FBI, Exército) passam a usar corpos únicos com pele (skinned) gerados
no Meshy, sem corpo antigo escondido, quando existe corpo compatível no catálogo.

## O que foi integrado

| Corpo (`assets/civilians/meshy/police/`) | Origem no Meshy | Escalões (tom) |
|---|---|---|
| `patrol_m.glb` | policial de patrulha, pele clara, quepe | patrulha |
| `patrol_heavy.glb` | policial de patrulha robusto, pele escura | patrulha |
| `patrol_f.glb` | policial de patrulha feminina, pele morena | patrulha |
| `suit_m.glb` | agente de terno cinza, pele clara | detetive (tom marrom), FBI (tom preto) |
| `suit_f.glb` | agente de terno cinza, pele escura | detetive (tom marrom), FBI (tom preto) |
| `tactical_gray.glb` | tático cinza com capacete/colete, pele clara | SWAT (tom grafite), Exército (tom oliva) |
| `tactical_black.glb` | tático preto com capacete/colete, pele escura | SWAT, Exército (tom oliva) |

Cada GLB tem ~4,1 mil triângulos, 22 ossos (podados de 50–88), textura 1024 e ~0,5 MB. O mesmo arquivo serve a
mais de um escalão: o `PoliceBodyCatalog.ENTRIES` aplica o `tone` (multiplicador de roupa do shader
`civilian_meshy`, que não afeta a pele).

- `PoliceBodyCatalog.pick(tier, look, appearance_index)` pontua biotipo e luminância da pele do policial contra a
  da entrada; empates rodam por `appearance_index` (o mesmo policial mantém o corpo).
- Tático (SWAT/Exército) e terno do FBI usam `baked_equipment`: a malha já tem capacete/colete/joelheiras, então
  o `PoliceModel` **não** anexa o equipamento procedural (ficaria duplicado, e sobre o terno raso o colete do kit
  flutuava). O ponto de rapel (`DescenderAttachment`) continua existindo.
- Patrulha e detetive seguem sem equipamento extra (igual ao kit).
- `GETECO_NO_MESHY_BODIES=1` ou `PoliceBodyCatalog.enabled = false` devolve o corpo procedural.

## Créditos do Meshy

Texto→3D (malhas, incluindo 2 regerações: a policial feminina saiu com 3 figuras na 1ª vez e de saia/pernas
coladas na 2ª) e 7 texturas de 10 créditos; remesh e rig são gratuitos. Gasto acumulado do trabalho de NPCs: 580
dos 800 autorizados (saldo 681 ao baixar), dentro do limite combinado.

## Verificação

Medido (Godot 4.7.2 mono, `--no-save --skip-arrival`, APPDATA isolado):

- `test_police_meshy_body`: 342 verificações, 0 falhas (5 escalões × 8 policiais pelo catálogo real, mira/recarga,
  um só corpo visível, equipamento, juntas da morte do Mixamo, interruptor desligado).
- Verdes: `test_police_variety` (agora fixa o corpo procedural; é teste de geometria do kit),
  `test_police_equipment_geometry`, `test_police_combat_closure`, `test_mixamo_npc_death`, `test_pedestrian_catalog`,
  `test_video_phase2_police_loadouts`, `test_police_visual_prewarm`, `test_police_occlusion_silhouette`,
  `test_armored_guard`, `test_police_crime_contract`, `test_police_ballistics_0922` (com o SCRIPT ERROR
  `State.owns_weapon` já conhecido), `test_maciota_transition_safety`, `garage_guards/test_guards`,
  `police_response/test_ground_response`, `test_dispatch_model_prewarm`.
- Falham **igual com `GETECO_NO_MESHY_BODIES=1`** (preexistentes, não causados por esta mudança):
  `test_police_walkin` (2 falhas de porta), `test_police_combat_flow_0922` (morte: corpo caído),
  `test_police_motor_pool` (7 falhas) e uma checagem de `dispatch/test_dispatch_police` (o resto dos grupos passa).
- Captura visual dos 5 escalões, 4 ângulos cada: `evidence/npc-meshy/police-real/` (fora do Git).

Desempenho (`tests/measure/measure_police_crowd.gd`, palco renderizado 1280×720, 24 policiais mistos em
repouso/mira, 5 s de aquecimento + 30 s, 8 rodadas alternadas old/new na mesma sessão, VSync desligado só no
processo):

| | p50 (ms) | p95 (ms) | draw calls |
|---|---|---|---|
| procedural | 1,82–1,97 (mediana 1,94) | 2,08–2,35 | 874 |
| Meshy | 2,05–2,23 (mediana 2,07) | 2,33–4,65 (2 rodadas com pico) | 370 |

**Sinal de regressão:** p50 ≈ +7% (≈ +0,13 ms para 24 policiais, ~5 µs por policial) e p95 mais ruidoso, acima do
limite de 5%; os draw calls caem 58%. A causa provável é o custo de CPU por policial (esqueleto + `PoseDriver`),
como já visto nos pedestres. **Não declaro aprovado.** Medido só neste palco (câmera parada, sem trânsito,
24 policiais, esta GPU); não medido: resposta policial completa em jogo real. Otimização candidata: um coordenador
único de poses no lugar de um `PoseDriver` por NPC.

## Pendências e limites conhecidos

- **Tático feminino (SWAT/Exército) e biotipo magro** não têm corpo importado: seguem com o corpo procedural.
- **Ombros do terno** (`suit_m`/`suit_f`): na pose de descanso/mira o ombro do paletó estica em "asa" (a malha do
  Meshy veio com braços muito abertos). Aceitável a distância de jogo; correção real = regerar o terno com braços
  a ~25° do tronco.
- `patrol_f` usa shorts/saia curta e botas altas (a regeração com calça comprida voltou com saia). O rig dela foi
  revisado e passou nos testes de alcance de mão, mas a pose de descanso tem uma perna adiantada.
- Consumidores do `PoliceModel` que não foram revalidados em jogo: `PoliceAgent`, `BankGuardModel`,
  `ArmoredGuardModel`, `FortSoldier`, guarda da garagem (`Guard.gd`, prende arma no antebraço antigo), `CobraModel`.
- Desempenho: ver abaixo; só vale para o cenário medido.
