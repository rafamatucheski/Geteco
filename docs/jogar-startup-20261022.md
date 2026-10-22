# Fechamento ao abrir pelo Jogar.cmd — 22/10/2026

O C# compilava, mas o release encerrava na abertura com `0xc0000005`
(`-1073741819`). O problema também ocorria em headless e com uma pasta
de usuário vazia. Os saves do jogador foram preservados.

`MainMenu.gd` já não declarava `btn_rachas`, mas
`SunsetMenuPresentation.install()` ainda acessava essa propriedade. O teste
`test_orphan_save_slots.gd` revelou o acesso inválido na linha 64.
A referência obsoleta foi removida da lista de botões da apresentação.

O novo export manteve Godot 4.7.2 .NET, release, Forward+ e
`script_export_mode=2`. A abertura que antes falhava passou a sair com código 0:

- Headless: `--headless --quit-after 3`.
- Renderizado: `--quit-after 180`, Vulkan, NVIDIA RTX 4060 Laptop GPU.
- Regressão do menu: 24 verificações, zero falhas e nenhum erro de script.
- Compilação `Harbor.csproj`: zero erros e zero avisos.
- Suíte central: nove testes passaram na execução inicial; o único erro foi
  o acesso a `btn_rachas` descrito acima. Após a correção, esse teste passou
  isoladamente. O resumo original da suíte conserva a falha encontrada em
  `evidence/test-suite/core/20261022-184519/RESUMO.md`.

Logs locais em `builds/launcher-fixed-headless.log`,
`builds/launcher-fixed-rendered-output.log` e
`builds/launcher-menu-regression.log`. O pacote validado foi copiado para
`builds/jogar`, utilizado pelo lançador.

`PlayRelease.ps1` agora espera o jogo terminar, verifica seu código de saída e
gera `builds/jogar-session.log`. Uma falha propaga um erro ao CMD, que mantém
o diagnóstico visível com `pause`. Os ramos de saída normal e de falha do
lançador foram conferidos com processos simulados; a inicialização real foi
conferida no executável exportado.

## Ajuste exigido pelo hook de commit

O hook recusou as duas chamadas novas de `SurfaceTool.append_from` em
`ResidentialTreeVisual.gd`. A mesma geometria agora está pronta em
`assets/urban_detail/residential_tree.res`; a receita ficou em
`tools/mesh_bake/bake_residential_tree.gd`. O bake renderizado verificou igualdade
exata das arrays de todas as superfícies e do AABB após salvar e recarregar.
`test_residential_finish.gd` passou renderizado, incluindo interações, sólidos,
superfícies da árvore e colisão do tronco. O hook passou após o ajuste.

Comparativo finito na mesma máquina e no mesmo dia: release, rota `sobrados`,
Forward+, Vulkan, RTX 4060 Laptop, preset Média, 1280×720, VSync e teto de FPS
desligados pelo runner, população padrão, meio-dia seco, despacho desligado,
30 segundos desde o primeiro quadro jogável (`--benchmark-cold`).

| Métrica | Montagem original | Asset pronto |
|---|---:|---:|
| Quadros | 5316 | 8759 |
| FPS médio | 177,20 | 291,96 |
| p50 / p95 / p99 (ms) | 4,85 / 9,91 / 13,07 | 3,04 / 6,83 / 8,78 |
| Máximo (ms) | 44,35 | 31,07 |
| Quadros > 33 / 66,7 / 100 ms | 5 / 0 / 0 | 0 / 0 / 0 |

Nenhuma regressão apareceu nessa amostra. Uma rodada por variante não permite
atribuir todo o ganho à árvore nem certificar outras rotas ou condições.
O limite de 33 ms já era excedido na base. Ambas as rodadas registraram o aviso
preexistente do editor de mundo sobre `path/mountain_zoo_walk`, fora desta correção.
JSONs completos em `%APPDATA%/GetecoV2/benchmark-west/`, prefixos
`launcher_tree_before_20261022_sobrados_1` e
`launcher_tree_after_20261022_sobrados_1`; logs em `builds/launcher-tree-*-bench.log`.

O pacote final com o asset pronto, também executado no comparativo renderizado,
foi copiado para `builds/jogar`. Esta validação não certifica integralmente as
outras alterações consolidadas no mesmo commit.
