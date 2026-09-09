# Polícia: pista, perseguição e sirene — 2026-09-08

## Correções

- O fallback de WantedManager sorteava um ângulo e colocava uma viatura a 520–720 px do jogador, sem verificar asfalto. Agora escolhe pontos livres de lanes reais, fora da câmera, respeita o sentido da via e recusa spawn quando não há pista válida ou a região está suspensa.
- A perseguição acompanha a troca entre pedestre e veículo. Dentro de casas, `police_exterior_position` conserva o ponto exterior em um alvo de busca; os agentes aguardam fora em vez de navegar para as coordenadas remotas do interior. A remoção da metadata ao sair reacquire o personagem.
- Viaturas sem estrelas encerram resposta e retornam. Sirene e giroflex respondem ao estado real; busca do lado exterior, retorno, pool e veículo quebrado silenciam a sirene. Sirene e motor usam o barramento SFX. Síntese/timbre permanece tarefa de áudio.
- Approaches de pistas canônicas terminam na pista quando o alvo está além do acostamento. Fallback não atravessa o vazio em linha reta, não usa redes distantes e não dá wrap em estradas abertas.
- Danos policiais deixaram de criar placas sobrepostas que ultrapassavam a silhueta. Pequenos arranhões são limitados ao corpo. Dano de abalroamento recebe intervalo de 0,85 s, evitando aplicação de dano em todos os quadros apenas por proximidade.
- Pool limpa atribuições e propriedade antigas. Diretor Harbor permite atendimento local por lanes para ocorrências muito distantes e rejeita região suspensa. Envelope do bombeiro recuou 10 px dentro da vaga pintada para não sobrepor ônibus largos na avenida.

## Verificação

- `test_police_pursuit_safety.gd`: PASS — ausência de pista, spawn na lane, sirene, busca exterior, retorno e fim de procurado.
- `test_police_mountain_lanes.gd`: PASS — MountainPassRoad/MountainTraffic reais com origem global `(4300,-4960)`. Viatura aproximou de 529,94 para 91,84 px do alvo; desvio máximo ao eixo da pista na última execução: 33,85 px em pista de 140 px. Região suspensa recusa spawn.
- `emergency_lane_router_contract_test.gd`: PASS — conexões dirigidas, cache e parada no acostamento sem avançar sobre borda da ponte.
- `test_harbor_police_multi_dispatch.gd`: PASS — quatro viaturas simultâneas, respeitando limite do pool.
- `test_harbor_emergency_dispatch.gd`: PASS — obstrução recusa saída, ambulância usa vaga oficial, bombeiro percorre 1086,5 px e apaga incêndio; teardown e reaproveitamento preservam unidades de outro atendimento. A ambulância ornamental que bloqueava a vaga foi removida pelo agente principal.

Execução Godot 4.7.2 headless. Alguns testes emitiram aviso de objetos vivos na saída; sem erros de script nos resultados aprovados. Não é medição visual de FPS. A travessia policial contínua foi validada também no mundo de produção, conforme abaixo.

## Travessia contínua da polícia

- `test_police_lane_handoff.gd`: PASS — passagem entre graph canônico e Path2D externo, volta ao graph, recusa de rota em sentido contrário ou região suspensa.
- `test_continuous_police_pursuit.gd`: PASS — HarborGame + ContinuousWorld + Mountain reais. Mesma viatura passou de Harbor para x=7560,44 e voltou para x=7067,42 no Harbor. Maior deslocamento por quadro: 4,60 px, sem teleporte ou substituição da instância.
- O handoff exige endpoints a no máximo 50 px e tangentes compatíveis (produto escalar >=0,8). A viatura percorre fisicamente o início da próxima lane antes de retomar o graph de cruzamentos.
- O teste de produção encontrou o gerador juntando indevidamente as duas pistas da fronteira, separadas por 62 px. O agente principal corrigiu `UnifiedRoadNetwork2D`/`HarborMountainConnector` para preservar esses endpoints; o retorno passou depois da correção. Não se ampliou a tolerância para esconder a falha geométrica.

Log de produção: `D:/geteco/continuous-police-pursuit.log`.
