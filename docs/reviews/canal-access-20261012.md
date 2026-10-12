# Investigação de acesso — Canal North e Canal Grocery

Relato: travamento após comprar/entrar na casa Canal North, ausência do cifrão e falha de acesso ao Canal Grocery.

Ambiente: Godot 4.7.2 .NET, Main renderizada, Vulkan Mobile, RTX 4060 Laptop, Harbor.csproj compilado com zero avisos/erros. Testes com `--no-save --skip-arrival`; save pessoal preservado. Outras instâncias Godot estavam abertas e não foram encerradas.

## Evidência funcional

`tests/test_canal_home_purchase_access.gd`: 30 checks, zero falhas. Cifrão visível antes da compra, compra pelo controlador real, porta fechada bloqueando o corpo, abertura por empurrão com gesto, entrada/saída e reentrada na Canal North, cápsula livre e controle restaurado. Canal Grocery prepara na aproximação, admite por caminhada e restaura controle.

Limites: aproximações iniciais usam teleporte de fixture, seguidas de caminhada física. Não reproduz a rota original do usuário, a compra pelo menu, o save original ou uma entrada durante streaming ainda pendente. Não certifica colisão/oclusão de todos os móveis nem saída/reentrada do Grocery. O travamento relatado continua sem causa demonstrada; nenhuma correção produtiva foi aplicada sem reprodução.

O cifrão representa uma casa à venda e é ocultado após comprar. A captura [da fachada atual](../../output/residence-sale-20261010/before-report-20261012-canal_north.png) mostra o indicador antes da compra.

## Performance: pendente

Janela renderizada de 30 s no exterior da Canal North: 82,08 FPS médios, p50 11,083 ms, p95 24,680 ms, p99 33,705 ms, máximo 104,666 ms; 27 frames acima de 33,3 ms e 2 acima de 66,7 ms. [Amostras](../../output/residence-sale-20261010/before-report-20261012.json). Há processos concorrentes, portanto não é comparativo isolado nem aprovação da meta de 60 FPS. Não houve mudança produtiva para comparar antes/depois.

Próxima informação necessária: distinguir congelamento da imagem/jogo de bloqueio apenas do movimento de Dante e identificar se ocorreu na rua ou já com o interior visível.
