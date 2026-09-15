# Indicador de interação

`ui/InteractionKeycap.gd` desenha o selo compartilhado das teclas de interação: fundo grafite, letra clara, borda fina, detalhe âmbar e base com relevo. Não usa animação contínua, textura, shader ou SubViewport. Os StyleBoxes são compartilhados e o desenho só é invalidado quando tamanho ou tecla mudam.

`GameplayPresentation` aplica o selo aos Labels cujo texto funcional de origem é `E`, depois de resolver o comando pelo `GameInput`. Teclas remapeadas e controle continuam funcionando. Labels criados durante streaming e carregamento de interiores entram no registro; os removidos saem dele. Textos de ação completos continuam sendo textos. Portas automáticas que deliberadamente ocultam o prompt mantêm esse comportamento.

## Validação — 12/09/2026

- Godot 4.7.2: `--headless --path D:/geteco/game --script res://tests/test_interaction_keycap.gd` passou nos 10 checks de integração com a apresentação, remapeamento, controle, visibilidade, reutilização, restauração de texto e descarregamento.
- Prévia renderizada dos selos E, F, A e Enter conferida em `D:/geteco/interaction-review/keycaps.png`.
- Medição preliminar em HarborGame, exterior da delegacia, 1280×720, Mobile/Vulkan, RTX 4060 Laptop, limite de 60 FPS, duas janelas de 30 s: antes 48,51 FPS, p95 35,00 ms, p99 44,24 ms; depois 43,22 FPS, p95 40,91 ms, p99 57,99 ms. Esse ponto não exibe o selo e as execuções tiveram variação suficiente para exigir confirmação. Não constitui aprovação de desempenho nem demonstra causalidade.
- A confirmação na bancada da oficina encontrou erros repetidos de referências nulas em `world/shared/pedestrians/CitizenGait.gd:25` e `:51`. O indicador da bancada foi detectado visível, mas a execução foi interrompida porque os erros invalidam a comparação. Performance integrada permanece pendente. Amostras e logs estão em `D:/geteco/interaction-review/` e `D:/geteco/interaction-bench-errors.log`.
