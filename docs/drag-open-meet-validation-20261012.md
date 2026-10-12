# Arrancada livre — 12/10/2026

Implementação: seis visitantes entram pelo acesso fora da visão do jogador,
aguardam fisicamente, correm, freiam e usam a via de retorno para voltar à fila.
Os mesmos veículos são reutilizados; não se recria um adversário em cada bateria.
O quadro oferece próxima largada ou segunda posição, com apenas uma bateria
adicional à frente. Corridas livres não alteram dinheiro nem ranking.
Inscrição #27 e números dos visitantes são aplicados sobre a geometria real do
vidro traseiro. A frenagem progressiva só dispara áudio de derrapagem quando há
deslizamento, preservando motor e rodagem.

## Validação

- Godot 4.7.2 .NET; Harbor.csproj compilado; rotas C# ativas; saves isolados.
- `output/open-drag-night2.log`: 31 verificações, zero falhas. Espera da segunda
  posição: 71,034 s. Entrada pelo quadro, corrida completa com movimento real,
  ausência de recompensa/ranking, retorno do mesmo adversário, cancelamento e
  limpeza. Frenagem normal sem loop de derrapagem.
- `output/open-drag-ranked-regression.log`: 75 verificações, zero falhas.
- `evidence/open-drag-44104-7133910/temporal/sequence.json`: sequência noturna
  de 31,02 s, 920 quadros; áudio real em `../braking.wav`.
- Ajuste final dos números inspecionado em
  `evidence/desert-car-fit-81872-9072968/`: Mirage, Faísca e Siroco mostram #27
  na superfície traseira, sem billboard nem desenho através da carroceria.
  Captura reproduzível: `tests/capture/capture_drag_numbers.gd`.

## Desempenho

RTX 4060 Laptop, Vulkan Forward Mobile, cena Main renderizada, mesma câmera e
horário. Comparativo finito de 30 s sem visitantes versus com seis visitantes,
após aquecimento. A geometria da via de retorno existe nas duas variantes.
Não representa comparação com uma revisão limpa anterior do repositório.

`evidence/open-drag-61492-7175328/metrics.json` contém amostras, configuração,
p50/p95/p99, máximo e contagens acima de 33,3/66,7 ms:

| Variante | FPS médio | p95 | p99 |
|---|---:|---:|---:|
| Sem visitantes | 144,01 | 9,002 ms | 9,261 ms |
| Com visitantes | 143,82 | 9,917 ms | 10,374 ms |

O alvo absoluto provisório de 16,67 ms foi atendido nessa amostra, mas o aumento
de cauda excedeu 5%. Performance não certificada: a confirmação deve distinguir
custo da circulação de variação/carga de outras sessões no workspace.

Confirmação finita em `evidence/open-drag-70604-7610696/metrics.json`:
143,68 → 143,60 FPS; p95 10,411 → 9,818 ms; p99 11,269 → 10,388 ms.
O aumento anterior não se repetiu, mas houve outro processo Godot transitório
na máquina durante a janela; comparação de cauda permanece inconclusiva.
Após as medições, a captura de número encontrou uma superfície sem índices
no carro com interior: corrigido o tratamento de índice nulo. Isso ocorreu
depois das duas amostras, não durante a medição da circulação.

Revalidação integrada do número após a correção:
`output/open-drag-final-number.log`, seis verificações e zero falhas, sem erro
de script. Captura real inspecionada:
`evidence/open-drag-104984-9433333/rear-window-number.png`.
