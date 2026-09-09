# legacy/district/ — bairros da geração anterior

**Isto não é o jogo atual.** As regiões jogáveis de hoje estão em `world/`:
`world/harbor/` é o jogo principal e `world/mountain_pass/` a segunda região.
Ver [../README.md](../README.md) para o contexto de `legacy/`.

O que está aqui é a primeira geração, alcançada por `legacy/Main.tscn`:

| pasta | situação |
|---|---|
| `borough_one/` | carregada por `legacy/Main.tscn` |
| `coast/` | carregada por `legacy/Main.tscn` |
| `highway/` | usada por `borough_one/` e por `bairro1_v2/` |
| `bairro1/` | protótipo de bairro, sem uso no jogo vivo |
| `bairro1_v2/` | cena de avaliação isolada; o próprio código diz que nunca é carregada por `legacy/Main.tscn` |

## Por que não foi apagado

`HarborSceneRoute.for_save()` escolhe entre `world/harbor/HarborGame.tscn` e `Main.tscn`
conforme o save: saves antigos, sem a flag `harbor_campaign_active`, **ainda carregam
`legacy/Main.tscn` em runtime**. Apagar ou tornar inacessível esta árvore quebra o save de quem
já estava jogando.

Se for mexer aqui, rode `tests/test_legacy_save_route.gd`: ele carrega a cena legada de
verdade e confirma que a rota de save antigo continua funcionando.
