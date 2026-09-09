# district/ — geração anterior do jogo

**Isto não é o jogo atual.** As regiões jogáveis de hoje estão em `world/`:
`world/harbor/` é o jogo principal e `world/mountain_pass/` a segunda região.

O que restou aqui é a primeira geração, alcançada por `Main.tscn` (na raiz do projeto):

| pasta | situação |
|---|---|
| `borough_one/` | carregada por `Main.tscn` |
| `coast/` | carregada por `Main.tscn` |
| `highway/` | usada por `borough_one/` e por `bairro1_v2/` |
| `bairro1/` | protótipo de bairro, sem uso no jogo vivo |
| `bairro1_v2/` | cena de avaliação isolada; o próprio código diz que nunca é carregada por `Main.tscn` |

## Por que não foi apagado

`HarborSceneRoute.for_save()` escolhe entre `world/harbor/HarborGame.tscn` e `Main.tscn`
conforme o save: saves antigos, sem a flag `harbor_campaign_active`, **ainda carregam
`Main.tscn` em runtime**. Apagar ou tornar inacessível esta árvore quebra o save de quem
já estava jogando.

Se for mexer aqui, o teste que importa é carregar um save sem essa flag e confirmar que a
rota legada ainda funciona.
