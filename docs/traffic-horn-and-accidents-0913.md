# Buzina, pedestres e acidentes no trânsito ambiente

Implementado em 13/09/2026 no tráfego criado por `ModernTrafficFactory`.

- Um pedestre bloqueando o carro parado recebe buzina após 1,2 s. O aviso dá mais 3 s para sair; a espera pertence àquela pessoa e reinicia quando ela sai ou o bloqueador muda.
- A buzina consulta corpos próximos uma vez por evento, com alcance de 240 px e limite de 64 resultados. NPCs na trajetória procuram um dos lados livres usando o próprio corpo físico e continuam pela navegação existente. Paredes separam a percepção. Combate e atendimento médico conservam prioridade.
- Depois do aviso, o motorista retoma o avanço. Contato durante frenagem pode atropelar quem entra repentinamente na trajetória. O movimento proposto é varrido antes de consumir a velocidade, incluindo passos de tráfego fora da tela. Só pessoas efetivamente atingidas recebem exceção de colisão temporária.
- Sem espaço para acelerar, 0,6 s de pressão do para-choque após o prazo provoca uma queda de baixa intensidade, equivalente ao limiar mínimo de impacto, sem aplicar dano de velocidade de cruzeiro. Também funciona com a margem de colisão dos veículos longos.
- Uma intrusão de outro carro dentro do movimento de frenagem pode produzir deformação e som de colisão nos veículos. A separação física permanece; o carro não atravessa a carroceria ou paredes. Sinais, reservas de cruzamentos e áreas de resgate continuam limitando o trânsito.
- Maciota, o mecânico e pessoas com proteção de atendimento mantêm suas proteções. A população e a seleção de veículos já existentes continuam sendo usadas.

## Validação

Evidências em `D:/geteco/artifacts/traffic-horn-0913/`.

- `tests/test_traffic_horn_and_accidents.gd`: passou, incluindo espera, percepção, fuga, continuidade, prazo de aviso, atropelamento, feedback, travessia repentina, proteção médica, saída com parede, colisão entre carros e contato persistente de carro/ônibus. Resultado final: `behavior-delivery.log`.
- Execução renderizada do mesmo teste com Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1280×720: passou antes da extensão do último caso ao ônibus. As imagens `01-horn.png` e `02-cleared-lane.png` foram inspecionadas; mostram o pedestre na trajetória e depois ao lado. É uma cena de teste, não uma certificação visual de todos os bairros.
- `test_vehicle_person_impact_0911.gd`: passou após corrigir a preparação do teste para iniciar as duas medições em um frame físico. Antes, o primeiro movimento de alguns veículos acontecia em idle, variando com o tempo do frame visual; a medição com pessoa já começava em física. Nenhuma tolerância foi alterada. `person-impact-fixed.log` conserva avisos de recursos/objetos ainda em uso ao encerrar; essa limpeza não foi certificada.
- `test_city_traffic_rules.gd`, `test_garage_weapon_restrictions.gd` e `test_vehicle_crash_and_explosion.gd`: passaram.
- Durante a execução, alterações concorrentes em `CoronerCare.gd` e `NPCMedicalCare.gd` causaram erros transitórios de parse. A execução renderizada posterior passou com os arquivos corrigidos pela outra tarefa. Os logs das tentativas anteriores foram preservados.

## Performance pendente

Não há baseline/comparativo isolado de frame time. Havia múltiplas instâncias do Godot, incluindo outras execuções renderizadas, e elas não foram encerradas. Não se declara aprovação de FPS nem ausência de regressão. Meta provisória: 60 FPS / 16,67 ms; confirmar com a cena real, mesma rota e população, pelo menos 30 s após aquecimento, comparando p95/p99 com tolerância de 5% para investigação.

O custo novo recorrente está na varredura de pessoas antes do movimento e no estado de espera por carro; a busca de ouvintes acontece apenas ao buzinar, e a escolha dos lados acontece apenas ao receber o aviso. Não há varredura global de NPCs por frame. A medição renderizada em HarborGame permanece necessária para quantificar esse custo.
