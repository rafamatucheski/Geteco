# Loading: apresentação independente — 22/10/2026

## Mudanças

- `ui/LoadingCanvas.cs` desenha as imagens com Direct2D por hardware na thread própria do apresentador Windows. As texturas são enviadas uma vez; zoom, deslocamento e crossfade deixam de redimensionar imagens grandes pela CPU a cada quadro. A tipografia Barlow é rasterizada em uma faixa pequena, atualizada somente quando muda a porcentagem.
- `LoadingPresenter` recebe a meta real da etapa e interpola a barra no próprio relógio. Ao alcançar a meta, a barra espera; a animação continua. Uma apresentação atrasada não salta várias imagens. Proporção e escala uniforme das artes são preservadas.
- `StartupCurtain` termina a transferência dos pixels antes de iniciar o dispositivo de apresentação. Na investigação, uma inicialização ficou presa em `Texture2D.GetImage`, confirmada por `dotnet-stack`; após separar a inicialização, o probe completou. A estabilidade renderizada dessa ordem final ainda precisa ser confirmada.
- A arte do Godot fica parada enquanto o apresentador nativo trabalha. O caminho portátil continua disponível quando o nativo não é usado ou falha.
- Novo jogo/falha de prévia transfere a cortina existente do menu para a raiz. Antes, o caminho podia abrir uma segunda cortina com outro apresentador e outro relógio sobre o primeiro. A transferência mantém opacidade, progresso e instância da arte. O menu deixa de ser dono dessa cortina antes de ser removido.
- O menu aguarda a preparação da apresentação antes de iniciar o fade e o trabalho pesado.

O mundo, os recursos Godot e a SceneTree continuam na thread principal. A thread de apresentação recebe somente pixels próprios, fontes e metas numéricas.

Referências da integração: [render target Direct2D para HWND](https://learn.microsoft.com/en-us/windows/win32/direct2d/id2d1factory-createhwndrendertarget), [composição e opacidade de janelas](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setlayeredwindowattributes).

## Evidência e limites

Ambiente: Godot 4.7.2 .NET, Windows, Vulkan Forward+, NVIDIA RTX 4060 Laptop. Desktop em 3440×1440; a janela fullscreen do motor tem 3440×1442 pixels de cliente. Meta provisória: apresentação a 60 FPS, sem saltos de imagem. Gameplay mantém as opções do jogador.

Artefatos locais: `artifacts/loading-smooth-20261022/`.

| Execução | FPS de apresentação | p50 / p95 / p99 | Máximo | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|
| Antes: loading real, 244 intervalos / 42,36 s, fullscreen | 5,76 | 151,86 / 288,57 / 311,41 ms | 336,36 ms | 244 / 244 |
| Primeiro protótipo GPU: teste isolado, 468 intervalos / 8,23 s, janela + resize + fullscreen | 56,85 | 17,51 / 18,68 / 19,35 ms | 37,65 ms | 1 / 0 |

Esses cenários têm duração/carga/resoluções diferentes e a segunda linha precede os ajustes finais. Demonstram um gargalo no caminho anterior e uma melhora preliminar; **não constituem aprovação comparativa da versão final**. Nesse protótipo, 171 quadros continuaram sendo apresentados durante uma pausa síncrona de três segundos na thread do motor; resize, fullscreen e destruição passaram.

O primeiro comparativo integrado depois da mudança (`after.json`) apresentou zero quadros nativos porque a janela ficou fora do primeiro plano. O probe confirmou `parent_foreground=false` mesmo com `Window.has_focus()` do Godot retornando `true`. Essa amostra não aprova fluidez. O teste do apresentador passou a exigir apresentação nativa efetiva, e o medidor rejeita zero quadros como sucesso. A tentativa posterior de 30 s também ficou sem apresentação e foi preservada em `presenter-unmeasured.json`.

O usuário interrompeu o controle da interface com Escape e depois pediu explicitamente para continuar sem validação visual. Não foram feitas novas inspeções da interface depois da interrupção. **Validação visual temporal, comparação final de 30 s em primeiro plano e medição em export release permanecem pendentes.** Os builds C# Release não equivalem a esse benchmark. Sem evidência visual, não se certificam ausência de glitches, composição final ou qualidade dos fades.

Houve alterações concorrentes em `ProductionWorld`, `RainPrewarm`, `StallLog` e `VehicleMaterialVariantPrewarm`, preservadas. Os tempos totais de carga registrados não permitem atribuir uma redução exclusivamente a esta correção, também por diferenças de cache/foco.

## Validação funcional final

Todos os comandos de motor abaixo usaram a instalação .NET 4.7.2 do projeto, após compilar `Harbor.csproj`.

| Verificação | Resultado e escopo |
|---|---|
| `dotnet build Harbor.csproj --no-restore` | Passou, zero erros/avisos |
| `dotnet build Harbor.csproj -c ExportRelease --no-restore` | Passou, zero erros/avisos |
| `--headless --script res://tests/test_loading_handoff.gd -- --no-save --skip-arrival` | Passou: etapas reais, sessão incompleta sem entrada, barra em 100%, cobertura removida, controles restaurados, nenhuma cortina restante na raiz |
| `--headless --script res://tests/test_loading_menu_handoff.gd -- --no-save` | Passou: mesma cortina/arte no novo jogo, cobertura opaca, progresso preservado, cancelamento e remoção do menu não destroem a cortina transferida, partida direta com arte regional, limpeza |
| `--headless --script res://tests/test_loading_slideshow.gd -- --no-save` | Passou: ciclo das 15 artes do fallback, árvore pausada/progresso parado, proporção/cobertura em 1280×720, 2560×1080 e 720×1280, progresso sem regressão/avanço fictício e liberação sem esperar o ciclo |

O handoff apontou também um erro de edição do mundo fora deste escopo (`path/mountain_zoo_walk` ausente/inválido). As saídas dos testes têm avisos de ObjectDB/recursos retidos no encerramento; isso não foi contado como validação de limpeza global do jogo. A execução renderizada inicial registrou erros de gravação do cache de shaders e de preparação de materiais. Não foram ocultados nem corrigidos por mudanças alheias ao loading.

Para retomar: `tests/test_loading_presenter.gd` exige a janela em primeiro plano e inclui pausa síncrona, reparenting, resize, 30 s de fullscreen com barra parada e fade/destruição. Depois, executar `tests/measure/measure_loading_slideshow.gd` com `--no-save --skip-arrival --benchmark --no-captures --report=<destino novo>` no fluxo real e validar novo jogo e continuar visualmente. Não sobrescrever saves pessoais nem misturar amostras em segundo plano com apresentação visível.
