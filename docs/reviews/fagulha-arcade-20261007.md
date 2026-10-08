# Fagulha — fliperamas jogáveis

Loja nova em Harbor, no espaço entre Boa Praça e Ammu-Nation: centro `(80, .12, 8.75)`, acesso `(80, .12, 15.05)`. **1 lugar físico / 1 interior distinto**. Nenhum prédio com função existente foi substituído. O catálogo publica o acesso no mapa e o indicador compacto de porta usa a transição compartilhada.

Quatro jogos originais: Bola de Aço (pinball, três bolas), Blocos (sete peças, rotação, linhas), Pista Neon (corrida, seis rivais, nitro) e Último Round (soco, chute, defesa, salto). Duas máquinas laterais ficam ocupadas por Lia e Ivo, com os rigs humanos nativos e mãos animadas nos controles. Quatro máquinas permanecem livres para Dante.

**Uso:** interação na entrada e diante da máquina; Enter/interação inicia a partida; direcional move; interação/Enter é a ação principal; freio de mão/Espaço é a alternativa; P pausa; Esc/Voltar sai. A interface mostra os comandos por jogo e as teclas remapeadas. Existem botões de toque, ainda sem validação em aparelho Android físico. Jogar é gratuito; recordes são persistidos no save, partidas em andamento não. O kit de primeiros socorros tem recibo persistente e coleta a pé.

## Implementação

- `world/places/arcade/`: sala 12×10 m, fachada, mobiliário, colisões e moradores. Padrão de câmera ortográfica alinhada, profundidade 3D real, materiais compartilhados e detalhes MultiMesh. Fachada somente com nome próprio.
- `activities/arcade/`: quatro modelos de jogo independentes e uma tela CanvasLayer, criada sob demanda. Sem SubViewport produtivo, criação de nodes por frame ou processamento dos jogos fora da tela ativa.
- `FullSession`, `PlaceCatalog` e `NativeRegion`: registro, entrada/saída, interrupções e prioridade de interação. O modal bloqueia movimento/combate e libera o controle ao sair. Nenhuma alteração nos contratos da garagem, da campanha ou das pontes.
- Duas luminárias locais fixas e sem sombras, alcance 10 m, energia 1,3 e atenuação 0,7, para legibilidade noturna; preservada a iluminação global. Sala inativa desliga apresentação e filhos; os residentes são removidos pela sessão na saída.

## Evidência funcional

Godot **4.7.2 .NET**, `Harbor.csproj` compilado com zero erros/avisos. Renderer Mobile, RTX 4060 Laptop, configuração efetiva de 1920×1080, MSAA 2, VSync 1 e limite 144 FPS. Save temporário exclusivo em cada pasta de evidência; nenhum save pessoal alterado. O Main confirma o roteador C# ativo.

- Regras dos quatro jogos: **85/85**, `tests/test_arcade_games.gd`. A regressão de lançamento natural em oito seeds encontrou a bola presa sob a guia; um canal físico de lançamento e trilho visível corrigiram a entrada na mesa. Reexecução final sem erros de parser; no Main renderizado, lançamento por input real entrou no campo e marcou 100 pontos mantendo as três bolas ([resultado](../../evidence/arcade-temporal-193732-6133984/pinball-launch.json)).
- Teclado e gamepad por eventos reais: **32/32**, `tests/test_arcade_controls.gd`. Inclui teclas remapeadas, separação de rotação/queda e soco/chute, início sem repetir comando, pausa e saída.
- Física e profundidade finais: **261/261**, [resultado](../../evidence/arcade-place-194272-6054816/results.json). Inventário sólido completo, cápsulas de Dante e visitante, movimentos varridos contra faces/cantos, caminhos válidos, moradores, oclusão e controles positivos. Inclui suspensão e restauração das duas luminárias finais. Um parser concorrente em `SupraA80Model` foi emitido no startup dessa fixture e corrigido pela sessão responsável; os 261 checks locais executaram, sem ampliar esse resultado para aprovação global do projeto.
- Main final: **92/92**, [resultado](../../evidence/arcade-session-192568-6308029/result.json). Caminhada pela calçada, admissão, caminhada aos quatro gabinetes, quatro partidas, bloqueio real do combate e movimento, pausa, saída, recordes em arquivo, reentrada, substituição de modal e interrupção por dano. A execução anterior tinha 91/92 porque a consulta de interrupção usava frames físicos antes do frame de processamento; o teste passou a aguardar o callback real, sem alteração no runtime.
- Carga fria dos bytes do save real da execução anterior: **26/26**, [resultado](../../evidence/arcade-restore-193564-6337176/result.json), [save de origem](../../evidence/arcade-session-194776-6674225/save.json). Recordes restaurados, dois moradores sem duplicação, controle livre, dano interrompendo no próximo frame, acesso ao pickup, retorno à fachada e recompensa sem duplicação. O teste atribui pontuação conhecida para verificar persistência; regras e pontuação natural são exercitadas separadamente.

