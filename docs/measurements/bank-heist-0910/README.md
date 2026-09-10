# Assalto ao banco — 10/09/2026

## Fluxo implementado

1. Entrada no salão, com câmera fixa que mostra o ambiente e guardas nos postos. A tecla usada na porta não aciona o cofre.
2. Arma na mão provoca advertência. Guardar a arma encerra a tensão; os guardas não iniciam prisão nem tiros nesse estado.
3. Primeiro tiro ou ataque inicia reação armada, pânico dos funcionários e contagem de 30 segundos.
4. Após neutralizar os guardas, segurar E junto ao guarda de escopeta recolhe o cartão. O cartão continua disponível depois da remoção do corpo.
5. Cartão e interação deliberada no cofre iniciam a fechadura. Cancelar devolve o controle; o relógio não para. Após destravar, a porta leva três segundos para abrir.
6. Três pilhas de $400 exigem coleta individual. As divisórias ficam transparentes para revelar o dinheiro; continuam sólidas. O jogador pode abandonar a coleta e sair com o que já pegou. Pilhas recolhidas não pagam novamente.
7. Ao terminar a contagem, três patrulhas entram pela avenida fora da câmera, dirigem até posições distintas e desembarcam suas duplas. Viaturas, portas e barreiras são obstáculos físicos. A polícia enfrenta o assaltante na saída. Ao sair do quarteirão, o cerco libera a perseguição normal.

O minimapa conserva a localização da entrada exterior. O enquadramento interno usa projeção paralela e limita a escala dos NPCs. Portas do banco e posto recebem a cortina de transição; objetivos de outra missão não sobrepõem o assalto. Os interiores continuam isolados internamente, mas suas coordenadas técnicas não são usadas como localização no minimapa.

## Evidência

- [Entrada](01_entrada.png)
- [Advertência](02_advertencia.png)
- [Fechadura](03_cofre.png)
- [Coleta e divisórias](04_coleta.png)
- [Cerco com três viaturas](05_cerco.png)
- [Saída sob confronto](06_fuga.png)

`tests/test_bank_heist_flow.gd` executou 31 verificações com Vulkan, incluindo entrada/saída pelo gerenciador real, interação, projéteis, bloqueio físico do cofre, coleta, deslocamento real das três viaturas, perseguição após a saída e compatibilidade com o caixa do posto. `tests/test_bank_robbery.gd` mantém o ponto de entrada anterior para a mesma suíte.

Também passaram `tests/test_police_fair_arrest.gd`, `tests/test_responder_routines.gd` e a checagem de referências de recursos.

## Limites da verificação

As capturas e verificações cobrem uma execução controlada; não medem dificuldade de combate nem substituem uma partida completa. O teste acelera o relógio na espera pelas viaturas, sem reposicioná-las. Os avisos de objetos remanescentes no encerramento estão preservados nos logs.

A suíte antiga `test_harbor_interiors.gd` não completou: pressupõe `gunsmith_npc` na Ammu-Nation, cuja implementação está sendo alterada em outra sessão. Também registrou expectativas antigas sobre Tito e limites da câmera da garagem. Esses problemas estão no log `interiors.txt`; não se trata de uma aprovação da suíte inteira de interiores.
