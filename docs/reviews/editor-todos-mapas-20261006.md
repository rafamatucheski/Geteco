# Editor de mundo: todos os mapas disponíveis — 06/10/2026

## Escopo

Integração do deserto ao documento compartilhado, seletor, catálogo, biblioteca, prévia 3D e fábrica usada por `ProductionWorld`. Os adaptadores aplicam alterações durante a construção; não adicionam processamento por frame ao jogo. Peças transferidas de setor são registradas no destino. Interiores, objetivos, infraestrutura e vias especializadas mantêm seus vínculos e proteções.

O exportador inclui 793 registros de Harbor e 861 da montanha, além de 424 registros e 378 setores do deserto existentes durante a geração. Conteúdo de outras sessões continuou sendo alterado durante esta tarefa; **Atualizar base** lê os construtores atuais. Os contextos de sessão incluem as marcações da descida e o cenário autorado da trilha do jipe, sem afirmar integração jogável deste último.

O processo da prévia é separado da partida. Os snapshots perdem scripts e colisões ativas. Transformações e cores de instâncias agrupadas são preservadas em metadados somente na construção para a ferramenta. A base principal é exportada com renderer, como o botão existente do editor exige; a exportação headless inicial mostrou uma regressão de distribuição dos túmulos e foi substituída por geração renderizada.

## Evidências

- Godot 4.7.2 .NET, compilação de `Harbor.csproj`: sem erros ou avisos.
- `test_world_editor_desert.gd`: 23 verificações aprovadas, incluindo ajuste de altura no relevo, migração de documento, persistência isolada, posicionamento, identidade 3D, colisões e realocação de setor. A comparação inicial de dicionários após JSON foi corrigida para considerar precisão numérica.
- `test_world_editor_all_maps_live.gd`: 16 verificações renderizadas aprovadas: deserto em 3D, cena passiva, seleção, transformação, desfazer/refazer, colocação de cacto, salvar e alternar Harbor/montanha com cenários de sessão presentes. O primeiro runner tinha chamadas de método incorretas; foi corrigido antes da execução aprovada.
- `test_world_editor_desert_session.gd`: 7 verificações aprovadas no Main/.NET, incluindo caminho C# de roteamento, carregamento de objeto salvo, raio físico contra a colisão real e retorno após descarregar o setor. Save pessoal e documento oficial não foram alterados.
- `test_world_editor_piece_shapes.gd`: 23 verificações aprovadas.
- `test_world_editor.gd`: 46 verificações aprovadas.
- `test_world_editor_assets.gd`: 30 verificações aprovadas. Corrigido Ctrl+S para aplicar o valor numérico em foco antes de atualizar a seleção; antes, a atualização destruía o controle e perdia o valor digitado.
- Captura da ferramenta: `evidence/editor-all-maps-20261006/desert-editor.png`.

## Performance e cobertura

Baseline da ferramenta, 1440×900, RTX 4060 Laptop, Mobile, órbita real, 8 s de aquecimento e 30 s de amostragem: 176,77 FPS; p50 5,513 ms; p95 7,419 ms; p99 8,710 ms; máximo 20,794 ms; nenhum frame acima de 33,3 ms. Amostras: `evidence/editor-all-maps-20261006/before.json`.

Baseline do Main no deserto, com save isolado e rota C# real: 346,81 FPS; p95 5,899 ms; p99 8,289 ms; máximo 104,885 ms; 2 frames acima de 33,3 ms e 1 acima de 66,7 ms. Evidência: `evidence/desert-contracts-editor-before-123876-5037383/report.json`.

A comparação final de performance permanece pendente: a tentativa final pela fila compartilhada aguardou 120 segundos e terminou com `QUEUE_BUSY`, preservando os processos das outras sessões. Havia medições de atividades do deserto e testes de rotina/transmissão em execução. Nenhuma amostra final isolada foi obtida; mudanças concorrentes nos construtores também impedem atribuir uma eventual diferença somente ao editor. Esses valores iniciais não aprovam regressão nem desempenho global. Também não se certificam todos os interiores, missões, NPCs, iluminação noturna ou todos os pontos de todos os mapas pela validação do editor.
