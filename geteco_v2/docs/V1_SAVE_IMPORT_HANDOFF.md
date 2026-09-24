# Handoff — importação isolada de saves produtivos V1

Data: 2026-09-21

## Resultado e limite de responsabilidade

`res://migration/v1/V1SaveConverter.gd` implementa uma transformação determinística em memória. A API recebe um `Dictionary` já lido e analisado pelo futuro integrador e retorna uma proposta schema 3, avisos, campos não convertidos, incompatibilidades e decisões pendentes. Ela não usa `user://`, não enumera saves, não escolhe slot e não publica arquivos.

```gdscript
var result: Dictionary = V1SaveConverter.convert(v1_snapshot)
```

`ready_for_publication` só é verdadeiro quando o envelope V1 é válido, a proposta passa no `GameState.restore_snapshot` atual e não há incompatibilidades, campos não convertidos nem decisões. `ok` significa que existe uma proposta estruturalmente válida, mas ela ainda pode exigir confirmação explícita. O integrador nunca deve tratar apenas `ok` como autorização de escrita.

## Fonte rastreada

O contrato de entrada vem exclusivamente do fluxo produtivo V1:

| Papel | Fonte V1 produtiva | Dados usados |
|---|---|---|
| Envelope/escrita | `systems/SaveManager.gd` | `save_version=1`, `campaign`, `player`, `world`, `wanted` |
| Leitura/restauração | `systems/SaveManager.gd` | validação de versão, restauração e zeragem da perseguição |
| Jogador | `characters/Player.gd` | dinheiro, combate, armas, munição, roupas, carro pessoal, pickups, colecionáveis e estatísticas |
| Campanha | `systems/CampaignState.gd` | ledger canônico, Cobras, salvamento, residência e tempos |
| Mundo/veículo | `systems/RegionTravel.gd` | região, versão de coordenadas, interior, frio e veículo controlado |
| Missões/recompensas | `world/harbor/campaign/CobraCampaignState.gd` e `world/harbor/campaign/HarborArrivalMission.gd` | ordem, conclusão e pagamento único |

Formatos de demos e protótipos não participam do mapeamento.

O destino é formado por `runtime/GameState.gd` schema 3 e validadores subordinados de economia, campanha, campanha canônica, frota, atividades, frio e garagem. O conversor chama o próprio `GameState.restore_snapshot`; nenhum validador foi alterado ou relaxado.

## Tabela de mapeamento

| V1 produtivo | Proposta V2 | Estado | Regra |
|---|---|---|---|
| `player.money` | `economy.balance` | Convertido | Inteiro e mesma unidade; fora de `0..100000000` é incompatível, sem corte |
| `weapon_inventory` + `weapon_ammo.clip/reserve` | `economy.weapons.magazine/reserve` | Convertido quando catalogado | IDs, carregador e reserva preservados; limites V2 são verificados |
| `active_weapon_id` | `economy.equipped_weapon` | Convertido/fallback avisado | Só equipa uma arma possuída e válida; caso contrário `fists` |
| `owned_outfits` + `current_outfit_id` | `economy.outfits/outfit` | Convertido quando catalogado | IDs preservados; roupa ativa inválida cai para `dante_classic` com aviso |
| Inventário geral | `economy.inventory` | Sem fonte | O escritor produtivo V1 não grava um inventário geral; nada é criado |
| `personal_loadout*` | campos homônimos da economia | Convertido quando slot/arma são compatíveis | Não concede arma ausente |
| `collectibles_found` | `economy.collectibles` + recibos | Convertido quando catalogado | Recibo histórico usa recompensa exata; saldo salvo não é somado novamente |
| `unlocked_achievements` | `economy.achievements` + recibos | Convertido quando catalogado | Mesmo princípio de idempotência, sem recalcular saldo |
| `health`, `armor` | `combat.health`, `combat.armor` | Convertido | Escala `0..100`; perseguição fica zerada como no leitor V1 produtivo |
| ledger canônico antes do arco de contratos | `canonical_campaign` | Convertido | Beats preservados; flags/regiões derivados do catálogo, não por coincidência de nomes |
| arco de contratos e posterior | `canonical_campaign` | Decisão obrigatória | V1 não grava `completed_contracts`; a proposta deixa esse ledger no início |
| Primeiro Giro concluído | campanha + recibo `$150` | Convertido | O V1 paga sincronicamente antes de persistir a conclusão |
| missões Cobras concluídas/recebidas | `campaign.completed`, `pending_rewards`, `claimed_rewards` e recibos | Convertido | Ordem, valores `$120/$200/$250/$350/$600` e estado recebido preservados |
| missão Cobra ativa | `campaign.active_id`, `step=0` | Proposta com decisão | O estágio V1 não equivale aos eventos físicos V2; exige reinício explícito |
| `world_pickups_collected` | `world.rewards` + recibos | Convertido quando o contrato V2 existe | Saldo nunca é incrementado na conversão; arma/item exigido precisa já existir |
| RPG da cachoeira/caverna | aliases canônico e V2 | Convertido com alias documentado | `mountain_waterfall_secret_rpg_01` ↔ `mountain_cave_rpg`; normalização permanece a do `GameState` |
| `races_finished`, recordes e drift concluído | `world.activities` | Convertido | Contadores e tempos preservados quando o ID consta no catálogo correspondente |
| `best_drift_score` | — | Não suportado/decisão | V1 não grava o ID da zona exigido pelo V2 |
| `residence_state` | `world.activities.home` | Convertido parcialmente | Casa/contagem preservadas; veículo ativo é proposto como guardado, com decisão |
| posição exterior `[x,y]` | `world.pedestrian.position [x/16,0,y/16]` | Convertido | X/Y V1 viram X/Z V2 em metros |
| coordenada antiga da montanha | posição V2 | Convertido | Soma `[4300,-4960]` antes da divisão por 16 quando `coordinates_version < 2` |
| interior conhecido | `region_id/place_id/checkpoint_id` | Convertido | ID preservado se região e catálogo coincidirem |
| `exterior_return` | — | Não publicado/decisão | O V2 usa retorno autorado; a coordenada original é devolvida em `unconverted_fields` |
| veículo controlado | `world.vehicles[]` | Convertido quando seguro | Script deve estar na allowlist produtiva, arquétipo catalogado, `yaw=-rotation-PI/2`, posição `/16` |
| Monaliza / Ironback / carro do chefe do porto | `world.garage_rewards` | Convertido quando há registro | Saúde, pintura, posição e estado compatíveis são preservados |
| Monaliza/Ironback desbloqueado sem registro | — | Decisão obrigatória | Impede que a integração dependa da recriação automática V2 e invente reparo/estado |
| cupê secreto de Ashbend | — | Não suportado/decisão | Não há identidade equivalente no catálogo V2 |
| `temperature`, `weather_clock` | `world.cold` | Convertido | Temperatura preservada; relógio normalizado ao ciclo 240; exposição ausente inicia em zero |
| `weapon_customization`, banco, atendimento médico, necrotério e desmanche | — | Não suportado/decisão quando significativos | Valores são retornados integralmente em `unconverted_fields` |
| campos desconhecidos | — | Não suportado/decisão | Caminho, motivo e valor são retornados; nunca são descartados silenciosamente |

