# Releitura das revisões estáticas — 2026-10-31

Fontes: `static-lifecycle-review.md`, `static-loading-review.md`, `static-runtime-cost-review.md`
(leituras de 2026-09-21). Cada achado foi conferido no código de `viagem-lages-testar`.
Godot não estava disponível: as mudanças foram verificadas só com `gdparse` (sintaxe). O teste
novo `tests/test_static_review_recheck.gd` **não foi executado**. Nada foi medido.

| Achado | Status | Observação |
|---|---|---|
| LIFE-01 entrada a pé sem exclusão mútua | Corrigido antes | `enter_place` recusa com `is_transition_blocked()`/`room` válido e abre `_begin_transition` com token. |
| LIFE-02 desembarque durante transferência de garagem | Corrigido antes | `Driving` consulta `_external_transition_blocked()`; `vehicle_transition_busy` entra no bloqueio central. |
| LIFE-03 save com região/lugar incompatíveis | Corrigido antes | `GameState._location_is_compatible`, recusa em `enter_place` e recuo em `restore_location`. |
| LIFE-04 chegada fora do bloqueio de pausa/save/load/menu | Corrigido antes (guardas) / **corrigido agora** (resto) | Save/load/menu já usam `is_transition_blocked()` (inclui a chegada). Agora: `_begin_disembark` confere geração/árvore/fase após cada `await` (`_disembark_current`), e o botão Carregar da pausa fica desabilitado em `is_transition_blocked()`. |
| Loading P1 JSON fora do export | Corrigido antes | `export_presets.cfg` versionado com `include_filter` dos JSON de runtime. |
| Loading P1 `FleetCatalog.create()` nulo | **Corrigido agora** | `Vehicle._ready` registra erro e cai na carroceria genérica (`VehicleVisual`). |
| Loading P2 slot só com `.tmp` | Corrigido antes | `SessionLaunch` lê `.tmp` válido e marca o slot reutilizável quando só há `.tmp` inválido. |
| Loading P3 atalho por flags sem erro | Corrigido antes | `_start_direct` confere o `Error` e mostra a mensagem. |
| Custo P1 chunk síncrono | Parcialmente tratado; aberto | Terreno da serra em `WorkerThreadPool`, construção com estágios e spans. O que resta é decisão de orçamento que precisa de medição em release. |
| Custo P1 floresta preparada na criação da região | Aberto | Continua síncrona, mas já tem span `region.prepare.records.*`. Pré-calcular ou fatiar depende de medição. |
| Custo P1 interiores recarregados na entrada | Aberto | Spans `native.ready.*` cobrem as etapas; cache/pool de salas pesa memória e precisa de medição. |
| Custo P2 áudio resolve catálogo por quadro | Parcialmente tratado; aberto | Troca de família virou `_sync_engine_family`; sobra um `FLEET.spec()` (consulta a dicionário) por quadro. Sem medição não compensa mexer. |
| Custo P2 `VehicleEquipment._process` incondicional | Aberto | Deixar orientado a eventos mexe em faróis, alarme e luz automática: não é mudança mínima e precisa de A/B. |
| Custo P3 consultas a grupos por polling | **Corrigido agora** (térmica) / aberto (resto) | `HeatPresentation.update_sources` só consulta `native_heat_source` quando habilitada. As consultas de `drivable` e recompensas ficam como estão até haver medição. |

Riscos das mudanças de agora: se `_recover_ride` trocar a geração no meio do desembarque, o
desembarque antigo para sem liberar a física e a visibilidade do jogador. Isso já acontecia
antes quando `active` ficava falso, e a recuperação é do passeio, não do desembarque. O recuo
do veículo esconde uma cena de frota ausente atrás de um carro genérico. Por isso ele grava `push_error`.
