# Missões secundárias do deserto — 06/10/2026

Escopo: Peças na estrada (Bia → Raul → Bia, R$ 1.200) e O último ramal (Raul → estação → vagão → Raul, R$ 2.200). Novas interações, acompanhamento no HUD, etapas persistidas e pagamento único. Sem alteração de geometria, luzes, população, campanha principal ou condição da ponte. Falas legendadas; gravações de voz ainda ausentes.

## Evidência funcional

- `dotnet build Harbor.csproj --no-restore`: compilação aprovada, zero avisos/erros.
- `tests/test_desert_contracts.gd`: 39 checks aprovados, incluindo JSON em cada etapa, ordenação, repetição, carteira cheia, recibos incompatíveis, tarefas paralelas e contrato completo de GameState.
- Primeira execução renderizada de `tests/test_desert_contracts_session.gd`: menus, sete etapas, salvamento real e recarga fria funcionaram. Um check de saldo falhou porque a conquista existente `first_grand` paga R$ 50 ao ultrapassar R$ 1.000. O save mostrou recibos corretos de R$ 1.200 + R$ 2.200 + R$ 50, total R$ 3.450; não houve pagamento duplicado. Expectativa corrigida para conferir os três recibos separadamente.
- Evidência dessa execução: `evidence/desert-contract-session-64788-4847742/`; capturas de menus e diálogos reais. O teste usa checkpoints isolados e reposicionamento entre destinos; não comprova as rotas rodoviárias completas.
- Execução final renderizada: **68 checks, zero falhas**, evidência `evidence/desert-contract-session-100932-5057589/`. Inclui aproximação final a pé nos sete objetivos, posições apoiadas/livres, menus reais, controles recuperados, bloqueio por pausa/input com controle positivo, disco validado em cada etapa, recarga fria da investigação e recibos separados da conquista. A recarga usou o backend C# compilado; nenhum save pessoal foi sobrescrito.
- Regressões: `tests/test_full_save.gd` **PASS**, `tests/test_desert_save_and_garage.gd` **32 checks, zero falhas**. Build e testes executados com a instalação .NET especificada pelo projeto.

## Performance localizada

Main real, Godot 4.7.2 .NET, Mobile/Vulkan, RTX 4060 Laptop, 1920×1080, 28 pessoas e 12 veículos. Mesma fixture no Miragem, seed, horário e configuração; 5 s de aquecimento após streaming e 30 s de intervalos reais por captura, sem benchmarks simultâneos. Limite de FPS efetivo 0; modo VSync registrado nos JSON. Meta provisória 16,67 ms, sinal de regressão definido em >5% de p95/p99.

| Medida | Antes | Depois |
|---|---:|---:|
| FPS frames/tempo | 446,21 | 441,44 |
| p50 ms | 1,928 | 1,941 |
| p95 ms | 4,159 | 4,289 |
| p99 ms | 5,239 | 5,230 |
| máximo ms | 67,683 | 68,745 |
| frames >33,3 / >66,7 ms | 1 / 1 | 1 / 1 |

Arquivos brutos: `evidence/desert-contracts-before-181628-5181231/report.json` e `evidence/desert-contracts-after-179716-4891993/report.json`. P95 +3,13%; p99 -0,17%. Sem sinal acima do limiar nesse cenário. A proteção posterior contra ação vazia não altera o caminho medido em repouso.

Não é certificação global do mapa: primeira visita, condução entre destinos, configuração limitada a 60 FPS e todos os outros cenários não foram medidos neste comparativo. Picos de primeira visita continuam visíveis nas execuções funcionais e não foram atribuídos às missões; o histórico de performance pendente do mapa permanece válido. Não foram adicionados processos por frame, NPCs, modelos ou fontes de luz.
