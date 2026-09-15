# Roubo de viaturas e alarmes — 10/09/2026

- Viaturas estacionadas exigem lockpick antes do embarque: três acertos na faixa verde, usando Espaço ou clique. Um erro ou Escape encerra a tentativa e dispara somente o alarme.
- Sucesso inicia o embarque normal e acrescenta uma estrela de procurado. Entrar novamente na mesma viatura não repete o crime nem o lockpick.
- Cerca de 35% dos veículos civis estacionados recebem alarme, incluindo motos. A seleção é estável pelo nome, posição e modelo; o alarme dispara no primeiro roubo, sem criar estrelas por conta própria.
- Alarmes duram entre 10 e 15 segundos. O temporizador continua durante embarque, avaria e suspensão da física de tráfego; tentativas repetidas não prolongam um alarme ativo.
- A reposição de uma viatura de prontidão preserva a que já foi roubada.
- O minigame libera os controles ao encerrar ou ao remover o veículo. O clique de uma tentativa falha não dispara a arma do jogador.

Validação em Godot 4.7.2:

- `tests/test_police_car_alarm_theft.gd`: lockpick, teclado/mouse, falha, cancelamento, prisão, remoção, reposição, estrelas, carros/motos com e sem alarme, expiração real e reentrada.
- `tests/test_motorcycles.gd`: montagem, condução e apresentação de motos.
- `tests/test_police_sensitivity.gd`: regressão do balanceamento policial.
- `tests/test_bank_heist_flow.gd`: regressão do lockpick compartilhado e do fluxo de assalto ao banco.
