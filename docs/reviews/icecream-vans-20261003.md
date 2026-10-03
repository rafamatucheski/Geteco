# Vans de sorvete com palhaços

Implementação: variante da `courier_van`, com dois palhaços sentados, pintura creme, faixas coloridas, balcões fechados, toldos listrados e sorvete no teto. Sem textos decorativos, novas luzes ou novas rotas.

- O primeiro courier elegível vira sorvete; os seguintes têm 25% de chance enquanto houver menos de dois exemplares vivos no tráfego ambiente. A população total continua sob o limite existente.
- A identidade `street_icecream_…` usa o `vehicle_id` já persistido. A restauração reconstrói os adereços sem novo formato de save. Pintura continua editável.
- Malhas dos palhaços e dos adereços são compartilhadas e pré-aquecidas na carga da frota. Uma superfície por malha; atualização de elegibilidade sonora a cada 0,25 s.
- Jingle original de 10,24 s, no barramento Ambient, alcance de 48 m e no máximo duas fontes ativas próximas. Distância, suspensão, invisibilidade, motor desativado e destruição interrompem o som. Sons e apresentação são filhos do veículo e seguem seu descarregamento.
- Os palhaços deixam de aparecer quando a van deixa o tráfego ou passa a ser controlada, evitando sobreposição com o jogador.
- Casco, portas, direção e regras de trânsito permanecem os da van existente. O sorvete do teto tem colisão própria.

## Verificações

Godot 4.7.2 .NET, DLL de `Harbor.csproj` compilada com `dotnet build Harbor.csproj --no-restore` (zero erros/avisos). Testes e medições com `--no-save`.

- `tests/test_icecream_van.gd`: **24 checks aprovados**, incluindo vanilla sem alteração, anexação idempotente, identidade restaurada pelo registro FleetState, duas vozes, culling/retorno, destruição, suspensão, limpeza, batching e raio físico atingindo o sorvete acima do casco original.
- `tests/test_icecream_boarding.gd`: **110 checks aprovados**, reaproveitando entrada/saída real, dois lados e orientações, distância do corpo à porta, cabeça sob teto, contato da mão e destino do embarque. Menor distância à folha: 0,34 m.
- `tests/measure/measure_icecream.gd -- --no-save --label=traffic --validate-traffic`: **aprovado na cidade real**, com roteador C# ativo. Duas vans surgiram pelo fluxo produtivo, máximo simultâneo de duas e movimento superior a 2 m registrado nas rotas existentes durante 30 s. As duas vans de apresentação criadas pelo teste não entram nessa contagem. Log: `evidence/icecream/traffic.log`.
- Inspeção renderizada: `evidence/icecream/fixture.png`, `clowns.png` e `after/van.png`; último arquivo mostra as duas vans na cidade real. Palhaços visíveis através dos vidros, adereços encaixados na carroceria.
- O teste inicial encontrou cálculo incorreto de fim do loop para WAV importado em QOA. Corrigido para contar frames de amostra, com regressão dedicada. Os 24 checks acima são posteriores à correção.

## Medição renderizada

Cena `Main.tscn`, semente 23107, dia seco, 1280×720, Mobile/Vulkan, NVIDIA RTX 4060 Laptop, configuração efetiva sem VSync/limitador. Dois couriers adicionais equivalentes nas duas variantes. Janela de 30 s após aquecimento; amostras brutas em `evidence/icecream/{baseline,after}/frames.json`.

| Medida | Base, adereços/som desligados | Variante ativa |
|---|---:|---:|
| Frames / duração | 2440 / 30,002 s | 2361 / 30,003 s |
| FPS médio | 81,33 | 78,69 |
| p50 | 13,458 ms | 13,739 ms |
| p95 | 16,570 ms | 17,169 ms |
| p99 | 19,446 ms | 20,318 ms |
| Máximo | 45,701 ms | 52,591 ms |
| Frames >33,3 / >66,7 ms | 4 / 0 | 3 / 0 |
| Veículos produtivos / pedestres ao final | 41 / 35 | 46 / 40 |

Meta provisória: 60 FPS / 16,67 ms; sinal para investigar regressão: aumento acima de 5% em p95/p99. As diferenças observadas foram +3,6%/+4,5%, mas **comparação de regressão inconclusiva**: população dinâmica diferente e outros processos Godot abertos. Não é aprovação de performance nem comprovação de 60 FPS sustentados. A medição posterior `traffic` instrumenta nascimento/movimento real, não substitui este par A/B.

## Limites

No encerramento da última execução integrada (`traffic`), após os checks aprovados, o stderr do motor reportou recursos pendentes: 5 meshes, 3 materiais, 1 shader e 16 instâncias ObjectDB. Esses avisos não aparecem no arquivo de log, que é fechado antes dessa etapa, nem ocorreram no teste isolado da variante. A causa não foi isolada; a limpeza global da cena completa permanece pendente, sem atribuição à variante ou a outro sistema.

Save foi verificado na captura/validação/reconstrução do registro; não houve gravação de partida pessoal nem ciclo completo de armazenamento em disco. Não foi feita auditoria global de cruzamentos, benchmark de chuva/noite ou avaliação auditiva humana do jingle. Renderização e testes de estado do áudio não certificam sua qualidade subjetiva. Os primeiros testes da cidade encontraram dependências ausentes de trabalho concorrente no supermercado; elas apareceram antes das medições válidas acima, sem alterações desta tarefa nesses sistemas.
