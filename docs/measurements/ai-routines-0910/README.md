# Rotinas de emergência e pedestres — 10/09/2026

## Alterações

- Navegação local a pé com caminho persistente, consultas de colisão, busca limitada e nova tentativa espaçada. Substitui desvios aleatórios de policiais, socorristas e civis. Orçamento menor para multidões; não é um navegador global para toda a cidade.
- O roteador encerra o deslocamento na rua quando a ocorrência fica além da faixa. A viatura freia antes de orientar para outro waypoint; um congestionamento a até 360 px permite concluir o acesso a pé.
- A polícia só desembarca para um carro parado por 0,6 s, usando o mesmo limite de 12 px/s da abordagem. Carros que retomam movimento provocam o retorno da dupla. A porta deixa de bloquear o próprio desembarque, fecha na abordagem pacífica e volta a servir de proteção em confronto com linha de visão.
- Atendimento não termina arbitrariamente após sete segundos. Ambulâncias/caminhões aguardam embarque; depois de 30 s sem concluir, solicitam retorno da equipe. Se toda a equipe desaparecer/morrer, aguardam dois segundos antes de liberar o veículo.
- Saída ajustada à largura física de cada veículo; exceção de colisão com o próprio veículo somente nas transições de embarque/desembarque. Socorristas escolhem um ponto com acesso ao paciente/incêndio e não trabalham através de paredes. Animação considera o movimento efetivo.
- Pausas de pedestres interrompem caminhada, tentativas de visitar portas inacessíveis expiram e interrupções cancelam o fade anterior. Tiros terminam na primeira barreira; civis distantes atrás de paredes não recebem o mesmo alerta de uma testemunha próxima.
- Limpeza de exceções físicas das portas e da dupla; rotação interpolada limitada para evitar extrapolação em frames longos.

## Evidências

Godot 4.7.2. Os arquivos `.txt` desta pasta contêm as saídas completas.

| Verificação | Resultado |
|---|---|
| `test_responder_routines.gd` | 22 verificações aprovadas: desvio de parede, fim de rota, carro andando devagar/parado, espera da equipe, atendimento e retorno das duas equipes, fogo atrás de parede e acesso pelo lado correto, pausas/visitas e percepção de tiros |
| `test_ambulance_hospital_routine.gd` | 6 verificações aprovadas no HarborGame: vítima incapacitada, despacho, deslocamento físico, atendimento, alta hospitalar e retorno dos dois paramédicos |
| `test_police_vehicle_stop_live.gd` | 10 verificações aprovadas com Vulkan/Forward+ e GPU real: extração/prisão, saída voluntária, fuga cancela abordagem, parede bloqueia interação e contato não empurra a viatura |
| `test_police_fair_arrest.gd` | Aprovado |
| `test_police_pursuit_safety.gd` | Aprovado |
| `test_police_lane_handoff.gd` | Aprovado |
| `test_police_mountain_lanes.gd` | Aprovado; desvio máximo do pavimento registrado: 33,85 px |
| `test_continuous_police_pursuit.gd` | Aprovado; perseguição atravessa a emenda entre regiões e retorna |
| `test_pedestrian_life_routines.gd` | Aprovado |
| `test_emergency_3d_cover.gd` | Aprovado; porta continua bloqueando raios de tiros |
| `tools/check_references.py` | Nenhuma referência quebrada nova |

Demais testes foram executados com `--headless --fixed-fps 60` para verificar lógica/física. Isso não mede desempenho gráfico. Há avisos de interpolação de câmera e de objetos remanescentes ao encerrar algumas cenas; não foram classificados como validação de ausência de vazamentos.

## Limites e pendências encontradas

- `test_rescue_and_burial_flow.gd`: o ciclo médico passou, mas o teste atingiu seu limite de tempo no trecho do IML/cemitério. Não considerar o sepultamento completo validado. O teste simula manualmente o retorno dos agentes do IML; ele não demonstra o ciclo inteiro desses agentes em partida.
- `test_region_emergency_teardown.gd`: três expectativas antigas de troca integral de cena falharam. `RegionTravel.request()` recusa essa troca quando existe `continuous_world` (linha 37); o teste ainda espera a arquitetura anterior. A passagem contínua efetivamente usada pelo jogo foi verificada pelo teste de perseguição entre regiões acima.
- Não foi feita partida longa com várias ocorrências concorrentes nem comparação de tempo de frame antes/depois. A busca de pedestres é local e limitada; geometrias sem acesso podem continuar impedindo atendimento, sem autorizar trabalho através de paredes.

As alterações pré-existentes de perfis/variação de passeios em `AuthoredSidewalkPedestrian.gd` foram preservadas e excluídas do commit desta correção, assim como as outras mudanças já presentes no workspace.
