# Água — 10/09/2026

Implementados mar com ondulações e reflexos contínuos, lagos com deslocamento mais
lento, correnteza/espuma em movimento e anéis na fonte da praça. As margens sul,
leste, norte, laterais da rodovia e península passam a receber som de mar por
proximidade; a travessia conserva sua camada regional existente.

O teste `tests/test_water_presentation.gd` carrega HarborGame, percorre as margens,
fonte e montanha carregada por streaming, entra em abrigo, verifica diálogo e volta
à cidade. Também verifica que os passos continuam produzindo marcas no lago.
As capturas foram inspecionadas com Godot 4.7.2, Forward+/Vulkan, RTX 4060 Laptop.
Não foi feita uma comparação de desempenho antes/depois.

`01_cais.png` e `02_cais_movimento.png` registram a mesma câmera em instantes
diferentes. A comparação inicial de uma área contendo somente mar encontrou
mudança acima de dois níveis de RGB em 34% dos pixels. `03_fonte.png`,
`04_lago.png` e `05_corredeira.png` mostram o recorte dos efeitos pelas estruturas.
`metrics.json` inclui análise do loop de áudio decodificado, sem saturação.

Limitações da verificação: o carregamento já acusa ações de InputMap ausentes em
`GameInput.import_bindings`; não são erros do shader nem do sistema de água.
O teste legado `test_lake_weapon_discoveries.gd` foi tentado, mas interrompido após
encontrar chamada a `_refresh_weapon_buttons`, ausente na loja atual, antes de
chegar à seção de água. Seu resultado não foi considerado aprovação.

O escopo é o mundo atual HarborGame e a montanha contínua. As cenas em `legacy/`
não foram migradas. A cachoeira congelada e os blocos de gelo continuam sólidos.

Resultado final: 23 verificações aprovadas, zero falhas. Saída resumida em `verification.txt`.
