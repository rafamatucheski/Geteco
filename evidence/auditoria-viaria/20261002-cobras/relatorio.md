# Bairro dos Cobras — revisão local de 02/10/2026

## Escopo e resultado

Revisão da apresentação exterior, caminhos de pedestres, bancos e população própria do bairro. Materiais escuros com textura, madeira e metal gastos, vegetação com volume, árvores variadas, barris e emblemas dos Cobras. Telhados corrigidos para encontrar a cumeeira e dispensar adereços destinados a coberturas planas.

As conexões usam o mapa salvo: quatro registros de calçada foram alinhados, removendo dois contornos deformados. Junções compartilhadas recebem acabamento arredondado; caminhos alcançam os pisos táteis das travessias existentes. O último ajuste de extremidade foi conferido na captura renderizada `finished/garden.png`. Não houve redesenho do grafo viário, fases de semáforos ou mudança de prioridade. Este relatório não aprova o trânsito da cidade inteira.

Restaurados três guardas (Ren, Haruka e Daichi) e dois moradores (Aiko e Ryo). Visita normal não inicia combate; agressão real provoca os guardas. Estados de missão e derrota da gangue são respeitados, assim como persistência de mortes e suspensão ao sair da área.

## Validação

- Godot 4.7.2 .NET, C# compilado com sucesso, zero avisos e erros.
- `tests/test_cobra_roof_finish.gd`: 32 verificações aprovadas.
- `tests/test_world_editor_cobra.gd`: 16 verificações aprovadas.
- `tests/test_cobra_walkway_connections.gd`: oito verificações aprovadas, incluindo junções do mapa salvo e ausência de grama nos caminhos. Executado antes do último ajuste pequeno da extremidade tátil, conferido depois em renderização real.
- `tests/capture/capture_cobra_neighborhood.gd --validate --motion --night`: população, saída/retorno, agressão, persistência, missões, derrota e deslocamento aprovados. Jogador e NPC real bloqueados pelo banco, sem subir sobre o assento. Zero falhas na execução `final`.
- Capturas reais em quatro pontos, mais praça à noite. Sequência de movimento disponível; inspeção dos extremos confirma jogador apoiado no terreno. Não representa certificação temporal de toda a iluminação; luzes não foram alteradas nesta tarefa.
- Alterações conferidas com `git diff --check`, sem erros de whitespace.

## Evidências

Pasta externa: `D:/geteco/artifacts/cobra-neighborhood-1002/`.

- `finished/entrance.png`, `garden.png`, `garden_night.png`, `workshop.png`, `south.png`: acabamento final.
- `final/bench_collision.png`: colisão do banco na cena real.
- `final.log`: resultados funcionais.
- `final/motion_000.jpg` a `motion_089.jpg`, `motion.json`: percurso renderizado.
- `finished/frames.json`, `finished.log`, `measurement-processes.json`: desempenho atual e monitoramento de processos.

SHA256 do mapa antes das quatro correções: `5B19A800335498273942766E4E4F22300E12888F785A1FE642276E3E8AC6DAF6`.
SHA256 após: `A349AC113D3E2D3A98870E444F65158E9C6204A7D354A7E7C44ECE2A9E53B1B5`.

## Performance e limites

Medição atual de 30,003 segundos na entrada, cena real renderizada, 1280×720, Mobile, RTX 4060 Laptop GPU, VSync desligado, sem limite de FPS: 7.049 frames, média 234,94 FPS, p50 3,323 ms, p95 8,154 ms, p99 16,625 ms, máximo 97,188 ms. Oito frames acima de 33 ms e dois acima de 66 ms. Três Cobras e população total informada de 31. Execução monitorada sem concorrência de outra instância de jogo.

Não existe baseline anterior comparável e isolado: outras sessões executavam o jogo durante a preparação. Portanto, a comparação antes/depois permanece pendente e performance sem regressão não está aprovada. A amostra atual cobre a entrada parada; não certifica combate prolongado, toda a cidade ou todos os percursos. Trabalho concorrente no repositório foi preservado.
