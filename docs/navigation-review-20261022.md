# Revisão de missão, minimapa e lugares — 22/10/2026

## Comportamento

- `FullSession.navigation_destination()` seleciona um registro de destino compartilhado por minimapa, mapa completo e indicador exterior: posição, nome, símbolo, região, texto e origem. Não altera progresso nem recompensas.
- No serviço de Neco: a pé ou em outro veículo, o destino é **Guincho do Neco**; dirigindo o guincho, é **Caminhonete da cliente**. As etapas seguintes identificam a baia, Neco e Ferrugem.
- O minimapa mostra nome e distância acima do desenho, direção na borda para destinos distantes e símbolo selecionado; mantém indicação de chegada a menos de 3 m. Destino na origem do mundo também é válido.
- Entradas de serviços usam os símbolos do mesmo catálogo do mapa completo. Neco, Ferrugem e Maciota têm referências nomeadas nos dois mapas. O minimapa limita a oito símbolos próximos, afasta símbolos sobrepostos e escreve até dois nomes; o mapa completo conserva o catálogo detalhado e seus filtros.
- Marcar um lugar no mapa completo preserva nome e coordenadas para o minimapa. Uma missão ativa tem prioridade; o destino manual reaparece na exploração e limpar o destino remove nome, marcador e rota.
- A apresentação temporária do nome do veículo ganha uma linha separada do destino e do objetivo durante o embarque.

## Validação e limites

Godot **4.7.2 .NET**, C# compilado por `dotnet build Harbor.csproj --no-restore -v quiet` (sem erros/avisos). APPDATA isolado e `--no-save`; saves pessoais preservados.

- `tests/test_navigation_destination.gd`: **19 verificações sem falhas**, incluindo etapas do guincho, outro veículo, prioridade do objetivo, destino na origem, limpeza e nomes importantes.
- `tests/test_ui_map_contract.gd`: **42 verificações sem falhas**, controles, filtros, seleção, destino e tamanhos de tela.
- `tests/test_world_map_atlas.gd`: **273 verificações sem falhas**, dados preparados das três regiões, serviços, limites de campanha, reutilização e preservação das ruas.
- `tests/measure/measure_navigation_review.gd`: **22 verificações sem falhas** na Main renderizada, [resultado](../artifacts/navigation-review-20261022/integration.json) e [log final](../artifacts/navigation-review-20261022/integration-final.log). [Minimapa a pé](../artifacts/navigation-review-20261022/01-objective-minimap.png), [guincho no mapa completo](../artifacts/navigation-review-20261022/02-truck-world-map.png), [destino atualizado após embarcar](../artifacts/navigation-review-20261022/03-truck-neco-landmarks.png). A fixture usa checkpoint validado e teleporte para preparar o bairro: não certifica dirigir o percurso inteiro ou carregar/entregar o carro. Verifica os mapas reais, seleção/limpeza de destino e interação normal de embarque com animação/corpo, sem forçar `Driving.occupied`.
- As expectativas antigas de distância sempre oculta em `test_compact_hud` e `test_contextual_ui` foram atualizadas para o novo pedido. Essas suítes completas não foram executadas nesta revisão.
- Cobertura de dados das três regiões não equivale a jogar todas as missões/atividades. Deserto, montanha, interiores e transições adicionais precisam de rodadas próprias para aprovação de gameplay.

**Performance: comparação inconclusiva.** Meta provisória 60 FPS / 16,67 ms; comparação de p95/p99 acima de 5% exigiria confirmação isolada. Havia outros processos Godot antes e durante a revisão, registrados em `concurrent-before.json` e `concurrent-during.json`. A primeira execução atingiu o limite de inicialização com fachadas em aquecimento por 51,94 s; outra detectou que a rotina de restaurar motorista da garagem não admitia o caminho desde a posição sintética da fixture. A execução seguinte testou a interação normal pela porta e passou. Uma inspeção visual detectou sobreposição entre nome do veículo e destino, corrigida com linhas separadas e verificações de retângulos. Logs anteriores foram preservados; não são passagens de teste.

A execução final registrou 60,00 FPS, p95 18,04 ms e p99 18,86 ms em 30 s, RTX 4060 Laptop, Forward+, 1280×720, VSync e limite de 60 ativos. Essa amostra registra apenas o estado atual renderizado, sem baseline isolado; não aprova regressão ou performance global. Logs conservam também o erro preexistente de array tipado no prewarm de materiais, alterações inválidas de `mountain_zoo_walk` e avisos de objetos retidos ao encerrar a fixture.
