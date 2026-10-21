# Edição direta em 3D — 26/09/2026

## Atualização de uso — 21/10/2026

A visão 3D agora compartilha os seletores de exterior, interiores e andares, os pincéis de relevo/textura e o documento de trabalho do editor. O [guia atual do editor](world-editor.md#editor-integrado-de-mundo--21102026) descreve os controles, os dois provedores de relevo disponíveis, as cópias de geometria e os limites da validação.

- **Enquadrar mapa atual** e **Limites dos mapas** ajudam a localizar o conteúdo; o alcance da prévia distingue área próxima e mapa inteiro.
- A topografia 2D é fornecida pelo mesmo worker quando a prévia 3D está aberta. Em 2D sozinho, a carga de terreno também fornece peças individuais editáveis; a imagem do chão não deve conservar fantasmas de peças movidas ou excluídas. A visualização reconhece cânions reais do Deserto, enquanto escultura de altura segue limitada a motocross e montanha.
- **Terreno** usa o ponto da superfície real e apresenta o raio da aplicação. Desative a ferramenta para voltar à edição de objetos.
- Escolher uma casa/empresa carrega sua sala real; **Andar** troca o piso quando disponível. A geometria da prévia permanece separada da simulação de gameplay.
- Alterações de interiores exigem validação da própria sala e do próprio andar antes de salvar. Cópia de geometria estática preserva seus sólidos para a aplicação no jogo; personagens e rotinas de serviço não são duplicados.
- O carregamento informa fases, indexação e erros. **Logs** permite ler e copiar o diagnóstico do worker; fechar a ferramenta encerra seu próprio processo auxiliar.

As medições finais estáveis registraram 60,002 FPS no [motocross 2D com relevo/pintura](../evidence/editor-workspace-20261021/topography-visible-harbor.json), no [Deserto 3D inteiro com LOD](../evidence/editor-workspace-20261021/lod-final-desert.json) e na [prévia do banco, andar 0](../evidence/editor-workspace-20261021/interior-final-interior-harbor_bank-floor0.json), em amostras de 30 s/1.801 frames, sem frames acima de 33,3 ms. As primeiras cargas continuam longas: 31,766 s, 100,423 s e 12,080 s, respectivamente. A imagem final do motocross foi inspecionada com relevo e Sand visíveis. Os detalhes e pendências estão no [guia de validação](world-editor.md#estado-da-validação-desta-revisão).

A [amostra nativa](../evidence/editor-workspace-20261021/native-frozen.json) usa `frame_post_draw`, prévia 650×379 e fundo do editor; não comparar seus 148,4 FPS com standalone limitado a 60. Teve 19 frames acima de 33,3 ms, pico estável de 45,979 ms e diagnósticos do motor no encerramento. O [smoke nativo posterior de 2 s](../evidence/editor-workspace-20261021/native-close-final.json), sem valor de benchmark, confirmou integração .NET e hashes preservados, saída GUI 0 e ausência de instâncias/RIDs/recursos vazados no log verbose após corrigir o wrapper Terrain3D. Mensagens C++ de RichTextLabel e EditorSettings/Android continuam sem atribuição, embora sem ScriptErrors; não declarar stderr nativo vazio. Cargas frias, reconstruções de cerca de 180–196 ms e pan muito além da margem de cache continuam pendentes. Não há certificação de ausência de travas em toda situação.

## Registro da implementação de 26/09/2026


A aba Mundo abre em 3D na primeira ativação. O seletor da barra oferece 2D, 3D e Lado a lado. O documento, a validação, o histórico e o botão Salvar mundo são compartilhados entre as visões.

## Uso

- Clique no objeto e arraste para mover pelo chão. As setas X/Z restringem o movimento a um eixo. Shift encaixa em passos de 0,5 m.
- Escolha Girar na barra da visão 3D e arraste o objeto ou o anel. Shift encaixa em 15°.
- Escolha Tamanho e arraste o objeto ou o quadrado: cima/direita aumenta, baixo/esquerda diminui. Dimensões individuais continuam disponíveis em Propriedades.
- Arraste um asset da biblioteca para a visão 3D. Também funciona armar o asset por duplo clique e clicar no destino.
- Delete exclui; Ctrl+Z desfaz; Ctrl+Shift+Z ou Ctrl+Y refaz; Esc cancela o gesto ou a colocação. Ctrl+C/Ctrl+V reutilizam a cópia do editor.
- Direito orbita a câmera, meio desloca a visão e roda aproxima/afasta. Salvar mundo aplica o documento à próxima execução do jogo.

Os limites e proteções dos objetos continuam os mesmos. Ruas e seus vértices continuam usando as ferramentas do mapa 2D; esta mudança trata objetos com posição, rotação e dimensões. A colocação é no plano horizontal da vista; a geometria definitiva adapta a altura ao terreno quando reconstruída. Não é um editor de interiores nem permite empilhar objetos em alturas arbitrárias.

## Implementação

`World3DEdit.gd` indexa a geometria da prévia por identidade, faz seleção pelos volumes das malhas e desenha o contorno e os controles. O worker preserva os IDs de peças; o adaptador acrescenta IDs dos registros originais somente quando está construindo a prévia.

Durante um gesto apenas as transformações da geometria selecionada mudam. Não há gravação nem reconstrução por movimento do mouse. Ao soltar, uma única alteração passa pela validação existente e gera um único item de histórico. A geometria definitiva é reconstruída pelo worker; novos gestos aguardam essa atualização. Esc, perda de foco da janela ou esconder a visão cancelam a transformação provisória. Soltar fora da visão também encerra o gesto.

O snapshot continua sem scripts de jogo e sem colisões ativas. Nenhum interior, acesso, save de progresso ou documento oficial foi alterado pelos testes.

## Validação e desempenho

Teste renderizado `tests/test_world_editor_3d_edit.gd`: **20 verificações aprovadas**, cobrindo seleção de telhado, movimento sem reconstrução por frame, uma entrada de histórico, giro, escala, cancelamento, desfazer/refazer, biblioteca, modos de vista, exclusão e persistência JSON. A comparação de valores recarregados usa precisão submilimétrica, pois o JSON não preserva a representação binária exata de floats. O plugin também passou na checagem de sintaxe do Godot.

Captura real: [edição 3D](../evidence/editor-3d/editing.png).

Benchmark da ferramenta real, não de gameplay: Godot 4.7.2 Mobile/Vulkan, RTX 4060 Laptop, 1440×900, câmera sobre a rodoviária, limite normal de 144 FPS, 8 s de aquecimento e 30 s de amostra, sem benchmarks simultâneos. Meta provisória: 60 FPS; tolerância de comparação p95/p99: 5%.

| Cenário | FPS | p50 ms | p95 ms | p99 ms | Máximo ms | Frames >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Órbita antes | 144,01 | 6,944 | 6,968 | 7,026 | 7,563 | 0 / 0 |
| Órbita com controles 3D | 144,01 | 6,943 | 6,976 | 7,109 | 7,589 | 0 / 0 |
| Órbita e arrasto contínuo | 143,92 | 6,944 | 6,998 | 7,194 | 22,239 | 0 / 0 |

Sem regressão acima do critério neste cenário: p99 da órbita +1,18%; com arrasto, +2,39% em relação à base. O limite de FPS impede inferir ganho de capacidade; não se afirma que 3D seja mais leve que 2D. A medição não certifica todos os mapas, o tempo de reconstrução após soltar nem a performance do jogo. Amostras brutas e configuração: `evidence/editor-3d/{before,after,drag}.json`. Avisos de interpolação da câmera e liberação de texturas no encerramento também ocorreram na base.