## Contrato do resultado

- `proposal`: snapshot V2 em memória; vazio quando o envelope básico é inválido.
- `warnings`: adaptações reversíveis ou comportamento produtivo relevante.
- `unconverted_fields`: caminho, razão e valor original não convertido.
- `incompatibilities`: violações que impedem considerar a conversão bem-sucedida.
- `decisions_required`: propostas que precisam de aceite ou resolução humana.
- `transformations` e `aliases_applied`: trilha explícita das regras usadas.
- `validator.checked/accepted`: evidência da execução do validador V2.
- `ok`: fonte aceita, proposta validada e nenhuma incompatibilidade.
- `ready_for_publication`: `ok` e nenhuma decisão/campo pendente.

O dicionário de origem é duplicado profundamente antes da leitura. Nenhuma etapa o modifica e não há relógio, aleatoriedade ou I/O; chamadas repetidas produzem o mesmo resultado.

## Ponto exato de integração e publicação em slot vazio

A futura interface de importação deve ficar fora do conversor e seguir esta ordem:

1. O usuário escolhe explicitamente um arquivo V1; o integrador o lê somente para memória. O conversor não participa dessa leitura.
2. Chamar `V1SaveConverter.convert(snapshot)` e apresentar avisos, incompatibilidades, campos não convertidos e decisões.
3. Publicação automática só é permitida com `ready_for_publication == true`. Uma decisão aceita deve produzir uma nova proposta explícita e novamente validada; não basta ocultar o aviso.
4. Reservar somente um slot V2 comum vazio com `SessionLaunch.prepare_import_destination(slot_id)`. `progress` não é destino de importação.
5. Criar `SaveStore`, atribuir `store.path = SessionLaunch.selected_path` e chamar `store.publish_import_snapshot(result.proposal)`.
6. Tratar `ERR_ALREADY_EXISTS` sem sobrescrever primário, `.bak` ou `.tmp`; tratar `ERR_INVALID_DATA` como falha de contrato. O arquivo V1 nunca é movido, renomeado ou apagado.

```gdscript
var conversion := V1SaveConverter.convert(snapshot)
if not conversion.ready_for_publication:
	return ERR_INVALID_DATA
var error := SessionLaunch.prepare_import_destination(slot_id)
if error != OK:
	return error
var store := preload("res://runtime/SaveStore.gd").new()
store.path = SessionLaunch.selected_path
return store.publish_import_snapshot(conversion.proposal)
```

Esse é o único ponto de conexão necessário. Nenhuma alteração em `GameState`, `SaveStore`, `SessionLaunch`, menu ou campanha foi feita nesta rodada.

## Testes e evidência

Fixtures sintéticas estão em `res://tests/migration_v1/V1Fixtures.gd`; elas não leem nem copiam saves pessoais. A suíte cobre início de jogo, progresso intermediário, interior, veículo, recompensa já recebida, formato inválido e campos desconhecidos, além de imutabilidade e determinismo.

Comando executado com Godot 4.7.2 headless e log em diretório temporário do sistema:

```text
Godot_v4.7.2-stable_win64_console.exe --headless --path D:/geteco/game/geteco_v2 --script res://tests/migration_v1/test_v1_save_converter.gd
MIGRATION_V1 PASS (42 checks, 7 synthetic scenarios)
```

Todos os cenários que produzem proposta chamam novamente o `GameState.restore_snapshot` atual. O aviso do ambiente Windows sobre leitura do armazenamento de certificados não pertence ao jogo nem afetou o exit code 0.

## Limitações declaradas

Esta entrega não é uma promessa de importação completa. Saves no arco canônico de contratos, com missão Cobra ativa, retorno de interior, estado de carro sem equivalente, score de drift sem zona, campos desconhecidos ou subsistemas V1 ausentes no V2 exigem decisão e não estão prontos para publicação automática. A validação estrutural também não substitui a admissão física da posição pela cena renderizada; a integração deve manter os fallbacks físicos já existentes no V2.
