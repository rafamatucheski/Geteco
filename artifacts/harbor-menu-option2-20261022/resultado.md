# Harbor — pausa, configurações e mapa

22/10/2026. Implementação nativa em Godot 4.7.2 .NET, baseada na segunda imagem escolhida e nas correções posteriores do usuário.

## Resultado visual

- Pausa em duas colunas, mantendo os botões e sinais existentes. Retomar em dourado; progresso, guia, configurações e saída separados. Desenvolvedor continua acessível.
- Fonte Barlow regular, 20 px, antialiasing, oversampling 2 e mipmaps, sem sombra/contorno nos controles. Mesmo tamanho e peso nos títulos, ações, opções e textos auxiliares. Capitalização de frase em português e inglês. Cantos de 12 px.
- Configurações em superfície ampla, com Tela, Qualidade, Avançado e Idioma; todas as opções anteriores preservadas. Teclado diretamente acessível, diagrama do gamepad disponível por escolha, colunas alargadas e nomes das teclas sem tradução automática indevida.
- Mapa com rótulos corretos, limites do relevo do deserto atualizados e escala métrica uniforme nas abas regionais: 0,611792 px/m em 1280×720; 0,410112 px/m em 800×600. O enquadramento Mundo possui seu próprio zoom para acomodar o conjunto. Nenhuma coordenada de estrada, destino ou progressão foi transformada.
- Mar azul profundo com textura de água gerada, mipmaps e amostragem linear. Material estático em coordenadas de mundo, atrás da geografia e sem interceptar input. As terras e lagos continuam vindo dos dados reais.

![Pausa](02-pausa-1280.png)
![Configurações](03-video.png)
![Mundo](map/world.png)

Capturas adicionais: [inglês](pause-english.png), [configurações em inglês](settings-english.png), [teclado](06-controles.png), [gamepad](controles-gamepad.png), [tamanho compacto](settings-800.png), [Digo selecionado](map/desert-marked.png), [comparação com o conceito](comparison.png).

## Validação funcional e visual

- `dotnet build Harbor.csproj --no-restore`: sucesso, sem avisos ou erros antes das execuções .NET.
- `test_settings_menu.gd`: PASS. Ajustes imediatos, opções anteriores, remapeamento principal/secundário, mouse/gamepad, conflitos, teclas reservadas, cancelamento e restauração. A antiga exigência de rolagem na ajuda foi substituída pela propriedade real: o último tópico precisa ficar inteiramente visível após receber foco.
- `test_ui_map_contract.gd`: PASS, 45 checks. Seleção, destinos, filtros, navegação, fechamento, camada de mar atrás das terras, escala do material e input livre.
- `test_world_map_atlas.gd`: PASS, 273 checks. Estradas e coordenadas reais, regiões preparadas sem montagem de chunks, progressão da ponte e cache de relevo. Reutilizado após alterações apenas de fonte e mar.
- `test_harbor_menu_layout.gd`: verifica ações visíveis e fonte de 20 px em 800×600 e 1280×720, acesso às opções por grupos, modos de controle e igualdade da escala regional.
- Capturas de produção isoladas: pausa/configurações em 800×600, 1280×720 e pausa em 1920×1080; português e inglês; mapa nas três regiões e Mundo, seleção e filtros em 1280×720 e 800×600. Não são evidência de FPS.
- Cena Main renderizada, C# confirmado e save isolado: pausa, configurações, abertura do mapa, Digo marcado, filtros, zoom e projeção/picking, fechar/reabrir preservando destino, limpar destino e recuperação do input. Execução terminou com código 0 em `evidence/harbor-menu-option2-381720-8415216/metrics.json`. Essa execução precede a última correção de tipografia e a inclusão do mar; não certifica o desempenho dessa revisão final.
- Não acionado salvamento sobre os arquivos pessoais do usuário. Callbacks de salvar/carregar e políticas de bloqueio foram mantidos.

