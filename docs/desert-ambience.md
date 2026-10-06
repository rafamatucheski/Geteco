# Ambientação sonora do deserto

Implementação: `audio/desert_ambience/DesertAmbience.gd`, instanciada por `audio/WorldAudio.gd`.

- Vento contínuo discreto, com intensidade suavizada e novos alvos a cada 7–19 segundos.
- Um único detalhe espacial por vez, com intervalos aleatórios de 24–52 segundos: rajadas e pássaros de dia, rajadas e chamados distantes à noite. Sem repetir consecutivamente o mesmo tipo.
- Ruídos metálicos somente a até 48 m da oficina ou do posto, emitidos na posição desses estabelecimentos.
- Interiores reduzem o vento a 12% do ganho exterior e interrompem os detalhes externos. Diálogos e telas modais também reduzem o vento e suspendem detalhes.
- Saída da região faz fade do vento e interrompe detalhes; os canais pertencem ao nó de áudio e são liberados junto dele. Seguem a pausa normal da árvore e o bus `Ambient`.
- Dois canais adicionais no máximo; atualização em 10 Hz, sem varredura de NPCs e sem síntese de áudio. Recursos existentes são carregados na primeira ativação e reutilizados.

Os grilos noturnos de `AmbienceProfile`, passos por superfície, ruído dos pneus e rádio continuam sob seus sistemas existentes. Esta mudança não adiciona música de exploração nem novos sons de passos. O catálogo utiliza as gravações existentes; os chamados noturnos reutilizam detalhes de cães distantes, sem representar uma espécie nova no mapa. Não há detecção acústica de rochas ou cobertura exterior nesta versão; o abafamento usa os interiores registrados na sessão.

## Verificação

- `dotnet build Harbor.csproj --no-restore -v quiet`: aprovado.
- Godot 4.7.2 .NET, `--headless --script res://tests/test_desert_ambience.gd`: aprovado. Cobre recursos, dia/noite, intervalos, posicionamento por contexto, interiores, diálogo, saída da região e limite de canais.
- `tests/measure/measure_desert_ambience.gd`: comparação renderizada no `Main`, com save temporário, backend C# confirmado, população real, dia/noite e entrada/saída do banco. Baseline de diagnóstico desativa o processamento e a reprodução do novo nó; não representa carregamento a frio sem o código instalado. São 10 s de estabilização e 30 s de amostras por variante. Alvo provisório: 60 FPS / 16,67 ms; aumentos de mais de 5% em p95/p99 exigem investigação, considerando variação da população viva.
- Qualidade percebida e equilíbrio final dos volumes precisam de escuta humana; testes de reprodução não certificam a qualidade audível.

### Resultado renderizado em 06/10/2026

Godot 4.7.2 .NET, Vulkan Mobile, RTX 4060 Laptop GPU, 1280×720, 24 pedestres. Comparativo sem VSync/limitador, sem outro runtime concorrente, fontes estáveis durante o lote. Entrada/saída real do banco aprovadas.

| Cenário | FPS desligado → ligado | p95 ms desligado → ligado | p99 ms desligado → ligado |
| --- | --- | --- | --- |
| Posto, dia | 213,32 → 200,64 | 8,19 → 8,48 | 10,28 → 10,62 |
| Vila, noite | 163,03 → 158,50 | 10,72 → 10,25 | 13,39 → 12,10 |

Os percentis ficaram dentro da tolerância inicial de 5%; o FPS médio caiu nas duas amostras, sem atribuição causal isolada, pois a população permanece viva. Houve 4 → 8 frames acima de 33,3 ms no posto, nenhum na vila, e nenhum acima de 66,7 ms em qualquer amostra. Máximos: 42,59 → 42,99 ms no posto; 21,23 → 17,69 ms na vila. Os percentis estão abaixo de 16,67 ms; existem picos que não foram atribuídos ao áudio. Não interpretar como garantia de ausência de hitches.

Evidência: `evidence/desert-ambience-57376-7953120/report.json`, com amostras brutas, hardware, fingerprint e capturas. O runner da fila registrou `overlap=false`, código 0. Aviso preexistente de interpolação de MultiMesh em `DesertAmbientLife.gd:76`, fora desta alteração.

A checagem com limite de 60 FPS e VSync (`--normal-cap`) concluiu a vila noturna e a entrada/saída do banco: 60,00 FPS médios, p50 16,66 ms, p95 18,66 ms, p99 19,80 ms, máximo 20,69 ms, nenhum frame acima de 33,3 ms. Fontes estáveis e nenhuma concorrência, código 0. Evidência: `evidence/desert-ambience-113380-6936459/report.json`. A média atingiu o alvo, mas o pacing com limitador não manteve todos os percentis em 16,67 ms; não há atribuição de CPU/GPU/espera para esses deltas.

A medição não valida todo o deserto, qualidade audível nem o custo de primeira visita. O resultado funcional está aprovado nos cenários descritos; o comparativo de percentis não apontou regressão acima da tolerância definida. Não é aprovação global da performance do mapa.
