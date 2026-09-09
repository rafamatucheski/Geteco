# Prévia de loadout e microtutoriais

Prévia interativa: `prototypes/loadout/index.html`. Pode ser aberta diretamente no navegador; servidor local da sessão em http://127.0.0.1:8769. Não modifica o inventário ou saves do jogo.

Proposta: três espaços (curta, longa, corpo a corpo), punhos sempre disponíveis, troca guardando a arma anterior. O inventário da demonstração é fictício. A simulação de descoberta preserva o loadout e apresenta a necessidade de escolher. Recuperação de equipamentos na garagem, persistência por veículo e limitações reais ainda precisam de integração no Godot.

Dicas de porta-malas, frio, túnel, item e busca policial aparecem uma vez por sessão, podem ser dispensadas e expiram em 12 segundos. A prévia simula contextos por botões; não detecta combate, velocidade ou menus reais. O catálogo/apresentador Godot foi separado no prompt do Claude. Modelo de porta-malas separado no prompt do Antigravity. Prompts entregues como arquivos, não enviados automaticamente.

## Correções aplicadas ao jogo

- Laterais do corredor da ponte começam na junção real do mundo contínuo, sem avançar para dentro do Harbor. A linha grossa sobre a estrutura virou uma borda fina; ligação inclinada entre as duas estruturas desenhada sobre a colisão existente.
- Os oito veículos da montanha são instanciados em frames separados no carregamento contínuo; a região só fica pronta depois de todos eles.
- Loja térmica estática desenha seu viewport quando se aproxima da tela, evitando renderização inicial fora de visão.

## Verificação

- Chrome/Playwright: troca de arma preserva a anterior; três espaços; fechar; descoberta não sobrescreve; dicas dispensadas não repetem; reset; viewport de 390 px sem overflow; sem erros JavaScript. Capturas em `D:/geteco/loadout-preview-desktop.png` e `D:/geteco/loadout-preview-mobile.png`.
- Godot/Vulkan `test_continuous_world.gd`: todos os checks passaram na ida e volta, mesmos objetos e sem barreira na junção. Log `D:/geteco/bridge-preview-final.log`.
- Teste de vida da montanha com `--headless --verbose`: passou e não reproduziu o aviso anterior de seis objetos. Isso não comprova que a causa foi corrigida. Log `D:/geteco/mountain-leak-diagnosis.log`.
- Perfil Vulkan: preparação 9,96 s, 285 frames, pico de 95,18 ms (anterior 158,02 ms). Pós-preparação: média 22,78 ms, pico 57,75 ms, em 100 frames. A referência inicial da própria execução também foi mais lenta (25,71 ms contra 18,10 ms da medição anterior). Não atribuir a diferença de média exclusivamente ao código nem anunciar FPS sustentado. Log `D:/geteco/stream-preview-fixes-profile.log`.

Ainda pendentes: streaming com descarregamento de setores, eliminação das travadas restantes, reprodução do aviso de objetos, integração oficial de loadout/tutorial e avaliação auditiva jogando. Nenhuma alteração em saves reais.