## Desempenho: pendente, sem aprovação

RTX 4060 Laptop, Forward+, 1280×720, Main.tscn, C# ativo, horário 0,45, amostras finitas de 30 s, sem outros processos Godot nos checks. Medição inicial: `evidence/world-map-328384-8542479/metrics.json`; foi encerrada por nós após obter as duas janelas de baseline, portanto seu status geral continua `running` e não representa uma execução concluída. Medição intermediária concluída: `evidence/harbor-menu-option2-381720-8415216/metrics.json`.

| Cenário | FPS médio | p50 ms | p95 ms | p99 ms | máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes, mapa parado | 38,23 | 25,88 | 35,23 | 44,21 | 85,62 | 105 / 1 |
| Antes, arraste | 21,47 | 47,25 | 64,17 | 70,70 | 80,91 | 612 / 19 |
| Intermediário, pausa | 405,29 | 2,50 | 3,31 | 4,52 | 40,92 | 1 / 0 |
| Intermediário, configurações | 351,42 | 2,71 | 3,98 | 4,66 | 6,42 | 0 / 0 |
| Intermediário, mapa parado | 33,02 | 30,31 | 40,21 | 54,23 | 79,78 | 238 / 2 |
| Intermediário, arraste | 21,64 | 45,58 | 62,13 | 73,57 | 97,69 | 642 / 16 |
| Intermediário, deserto em movimento | 22,30 | 43,78 | 60,32 | 71,08 | 99,83 | 660 / 17 |
| Intermediário, VSync/limite 60 | 30,15 | 31,83 | 46,64 | 56,42 | 72,07 | 332 / 3 |

O mapa já estava abaixo da meta de 60 FPS antes da alteração. A janela estacionária intermediária piorou p95/p99 acima de 5%; não foi feita uma confirmação controlada dessa diferença, nem medição da revisão final com fonte e oceano. Regressão e desempenho final permanecem inconclusivos; não atribuir a causa ao mar ou declarar ausência de regressão com esses dados.

Também foram registrados defeitos preexistentes durante o carregamento: `VehicleMaterialVariantPrewarm.gd:146` (atribuição de array tipado) e edição inválida `path/mountain_zoo_walk`. As importações acionaram o aviso de rascunho antigo do editor; esse rascunho não foi substituído. A execução integrada reportou três ObjectDB restantes no encerramento, sem diagnóstico de origem nesta tarefa. Esses pontos não foram corrigidos fora do escopo.

## Limites

Aprovação visual e testes funcionais não certificam performance, ausência global de flickering, todas as condições da campanha ou um export de release. A última revisão de fonte/mar foi conferida nos componentes nativos isolados; o fluxo integrado anterior é evidência dos comportamentos preservados. O mar não tem animação e não altera iluminação, tráfego, física ou missões.

Textura, prompt e procedência: [ocean-asset.md](ocean-asset.md). Ícones Lucide e licença ISC estão em `assets/ui/harbor-menu/`.


## Separação apenas cartográfica — 22/10

Cidade, montanha e deserto recebem translações de apresentação, com 320 unidades de mar entre as caixas visuais. Sem mover terreno, jogador, rotas físicas, ponte ou campanha. MapIslandLayout converte destinos entre coordenadas reais e de exibição; marcadores usam região explícita e o waypoint conserva sua região. Duas linhas tracejadas representam as ligações já existentes. O estado de câmera anterior usa versão de layout para não reabrir deslocado. Mesma escala por metro nas três abas; as áreas continuam com dimensões reais distintas.

Validação: build Harbor.csproj sem erros; test_harbor_menu_layout PASS, incluindo separação e ida/volta de coordenadas; test_ui_map_contract PASS 45 verificações. Captura renderizada: map/world.png. A preparação ainda registra o erro preexistente path/mountain_zoo_walk. Sem aprovação de performance: não houve novo benchmark integrado comparável após esta mudança.