As tentativas anteriores mantêm erros de parser já corrigidos, uma fixture que desativava o corpo físico antes da consulta de profundidade e uma execução que usava `--no-save` indevidamente para testar persistência. Esses resultados não foram usados como aprovação. O caminho artificial que cortava a posição de Lia foi substituído pelo corredor livre; a NPC e sua colisão foram preservadas.

## Fotos e apresentação

- [Terreno antes](../../evidence/arcade-before-192704-6030704/street.png).
- [Fachada](../../evidence/arcade-session-192568-6308029/01-facade.png), [salão diurno final](../../evidence/arcade-after-193168-6042727/room.png), [salão noturno final](../../evidence/arcade-temporal-193732-6133984/frame-000000.jpg).
- [Pinball com pontos naturais](../../evidence/arcade-temporal-193732-6133984/pinball-first-points.png), [Blocos](../../evidence/arcade-session-192568-6308029/03-blocks.png), [Corrida](../../evidence/arcade-after-193168-6042727/racer.png), [Luta](../../evidence/arcade-session-192568-6308029/03-fighter.png).

O interior é novo; foto anterior da sala não se aplica. A primeira sequência noturna mostrou piso e Dante escuros; motivou as duas luminárias locais. As fotos finais mantêm o ambiente escuro à noite com leitura do corredor, máquinas e personagens.

Sequência noturna final no Main: **1.709 frames / 30,989 s**, aproximadamente 15 s parado e 16 s andando. Arquivos/índices contínuos, contador de frames do motor com todos os deltas iguais a 1. Nas seis regiões estáticas sem personagens houve **zero candidatos a flicker**, maior salto médio 0,075/255; nas paredes, até 0,017/255. Oito panoramas e oito pares de maior variação inspecionados, sem piscadas ou popping observados. [Análise e limites](../../evidence/arcade-temporal-193732-6133984/temporal-analysis.json), [panoramas](../../evidence/arcade-temporal-193732-6133984/temporal-contact-sheet.jpg), [pares](../../evidence/arcade-temporal-193732-6133984/temporal-ranked-pairs.jpg). Captura nativa 1920×1080 reduzida para JPEG 960×540 apenas para armazenamento; readback não usado como FPS. Cobertura restrita à sala, rota e noite testadas, sem certificar exteriores, outros climas ou transições de iluminação.

## Desempenho e limites

Meta provisória: 60 FPS / 16,67 ms, sem degradar qualidade ou população. Comparar p95/p99 com limiar de investigação de +5%, amostras de pelo menos 30 s, separando entrada/aquecimento. O limite normal de 144 FPS não prova folga de GPU. Headless, fotos e gravação com readback não são benchmark.

A baseline inicial renderizada registrou p95 13,019 ms / p99 14,948 ms na rua; outras sessões do Godot estavam ativas e arquivos compartilhados continuavam recebendo trabalho. Ela é diagnóstico, não comparação isolada suficiente para certificar regressão. Fonte, processos concorrentes e configuração devem acompanhar o comparativo final.

O primeiro comparativo final iniciou após inventário vazio de processos Godot. Durante a preparação, outra sessão iniciou `measure_park_countryside.gd` e uma terceira gravou `test_upside_world_session.gd --capture`. A medição da Fagulha foi interrompida ao identificar o benchmark concorrente; nenhum processo alheio foi encerrado. [Inventário temporal de processos](../../evidence/arcade-process-audit.jsonl).

A segunda tentativa final terminou, mas também teve concorrência (`test_upside_world_lifecycle.gd` renderizado e teste headless do Supra). Os hashes mudaram em `FullSession.gd` e `DesertDrag.gd` durante a execução. É **diagnóstico da cena real**, não aprovação comparativa: [amostras/configuração/hashes](../../evidence/arcade-after-193168-6042727/report.json), [processos por horário](../../evidence/arcade-final-process-audit.jsonl). População observada: 28 pessoas/33 veículos; C# ativo, configuração gráfica preservada.

| Cenário final | Amostra | p95 | p99 | Maior frame | Frames >33,3 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Rua | 30,880 s | 11,842 ms | 13,733 ms | 51,457 ms | 1 |
| Salão | 30,868 s | 10,900 ms | 11,622 ms | 25,860 ms | 0 |
| Corrida jogando | 30,997 s | 10,461 ms | 11,044 ms | 20,647 ms | 0 |

Entrada separada: maior frame 39,641 ms; aquecimento da rua: 113,526 ms. Não atribuir causalidade desses picos à Fagulha com fontes/processos concorrentes. **Performance comparativa inconclusiva**, sem afirmar ausência de regressão. O runner `tests/measure/measure_arcade.gd` mede rua, sala e corrida em janelas de 31 s e registra hashes das fontes.

Pendente: comparação isolada da versão final. Não certificar globalmente cidades, outros horários/climas, Android, áudio ou combinações fora dos cenários descritos.
