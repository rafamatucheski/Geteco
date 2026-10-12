# Lanterna nos esgotos — 12/10/2026

A camada 2D de escuridão dos esgotos adicionais encobria a luz da arma; o esgoto original usava outra apresentação. A correção aplica ambiente local com energia ambiente de 0,025, suspende a contribuição do sol durante a ocupação e preserva as superfícies realmente iluminadas no shader de escuridão. A lanterna existente continua com energia 5 e alcance 24 m; suas sombras ficam habilitadas dentro do esgoto e o estado anterior retorna na saída/descarregamento.

Paredes cortadas pela câmera recebem malhas somente de sombra com altura de 2,8 m, sem alterar colisões ou esconder personagens. O esgoto original passa a compartilhar o mesmo controlador. Não há novo SubViewport, luz adicional da arma, raycast por pixel ou mudança no inventário.

Ambiente: Godot 4.7.2 .NET, Harbor.csproj compilado (zero erros/avisos), Mobile/Vulkan, NVIDIA RTX 4060 Laptop GPU, 1280×720. Saves pessoais preservados com `--no-save`.

## Evidência

- `tests/urban_detail/test_sewer_darkness.gd`: 12 verificações aprovadas, incluindo sala pré-carregada, ambiente externo intacto, restauração e descarregamento da sala ativa.
- `tests/test_sewer_refresh.gd`: 312 verificações aprovadas nos sete esgotos, com corpos reais de Dante/NPC, sólidos/cantos, spawn, coleta e áudio/reativação.
- `tests/test_sewer_depth.gd`: fixture atualizada pela sessão concorrente, preservada e executada novamente; 105 verificações aprovadas nos sete esgotos, separando diagnóstico de oclusão da camada de escuridão.
- `tests/urban_detail/test_sewer_flashlight.gd`: arma e sessão reais verificadas no original e, em processo separado, no Mercado; 11 verificações por lugar de entrada, ambiente, sombras, acionamento/desligamento, saída e restauração. O Mercado registrou erros externos em `CobraModel.gd:57` (`fit_seat`, malha nula) durante streaming de patrulheiros; não confundir checks locais aprovados com jogo inteiro sem erros.
- Giro da mira por 30 segundos em cada lugar: 1.555 frames no original (30.007 ms; intervalo p95 25 ms, máximo 45 ms) e 1.669 no Mercado (30.002 ms; intervalo p95 23 ms, máximo 54 ms). Todos os frames capturados têm timestamps. Folhas de contato inspecionadas; intervalos acima de um frame deixam a certificação de defeitos de um único frame inconclusiva.
- `tests/urban_detail/test_sewer_flashlight_occlusion.gd`: seis verificações renderizadas aprovadas em `harbor_sewer` e `sewer_market`. Ganho de luminância do objeto exposto: 0,317 / 0,318; atrás da parede: 0 / 0; removendo a parede: 0,621 / 0,622. Fixture elevada isola a oclusão da lanterna da geometria já autorada; não certifica todas as paredes do mapa.
- Fotos reais e sequências com timestamps: `evidence/sewer-flashlight-20261012/`. As fotos `*-off.png` e `*-on.png` comparam lanterna desligada/ligada após a correção, não implementação anterior/posterior.

## Limites da validação

Sem aprovação completa de FPS: havia outro benchmark renderizado durante a preparação e não foi capturado baseline comparável antes da implementação. As sequências temporais com readback/JPEG não são benchmark de desempenho. O alvo provisório permanece 60 FPS/16,67 ms; tolerância de regressão de p95/p99: 5%, a confirmar com amostra equivalente se excedida.

O teste de profundidade `tests/test_sewer_depth.gd` apontou inicialmente duas falhas de legibilidade no original; a fixture selecionava um tijolo periférico e colocava atores fora da sala. Outra sessão corrigiu essa fixture durante o trabalho; o arquivo foi preservado. A verificação diagnóstica intermediária sem esta iluminação também revelou uma falha de seleção/oclusão da fixture. A execução final da fixture corrigida passou nas 105 verificações, sem alterar suas exigências para esta entrega.

O teste produtivo encontrou recusa da entrada do Mercado ao posicionar Dante em diagonal ao acesso. A fixture passa a usar a posição junto da escada, como o teste de sessão existente. Isso não altera o acesso produtivo e não comprova todas as aproximações de entrada.

Cobertura visual completa dos sete interiores, movimento através de todas as paredes/objetos, save/load real, pausa e comparação de performance permanecem pendentes. Não contar este lote como migração totalmente aprovada.
