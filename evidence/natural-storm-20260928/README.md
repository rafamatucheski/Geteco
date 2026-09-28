# Tempestade natural — 28/09/2026

Mudança: 8% de tempestade por sorteio (42% limpo, 28% nublado, 22% garoa),
mantendo intervalos de 90–180 s. Céu/horizonte escurecidos apenas na tempestade
exterior de Harbor, com mistura regional. Sem novas luzes ou emissores.

Risco: tempestades passam a ativar naturalmente as 600 gotas e clarões já
existentes. Alvo provisório: 60 FPS / 16,67 ms na RTX 4060 Laptop, Mobile.
Comparação: cena Main renderizada, mesma câmera e população, dia e noite,
8 s de aquecimento e 30 s de amostra por variante. Aumento de p95/p99 acima
de 5% exige confirmação. Editor e jogo do usuário permanecem abertos.

`before/` e `after/` são ensaios INVÁLIDOS: o runner antigo carregou um save
na garagem. Não usar suas métricas para aprovar performance.
`paired/` usa `--no-save --skip-arrival --benchmark --ab-weather` e compara
uma cópia do código anterior com a implementação atual no mesmo processo.
`Weather.before.gd` foi reconstruído retirando apenas as alterações desta tarefa.

## Resultado e pendências

Comparativo renderizado, FPS médio / p95 ms / p99 ms:

| Cenário | Antes | Depois |
| --- | --- | --- |
| Dia | 36,31 / 105,31 / 167,75 | 16,13 / 162,04 / 189,91 |
| Noite | 18,72 / 100,09 / 166,43 | 31,70 / 65,26 / 102,42 |

Performance **não aprovada**: orçamento já descumprido na base; variação elevada
e piora diurna exigem confirmação. Outros processos renderizados estavam abertos;
não há evidência suficiente para atribuir a variação ao ajuste de cores/luz.
A confirmação de ordem invertida foi interrompida por erro de compilação
concorrente em `gameplay/urban_v1/VerticeCompany.gd:175` (inferência de `paint`).
O teste funcional de clima também encontrou esse erro nas dependências da cena.
Não corrigimos nem sobrescrevemos o arquivo de outra sessão.

Captura diurna após mudança inspecionada: chuva e rua legíveis. Comparativo noturno
capturado em `paired/`. Validação funcional integral e confirmação de performance
permanecem pendentes até a cena voltar a compilar e haver medição sem interferência.

O teste funcional chegou ao fim: 1.035 verificações, uma falha de impactos de
granizo na colisão real de Mountain, além dos erros de compilação/PortLogistics.
As verificações do sorteio natural, céu mais escuro, chuva, trovão e abrigo
passaram nessa execução degradada; isso não aprova a integração completa.
