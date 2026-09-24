# Migração V1 → V2: NPCs e rotinas

## Estado desta rodada

Esta entrega implementa um módulo desacoplado em `gameplay/routines_v1/`, mas não o conecta aos arquivos compartilhados do runtime. Portanto, as rotinas **ainda não aparecem no jogo atual** até o integrador aplicar os pontos descritos abaixo. Nenhuma alteração foi feita em `Actor.gd`, `Gameplay.gd`, `Vehicle.gd`, despacho, combate ou arquivos do Claude.

Maciota e o mecânico não fazem parte do catálogo nem do diretor. Os novos atores ambientais não expõem métodos de dano ou morte e não são registrados como alvos de combate. A proteção permanente já existente em `MaciotaPlace.gd`/`DamageProtection.gd` permanece intocada.

## Fontes V1 produtivas consultadas

- Entrada produtiva: `ui/MainMenu.gd` → `world/harbor/HarborGame.tscn` → `HarborPreview.tscn`.
- Cais do cargueiro: `HarborPreview.tscn` → `HarborWaterfront.gd` → `HarborDockCrew.gd` → `HarborDockWorker.gd`.
- Porto Sul: nó `SouthPort` de `HarborPreview.tscn` → `HarborSouthPort.gd:_build_life()` → `HarborDockWorker.gd`.
- Serra produtiva: `systems/RegionTravel.gd` → `MountainPass.gd` → `MountainSettlement.gd` e `MountainVillageLayout.gd`.
- Lodge já acessível: `MountainPass.gd` → `MountainInteriorManager.gd` → `SummitSkiLodgeInterior.gd:_spawn_lodge_npcs()`.
- Apresentação original da serra: `WinterResident.gd` e `WinterResidentModel.gd`.

O V2 foi comparado com `ProductionWorld.gd`, `FullSession.gd`, `Services.gd`, `NativeRegion.gd`, `OriginalSouthPort.gd`, `PlaceCatalog.gd`, `OriginalResidents.gd` e `OriginalResidentData.json`. Os moradores existentes de delegacia, hospital e quartel já estão conectados e não foram duplicados.

`HarborLaunchRoutine.gd` também é alcançado pelo Porto Sul produtivo do V1, mas seus cargueiros/berços móveis não têm equivalente conectado no V2 atual. A rotina não foi cadastrada isoladamente para não criar carregadores trabalhando em um mecanismo ausente. Os operadores do teleférico e a instrutora de `MountainSkiArea.gd`/`ResortPromenade.gd` seguem a mesma regra: aguardam a migração do mecanismo/local correspondente.

## Arquivos e funcionalidade

- `RoutineCatalog.gd`: conserva as três rotas do cargueiro, os 32 postos/rotas/turnos do Porto Sul, os 23 moradores nomeados da serra e os três residentes do lodge. Coordenadas V1 usam a escala produtiva de 16 px/m e o mesmo deslocamento da serra usado por `PlaceCatalog.gd`.
- `DockWorkerModel.gd`: reaproveita `CivilianModel.gd` e porta capacete, colete e faixas refletivas de `HarborDockWorker.gd`.
- `V1RoutineActor.gd`: fornece corpo físico, caminhada com `move_and_slide`, ciclo de carga/descarga, atividade ambiente da serra, apresentação original `WinterResidentModel.gd` e conversa. O ator não atravessa obstáculos deliberadamente nem usa teleporte para completar uma rota.
- `RoutineDirector.gd`: materializa somente o contexto atual, verifica o corpo no piso com `FullSession.position_clear`, mantém no máximo 12 rotinas externas mais próximas, remove atores distantes, respeita o turno 06h–18h e a equipe noturna do Porto Sul, evita IDs duplicados e expõe `nearest_action()`/`perform()`.

Personagens de interior só são admitidos na posição local autorada do V1 quando o corpo inteiro cabe segundo a física atual. Não existe fallback sobre móveis. Se a posição estiver bloqueada, o diretor não cria o NPC e deixa a falha observável para correção do layout/posição.

## Integração exata ainda necessária

### 1. Construção do diretor

Em `runtime/ProductionWorld.gd`, na função `build()`, imediatamente depois de criar/configurar `world.session` e atribuir `session = world.session`, adicionar:

```gdscript
var v1_routines = preload("res://gameplay/routines_v1/RoutineDirector.gd").new()
v1_routines.configure(world, session, self)
world.add_child(v1_routines)
```

Não é necessário alterar `Actor.gd`, `Gameplay.gd`, `Vehicle.gd` ou qualquer controlador de despacho.

### 2. Consulta e execução da interação

Em `runtime/FullSession.gd:nearest()`, consultar `world.get_node_or_null("V1RoutineDirector")`:

- dentro de um lugar, depois de `services.nearest_action()` e antes do fallback genérico de `interaction_points.service`;
- no exterior, depois de `activities.nearest_action()` e antes de `mission_world.nearest_action()`.

Se `nearest_action()` não estiver vazio, retornar essa ação. Em `FullSession.gd:interact()`, acrescentar ao `match`:

```gdscript
"v1_routine":
	var routines = world.get_node_or_null("V1RoutineDirector")
	return routines != null and routines.perform(str(action.target))
```

Essa ordem preserva a prioridade dos serviços, atividades e personagens de missão já conectados.

### 3. Atualização imediata de contexto

O diretor detecta mudanças em até 0,25 s, mas o integrador pode eliminar esse atraso chamando `refresh_context()`:

- em `FullSession.enter_place()`, depois de `state.set_location(state.region_id,id)` e depois que `room` existe;
- em `FullSession.leave_place()`, depois de `state.set_location(state.region_id)`;
- em `ProductionWorld._travel_checked()`, depois de `state.set_location(region_id)`.

## Validação pendente

Por determinação desta rodada, Godot, testes, benchmarks e commits **não foram executados**. Inspeção estática não valida comportamento, colisão, profundidade ou desempenho.

Antes de integrar como concluído, é obrigatório verificar:

1. carregamento/sintaxe dos quatro módulos e descoberta das ações reais;
2. colisão e circulação de cada rota ativa do cargueiro e de amostras representativas dos 32 postos do Porto Sul, sem atravessar carga, guindaste, água ou veículo;
3. spawn, conversa, saída, reentrada e descarregamento dos três NPCs do lodge, além de oclusão/profundidade, usando o contrato de `docs/interior-physics-and-depth.md`;
4. ausência de duplicação com população genérica, missões e `OriginalResidents`;
5. turno diurno/noturno e remoção por viagem/troca de interior;
6. invulnerabilidade de Maciota e mecânico, incluindo o teste obrigatório `tests/test_garage_weapon_restrictions.gd` se a integração tocar transições da garagem;
7. comparação renderizada antes/depois na cena real, com população/tráfego/clima equivalentes e métricas p50/p95/p99. A performance está **não medida**, não aprovada.

Esta entrega não afirma que a migração completa de NPCs do V1 terminou: cargueiros móveis, teleférico e personagens diretamente dependentes desses mecanismos continuam aguardando seus sistemas correspondentes no V2.
