# Áudio de motores de serviço — Geteco V2

Componente independente: `ServiceVehicleAudio.gd`. Nenhuma integração é instalada automaticamente e nenhum sistema existente foi alterado. Os caminhos `res://` pressupõem abrir **geteco_v2/project.godot**.

## API

Criar um único nó por SceneTree, como filho do mundo, e chamar `configure` depois de `add_child`.

| Método | Contrato |
| --- | --- |
| `configure(world, listener) -> bool` | Mundo com propriedade `driving` (pode ser null) e Node3D que acompanha o ouvinte real/câmera. Não cria nem troca AudioListener3D. |
| `register_vehicle(vehicle, service) -> bool` | Recebe Vehicle/DispatchVehicle já na árvore e serviço `police`, `medic`, `fire` ou `mortician`. Duplicata do mesmo veículo/serviço é idempotente. Retorna false para entradas inválidas, catálogo ausente, assets indisponíveis ou limite excedido. |
| `set_vehicle_active(vehicle, active)` | Suspende imediatamente as vozes e permite retomada; redefine a amostra de aceleração. |
| `set_enabled(enabled)` | Suspende/retoma todo o mixer; desativado não recebe processamento. |
| `unregister_vehicle(vehicle)` | Para o motor, desconecta sinais e libera a referência ao banco quando seu último usuário sai. |
| `shutdown()` | Limpeza idempotente de registros, emissores, streams e referências. Também executada ao sair da árvore. |

`unregister_id(id)` é a variante usada pelo sinal `tree_exiting`. O veículo não é mantido vivo pelo mixer (WeakRef). Remover o veículo da árvore encerra o registro; para recolocá-lo, registrar novamente. Alteração de archetype em runtime exige remover e registrar novamente. Se world/listener desaparecer, o mixer se desativa: configurar os novos objetos e chamar `set_enabled(true)`.

## Integração externa proposta

Exemplo para o integrador do mundo, **não aplicado** ao projeto:

```gdscript
const SERVICE_AUDIO = preload("res://audio/service_vehicles/ServiceVehicleAudio.gd")
var service_audio: Node3D

func setup_service_audio(world: Node, listener: Node3D, dispatch: Node) -> void:
    service_audio = SERVICE_AUDIO.new()
    world.add_child(service_audio)
    if not service_audio.configure(world, listener):
        service_audio.queue_free()
        return
    dispatch.dispatch_event.connect(_on_service_dispatch_event)
    # Inclui unidades criadas antes da conexão.
    for unit in dispatch.units:
        _register_service_unit(unit)

func _register_service_unit(unit: RefCounted) -> void:
    if not is_instance_valid(unit.vehicle):
        return
    if not service_audio.register_vehicle(unit.vehicle, unit.service):
        push_warning("Motor de serviço não registrado")
        return
    service_audio.set_vehicle_active(unit.vehicle, not unit.suspended)

func _on_service_dispatch_event(event_name: String, data: Dictionary) -> void:
    if not is_instance_valid(service_audio):
        return
    var unit: RefCounted = data.get("unit")
    if unit == null:
        return
    match event_name:
        "dispatched":
            _register_service_unit(unit)
        "unit_suspended":
            service_audio.set_vehicle_active(unit.vehicle, false)
        "unit_resumed":
            service_audio.set_vehicle_active(unit.vehicle, true)
        "unit_finished", "unit_wrecked":
            service_audio.unregister_vehicle(unit.vehicle)
```

Na troca de mundo ou ao desmontar essa integração, desconectar `_on_service_dispatch_event` de `dispatch.dispatch_event`, chamar `shutdown()` e `queue_free()` no mixer. Ao desativar o dispatch ou entrar em um interior sem áudio exterior, o integrador deve chamar `set_enabled(false)` e restaurar ao retornar. Não deduzir essa política a partir da posição exterior alternativa do dispatch.

Também é possível registrar veículos fora do dispatch diretamente. O serviço é explícito: `station_wagon` não identifica sozinho um carro de legista. Não há busca global por veículos nem polling do array `dispatch.units`.

## Contratos preservados

