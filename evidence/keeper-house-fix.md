# Casa do coveiro — correção de posicionamento

- A bancada ocupa z=-3,30 até -2,28. O ponto anterior do coveiro, z=-2,15, sobrepunha a cápsula de raio 0,30 m ao móvel em 0,17 m.
- O ponto passa a z=-1,85, com 0,13 m de folga para a cápsula. A admissão na sala zera a velocidade e a rota externa e reinicia a interpolação.
- O ponto passa a ser aplicado uma vez por instância da sala, evitando que a varredura de contexto a cada 0,25 s desfaça o deslocamento físico.
- Teste de regressão: `tests/test_keeper_house.gd`, com sala integrada, colisão, estabilidade entre varreduras, conversa e reentrada.
- Validação integrada pendente: primeira execução bloqueada por erro de inferência de `extent` em `runtime/GarageRewards.gd:90`; tentativa posterior encontrou erro de inferência de `impact` em `gameplay/urban_v1/UrbanRoutineActor.gd:151`, arquivo alterado simultaneamente por outra sessão. Nenhum desses arquivos foi modificado nesta tarefa.
- Fotos, oclusão e performance renderizada antes/depois: pendentes. Havia quatro processos Godot existentes; nenhum foi encerrado. Não há aprovação visual, física integrada ou de performance, nem alteração na contagem de interiores migrados.
