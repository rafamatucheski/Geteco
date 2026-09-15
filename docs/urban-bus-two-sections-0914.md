# Ônibus urbano com duas seções — 14/09/2026

A linha 510 passou de uma cabeça com dois reboques para uma cabeça com um reboque. A sanfona acompanha as seções existentes, e a reserva longitudinal do trânsito passou de 386 para 266 px. Os corpos, suas colisões e a varredura conjunta foram preservados. O nome apresentado agora é Expresso Articulado.

No Godot 4.7.2, o teste `test_urban_bus_route_turns.gd` antes da mudança falhou em Westgate → Foundry (último reboque contra StationSolids) e Quay → Dock (último reboque contra RoadPost078). Depois da redução, as quatro curvas passaram. Logs: `D:/geteco/artifacts/bus-two-baseline.log` e `bus-two-turns.log`.

`test_articulated_driving.gd` passou aceleração, curva, ré e separação física das seções. `test_urban_bus_section_lifetime.gd` passou remoção do reboque, parada do ônibus incompleto, faróis e transferência entre pistas. Os testes que acessavam o antigo terceiro corpo foram adaptados ao último reboque real; o obstáculo de regressão continua imediatamente à frente dele.

A validação integrada `test_urban_transit.gd` registrou 12 embarques e 7 desembarques, mas falhou em alcançar as seis paradas e completar uma volta: ônibus aguardaram reserva nos cruzamentos de Westgate, embora a varredura física estivesse livre. Portanto, esta alteração resolve os dois bloqueios físicos reproduzidos nas curvas; não certifica a operação completa da linha. O teste encerrou pelo timeout de 160 s durante o fechamento noturno. Log: `D:/geteco/artifacts/bus-two-service.log`.

Performance e revisão visual renderizada não foram medidas nesta tarefa. Havia outra medição gráfica e mudanças concorrentes no workspace. A remoção de um corpo/viewport por ônibus reduz a quantidade de objetos, mas não constitui comprovação de ganho de FPS. Nenhuma certificação nova de interiores ou oclusão foi realizada.
`test_long_traffic.gd` também passou: cinco combinações de carros/caminhões/ônibus atravessaram a curva, sem sobreposição de corpos e mantendo bloqueio por obstáculo diante do último reboque. Log: `D:/geteco/artifacts/bus-two-mixed.log`.
