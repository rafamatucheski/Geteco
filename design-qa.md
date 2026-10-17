# Harbor — menu centralizado

final result: passed

Escopo: apresentação do menu principal, seleção de saves, novo jogo e configurações. Não certifica o carregamento do mundo ou os demais sistemas do jogo.

## Referência e evidências

- Referência aprovada: `C:/Users/rafae/.codex/generated_images/01a13f3f-db8c-75a0-a2b0-643d252490c6/exec-7b41ef3c-cc47-4778-97eb-28738f5339d6.png` (1672×941).
- Capturas renderizadas: `evidence/centered-title-menu/main.png`, `main-4x3.png`, `saves.png`, `new-game.png`, `settings-0.png`, `settings-1.png`, `settings-2.png`.
- Comparação conjunta da referência e captura principal, mesma proporção 16:9, captura em 1280×720; teste adicional em 1024×768. Estado principal: Continuar selecionado, português.

## Correções após a primeira comparação

- P2: título em Barlow estava fino e pequeno. Substituído por wordmark raster transparente derivado da referência; proporção preservada via AtlasTexture.
- P2: textos do menu estavam compactos. Aplicado espaçamento entre letras e largura da seleção ajustada.
- Nova captura após correções confirmou título, hierarquia, centralização e leitura. Sombra discreta dá suporte aos textos sobre reflexos.

## Superfícies verificadas

- Tipografia: wordmark pesado em marfim; Barlow existente nos controles, com espaçamento ampliado. Sem quebras nas ações verificadas.
- Layout: título e ações centralizados; fundo cobre a tela sem distorção; saves e configurações substituem as ações, preservando a arte.
- Cores: água azul quase preta, marfim e detalhes dourados; foco usa faixa clara com texto escuro.
- Imagens: fundo e wordmark gerados com Image Gen a partir da opção aprovada. Sem personagens ou revelações narrativas.
- Conteúdo: funções existentes preservadas; importação V1 acessível dentro da seleção de saves. Preferência de idioma do usuário continua sendo respeitada (português aplicado só no processo de captura).
- P3 aceitos: ausência do pequeno triângulo decorativo; foco continua explícito pela faixa. Texto funcional existente “Sair do jogo” e aviso de versão alfa preservados. Pequenas diferenças no desgaste do wordmark e fonte dos botões.

## Validação

- `dotnet build Harbor.csproj --no-restore`: 0 erros, 0 avisos.
- `tests/test_centered_title_menu.gd`: PASS. Centralização, abertura/retorno de saves, cancelamento de importação, três abas, restauração de foco e novo jogo sem gravação.
- `tests/test_menu_idle.gd -- --measure`: PASS antes/depois, saves da fixture intactos e nenhum mundo iniciado sem clique.
- Godot 4.7.2 .NET, Forward Mobile, RTX 4060 Laptop, VSync e limite 60 FPS; 30 segundos por amostra. Baseline versus final: p50 16,666→16,666 ms; p95 16,873→16,823 ms; p99 17,979→17,297 ms; máximo 1521,729→1176,289 ms; média incluindo inicialização 56,49→57,32 FPS; 3 frames acima de 33,3 ms e 3 acima de 66,7 ms em ambas. Sem regressão observada neste cenário de menu. Picos de inicialização permanecem; não é certificação global de FPS.
- Relatórios: `evidence/menu-on-demand-20261002/deepwater-before/report.json` e `deepwater-final/report.json`.
- Limite externo: importação do editor detectou erro de inferência em `world/desert/village/DesertVillageDoor.gd:27`, arquivo já alterado por outra sessão. Não modificado aqui. Entrada no mundo não foi revalidada nesta entrega.
