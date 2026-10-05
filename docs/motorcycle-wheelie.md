# Empinar moto

Nas motos urbanas, esportivas, cruiser e de motocross, acelere e segure **Shift** (teclado), **L3** (controle) ou **Empinar** (toque). A ação pode ser remapeada em Configurações → Controles → Veículo / Esportes. Soltar o comando ou o acelerador baixa a frente; o freio a baixa mais rapidamente.

A manobra começa acima de 2 m/s e alcança a inclinação máxima de 0,62 rad (~35,5°) a partir de 7 m/s com aceleração completa. A direção chega a 45% da resposta normal com a frente totalmente levantada. Não funciona parado, em ré, com motor desligado, em carros ou para motoristas automáticos.

O visual gira em torno do contato do pneu traseiro. Banco, guidão e piloto acompanham essa transformação; as mãos continuam presas às manoplas. O corpo físico conserva o apoio no solo e o casco de colisão com obstáculos. A manobra não produz salto nem altera os critérios dos checkpoints. No motocross, sair do chão devolve o controle à atitude de salto e conserva a empinada temporária da largada por excesso de giro.

Queda, bloqueio dos comandos, reposicionamento e saída limpam a inclinação. A empinada não fica no save. O estado compartilhado está em `gameplay/MotorcycleWheelie.gd`; as motos de rua instanciam esse estado uma vez, e motos sem jogador não fazem consultas adicionais nem atualizam o transform parado. Não há malhas, partículas, luzes, timers ou loops de busca novos por frame.

Validação funcional: `tests/test_motorcycle_wheelie.gd`. Integração em `Main.tscn`, com embarque/desembarque e toque: `tests/test_motorcycle_wheelie_flow.gd -- --no-save --skip-arrival --touch-controls`. Capturas e sequência temporal opcionais com `--capture-dir=<diretório>`.

Medição renderizada: `tests/measure/measure_motorcycle_wheelie.gd -- --no-save --skip-arrival --scenario=street --variant=after --output-dir=<diretório>`; também aceita `--scenario=motocross`. Cada cenário tem 8 s de aquecimento e 30 s de amostras reais. A comparação exige mesma configuração e ausência de benchmarks concorrentes.