- Lê `FleetCatalog.spec(vehicle.archetype).engine_family`, com default `sport`, igual a WorldAudio. Se qualquer um dos sete WAVs faltar, tenta `street`; falha sem tocar se esse banco também estiver incompleto. Usa os assets originais `res://audio/acoustic/engine_<família>_0..6.wav`; duplica os recursos para configurar loop sem modificar os imports compartilhados.
- No catálogo inspecionado, police_cruiser, police_suv, medic_box, rescue_pumper e station_wagon não declaram engine_family: todos seguem o default sport. Não atribuí famílias diferentes apenas pelo nome do serviço.
- A posição global segue Vehicle; velocidade usa `abs(speed)`, inclusive em ré; aceleração é a variação dessa velocidade ao longo do tempo, limitada e suavizada. Velocidade relativa a max_forward_speed e aceleração modulam a mistura de dois samples adjacentes dos sete originais e o pitch. É um mixer ambiente simplificado, sem simular marchas de WorldAudio.
- `controlled` não significa necessariamente jogador: DispatchDriver usa `controlled=true` e `external_input=true`. O mixer exclui `controlled && !external_input` e também `world.driving.occupied && world.driving.car == vehicle`. WorldAudio continua sendo o único dono do motor conduzido pelo jogador. Para transferência de posse, atualizar esses estados antes da etapa de áudio do frame.
- Motor desligado/bloqueado, saúde zero, veículo oculto, física desativada, processamento desativado, fora do alcance ou registro inativo não consomem vozes em reprodução. Parado em semáforo com motorista continua em marcha lenta. Veículo sem motorista nem trânsito ativo fica silencioso.
- Usa processo pausável. Não escreve estado de Vehicle, driving, equipamento ou dispatch. Não instancia VehicleEquipment, buzina ou sirene. O legista permanece sem sirene.

## Limites explícitos

| Recurso | Teto |
| --- | --- |
| Mixers aceitos | 1 por SceneTree; duplicata é recusada e removida |
| Veículos registrados | 32; registro adicional retorna false |
| Motores audíveis | 6 mais próximos dentro de 45 m |
| Vozes por motor | 2 AudioStreamPlayer3D, max_polyphony=1 |
| Vozes deste componente | **12 simultâneas**, sem contar WorldAudio, sirenes ou outros sistemas |
| Seleção por distância | No máximo uma vez por frame, cadência de 0,1 s, sem catch-up |
| Bancos | 7 streams por família registrada, compartilhados entre veículos |

Acompanha estado/movimento dos até 32 registros por frame e atualiza até 12 emissores. Em suspensão individual permanece apenas a leitura limitada para detectar retomada automática; não há reprodução silenciosa em background. O pool mantém até 12 nós parados enquanto houver registros, reutilizados sem criar novas vozes; ao remover o último registro ou encerrar, os nós são liberados. Bancos carregam sincronamente no registro: registrar em fase coordenada de criação/carregamento para avaliar possíveis picos. Os tetos são decisões de orçamento, **não evidência de performance**.

## Validação e pendências

Revisão estática dos contratos e conferência dos WAVs/referências locais. Godot, testes comportamentais, escuta e benchmarks **não executados**, conforme pedido. Parser/type checker Godot não executado; gdtoolkit não está instalado. `test_service_vehicle_audio.gd` é um teste de contrato preparado para execução futura, sem física/visuais reais; não substitui integração.

Após coordenação, executar pelo projeto V2 esse teste e validar em cena real: quatro serviços; marcha lenta/aceleração/frenagem/ré; passagem pelo ouvinte; entrada/saída dos 45 m; 8 unidades com teto de 12 vozes; transferência ao jogador; suspensão/retomada; motor bloqueado; destruição; remoção e troca de mundo; pausa; sirene existente tocando uma única vez e legista sem sirene. Conferir níveis, transições de samples e possíveis cortes na troca dos seis mais próximos.

Performance **não medida e não aprovada**. Comparar baseline sem integração versus integração na mesma cena renderizada, hardware e configuração, incluindo primeira carga e regime estável; coletar frame time p50/p95/p99, máximo e frames acima de 33,3/66,7 ms, além de contagem de vozes. Referência provisória do projeto: 60 FPS/16,67 ms; hardware e orçamento final devem ser acordados antes da medição.
