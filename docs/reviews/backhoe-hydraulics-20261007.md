# Retroescavadeira: comandos traseiros

O limite registrado no board `inv-030` foi implementado: giro, braço, antebraço e caçamba traseiros possuem comandos independentes. A pá frontal continua com PgUp/PgDn e B; o caminhão não ganhou carregamento a granel nem a guarita um interior.

Comandos traseiros: U/O, Home/End, Insert/Delete e vírgula/ponto. Só operam com o veículo parado e motorista com controle. As três peças físicas acompanham os pivôs e usam consultas varridas, subdivisão angular e limites contra cabine/chassi. O controlador não cria outro loop por frame. As poses retornam à posição de transporte quando a máquina é recriada, conforme o comportamento anterior da pá.

Godot 4.7.2 .NET, Harbor.csproj compilado sem erros/avisos, saves de teste isolados. Contratos:

- `test_backhoe_hydraulics.gd`: **29/29**, juntas independentes, preservação da pá, parede fina com delta grande, proprietário de input, motor desligado e ausência do recurso no trator.
- `test_mining_machine.gd`: **33/33**, pá, minério, carro, moto, colisão e soltura.
- `test_mining_bucket_lifecycle.gd`: **12/12**, pooling, contato, recuo e destruição. A primeira rodada falhou em quatro verificações porque a fixture usava o antigo raio de pedra. O minério atual é convexo e deixava folga. A fixture agora deriva o ponto inferior dos vértices e exige contato real antes de testar o recuo; nenhuma assertion foi removida.

Logs: `evidence/backhoe-contract-final.log`, `backhoe-front-regression.log`, `backhoe-lifecycle-regression.log` (falha preservada) e `backhoe-lifecycle-contact-final.log`.

O Main real admitiu o motorista, manteve o input da máquina ativo e registrou 2.638 frames físicos com alteração das juntas. Seis poses renderizadas foram capturadas, além de repouso e ciclo. Inspeção amostral mostra a caçamba acompanhando o braço; não é certificação temporal de toda a iluminação.

## Medição e limites

RTX 4060 Laptop / i7-13650HX, Mobile, 1280×720; duas janelas de 30 segundos após 10 segundos de aquecimento cada. VSync/limite desligados somente na amostragem; capturas posteriores com 60 FPS. Meta provisória 60 FPS e aumento superior a 5% em p95/p99 como critério de investigação.

| Cenário | Antes FPS | Depois FPS | Antes p95/p99 ms | Depois p95/p99 ms |
| --- | ---: | ---: | --- | --- |
| Motorista parado | 493,6 | 522,7 | 3,456 / 4,843 | 3,529 / 4,760 |
| Ciclo hidráulico | 452,3 | 530,1 | 3,810 / 5,404 | 3,605 / 5,430 |

Zero frames acima de 33,3/66,7 ms nas quatro amostras. **Regressão de performance inconclusiva:** fontes alheias mudaram durante as duas execuções (`DesertCarCatalog.gd` no baseline; `RauhzFocusModel.gd` no depois), e `test_sewer_session.gd` renderizado de outra sessão coincidiu com o depois. Os números não aprovam uma comparação isolada. Nenhum processo alheio foi encerrado. O custo de leitura de screenshots posterior não integra as métricas.

Relatórios completos, amostras e hashes: `evidence/backhoe-baseline-132912-6003164/report.json` e `evidence/backhoe-after-156612-7123568/report.json`. A revisão final apenas estreita o painel para sua largura anterior e acomoda as duas linhas de comandos, evitando sobreposição aos cantos do HUD; não altera a hidráulica medida.

A captura final do painel passou no Main com 239 frames físicos de movimento: `evidence/backhoe-after-61900-5902488/rear-motion-00.png` até `rear-motion-05.png`, log `evidence/backhoe-hud-final.log`. Essa rodada é revisão visual, sem nova alegação de FPS.
