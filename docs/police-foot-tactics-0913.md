# Polícia a pé — 13/09/2026

Policiais usam as entradas e curvas dos becos publicados por `HarborAlleys`, com coordenadas transformadas por distrito. `PoliceFootNavigation` conserva os pontos do corredor e usa `ResponderNavigation` para desviar de obstáculos físicos. O planejamento local mantém as fatias e o orçamento global existentes; as definições dos becos são consultadas ao mudar o destino ou, sem rota, no máximo uma vez por segundo. A colisão continua com raio 5 e altura 16.

A busca pelo último ponto visto agora chega a 12 pixels, em vez de parar a 110. Em combate, a cobertura da porta da viatura dura 2,8 ou 4,4 segundos conforme o assento; perder visão, afastar-se da viatura ou receber uma ameaça muito próxima libera a cobertura. O policial fecha sua porta ao avançar. O bloqueio específico do banco conserva sua função.

Velocidades de patrulha/investigador/SWAT/FBI/exército: 112/118/124/128/132 pixels por segundo; antes, 175/190/210/220/235. Desembarque e deslocamento para cobertura usam 72% dessas velocidades, e busca usa 85%.

`PoliceAppearance` fornece dez combinações persistentes de altura, largura, profundidade, espessura dos membros, rosto, pele e cabelo/barba. A distribuição percorre os dez modelos; `appearance_model` permite selecionar um deles. Reentrada de uma reserva preparada preserva sua identidade. Porte não altera velocidade, colisão ou equipamentos. O uniforme usa a construção por anéis da referência do Dante; ombros, calçados e passada foram ajustados. As mãos usam o solver de armas compartilhado.

Quatro dos dez perfis (índices 1, 4, 7 e 8) são policiais mulheres, com diferentes portes e tons de pele, rosto e uniforme ajustados e cabelo curto, coque ou rabo de cavalo. Participam da mesma distribuição automática e de todos os escalões. O cabelo acompanha a cabeça em um único mesh/material, sem novo processo ou viewport. Prévia atualizada em `D:/geteco/artifacts/police-women-0913/variants.png`, renderizada de frente, perfil e costas. O teste de tática foi executado novamente: aprovados contato com o chão, empunhadura das três armas e comportamento existente nos dez perfis. Log em `police-women-0913/test.log`, com aviso de objetos no encerramento. A medição de FPS continua pendente: havia outra medição renderizada de ponte/iluminação ativa na mesma GPU durante esta revisão; não se iniciou benchmark concorrente.

## Validação

Correção posterior de ocupação: `EmergencyVehicle` mantém um bloqueio de direção desde o início do desembarque até a confirmação real de embarque da equipe completa. Ordens de retorno, ré e recuperação de travamento não vencem esse bloqueio. Foram removidas as liberações por 12 segundos de espera ou morte da equipe. Sem reembarque, a viatura permanece estacionada. Callbacks de atores fora da equipe, visíveis, mortos ou duplicados não contam como ocupantes.

`test_police_parked_without_crew.gd` aprovado: 100 segundos simulados de ordens repetidas de retorno/ré sem deslocamento ou rotação, embarque real liberando o bloqueio e mais 30 segundos com equipe morta sem retorno autônomo. `test_police_fair_arrest.gd` aprovado novamente para retomada normal após embarque. O novo teste emite avisos de recursos/objetos no encerramento. Não houve nova medição renderizada de FPS nesta correção; a pendência de desempenho abaixo permanece.

Godot 4.7.2, scripts em `game/tests/`:

- `test_police_foot_tactics.gd`: aprovado; dez modelos, pele consistente, colisão, limites de velocidade por escalão, saída física de viatura, uso e abandono da porta, perda de visão e busca até o último ponto visto. Nos dez portes, valida apoio no piso e sapatos nivelados ao andar/parar, além da empunhadura de pistola, SMG e M4.
- `test_police_alley_navigation.gd`: aprovado; policial de produção percorre os dois becos reais nos dois sentidos. O teste entrega apenas o destino final, verifica chegada e deslocamento sem teleporte. Usa HarborPreview, obstáculos estáticos reais e desativa colisões da população para isolar a rota.
- `test_responder_routines.gd`: aprovado; contorno físico de parede e regressões dos serviços existentes.
- `test_police_fair_arrest.gd`: aprovado; advertência, prisão, retorno da dupla à viatura e retomada da perseguição. O encerramento deste teste emite avisos de objetos/recursos ainda em uso; o teste de tática também emite aviso de objetos no encerramento.
- `capture_police_variants.gd`: renderização Vulkan dos modelos de produção, frente/perfil/costas, na mesma escala e câmera do Dante. Prévia isolada em `D:/geteco/artifacts/police-alley-0913/variants.png`; não é captura de uma perseguição no mapa.

Os testes novos e o de prisão foram executados com `--headless --fixed-fps 60 --path D:/geteco/game --script res://tests/<arquivo>.gd`. O teste de rotinas usou tempo normal. Logs e cópias anteriores dos arquivos principais estão em `D:/geteco/artifacts/police-alley-0913/`.

## Desempenho: pendente

Alvo provisório de 60 FPS / 16,67 ms; aumento superior a 5% em p95/p99 exige confirmação. Risco desta mudança: geometria por personagem, animação por entidade e planejamento de rotas. Não aumenta população nem cria viewports adicionais; o planejamento conserva o orçamento compartilhado de 1 ms por frame.

Baseline renderizado de `measure_game_frame_stability.gd -- --police --normal-cap --capture`, HarborGame, 1280×720, Mobile/Vulkan, RTX 4060 Laptop, limite 60 e VSync desligado: 1.269 frames em 30,039 s, média 42,25 FPS, p50 18,93 ms, p95 40,29 ms, p99 73,08 ms, máximo 439,39 ms, 143 frames acima de 33,3 ms e 17 acima de 66,7 ms. Pico de cinco viaturas. O aquecimento foi separado em outro arquivo. A base já não cumpre o alvo.

A tentativa posterior foi interrompida por esta tarefa ao detectar benchmarks de montanha e Dante iniciados por outras tarefas na mesma GPU. Apenas os processos da medição desta tarefa foram encerrados. Não há resultado posterior comparável nem aprovação de desempenho. O cenário de baseline é perseguição de carro; a carga específica de dez policiais a pé ainda precisa de medição renderizada isolada. Alterações simultâneas no projeto e o jogo/editor abertos também limitam a atribuição de diferenças.
