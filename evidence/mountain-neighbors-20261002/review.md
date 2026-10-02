# Prédios vizinhos das lojas — 02/10/2026

Ampliação solicitada após a reforma das lojas: Summit junto à Boutique Alpina, chalés da vila e laterais/fundos das lojas. Três famílias de fachada corrigidas; os modelos compartilhados propagam o acabamento às suas instâncias existentes. Nenhum lugar/interior novo. Interiores não foram reformados neste complemento; bunker militar preservado.

## Causas e correções

- Summit: águas do telhado cortavam o topo das paredes e deixavam uma abertura na cumeeira. Cobertura recalculada, frontões triangulares e fechamento dos beirais. Oito janelas existentes estavam parcialmente enterradas na parede; reposicionadas. Acrescentadas seis janelas laterais.
- Chalés: empenas feitas de caixas escalonadas atravessavam o telhado. Substituídas por frontões triangulares sob as águas elevadas. Neve, cumeeira, caibros e arremate da chaminé acompanham a cobertura. Janela lateral antes escondida foi substituída e incluídas janelas na outra lateral e nos fundos, afastadas das ferramentas.
- Lojas: cobertura também passava dentro das paredes laterais. Águas elevadas e frontões/cumeeira fechados. Uma janela em cada lateral e duas nos fundos.
- Madeira/pedra texturizadas; janelas com molduras, montantes e peitoris. Nenhuma luz dinâmica nova. Materiais do Summit aplicados apenas à fachada, preservando outros modelos que herdam seu construtor.

## Validação

Godot 4.7.2 .NET, C# compilado sem erros/avisos, Vulkan Mobile, RTX 4060 Laptop GPU, 1280×720, Main real com câmera diagnóstica em quatro direções. Saves pessoais preservados.

- **71 verificações aprovadas**: duas águas por modelo, paredes/empenas abaixo da cobertura, encontro na cumeeira, vidro fora das faces opacas, janelas esquerda/direita/fundos, porta fechada bloqueia jogador, aberta admite e paredes laterais continuam sólidas. [Teste](../../tests/test_mountain_exterior_finish.gd), [log final](physics-final.log).
- Fotos antes/depois em quatro ângulos para cada família. Cobertura visual amostrada em Summit, Chalé 03 da vila e Boutique Alpina, incluindo instâncias vizinhas visíveis; não é uma visita individual a todos os imóveis do mapa.
- **Performance inconclusiva:** base contém três amostras de 30s, mas outra sessão iniciou `capture_footer_prompt.gd` durante a medição; [registro](processes-before.json). Não usar os FPS da base ou das capturas para aprovar ganho/regressão. Dependências de mundo monitoradas tiveram hashes iguais entre amostras.
- Uma execução intermediária sofreu erro concorrente `AirK9Models.dog_scale()` ausente. A função surgiu depois no arquivo da outra sessão; fizemos nova execução após essa mudança concreta. Arquivos da polícia não foram alterados nesta tarefa. Logs intermediários preservados em `after.log` e `../mountain-exterior-finish-20261002-physics.log`.
- Geometria estática e portas locais validadas; sem certificação de todo o fluxo de interiores, save/load, movimento de NPC nas novas fachadas, chuva/noite ou estabilidade temporal integral de sombras. Nenhuma mudança global de iluminação/câmera.

## Fotos

| Fachada | Antes | Depois frontal/lateral | Depois fundos/lateral |
|---|---|---|---|
| Summit | [foto](before/ski_lodge-15.0-15.0.png) | [foto](final/ski_lodge-15.0-15.0.png) | [foto](final/ski_lodge-15.0--15.0.png) |
| Chalé | [foto](before/mountain_cabin_village_3-15.0--15.0.png) | [foto](final/mountain_cabin_village_3-15.0-15.0.png) | [foto](final/mountain_cabin_village_3-15.0--15.0.png) |
| Loja | [foto](before/mountain_boutique-15.0--15.0.png) | [foto](final/mountain_boutique-15.0-15.0.png) | [foto](final/mountain_boutique-15.0--15.0.png) |
