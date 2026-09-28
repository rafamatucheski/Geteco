# NPCs e funeral do cemitério — 27/09/2026

## Comportamento entregue

- Os atores exclusivos do cemitério recebem dano pela API nativa, morrem, caem e entram no atendimento de emergência. Não foi adicionada API de dano aos personagens da garagem.
- Disparos, explosões e agressões interrompem a cerimônia. Sobreviventes fogem; o corpo original permanece registrado no necrotério quando o enterro não terminou.
- Mortes dos moradores e participantes são persistidas no ledger do cemitério. Reentrada e restauração não recriam as mesmas vítimas. A morte do agente deixa aquele serviço interrompido, sem um ciclo de recriação do funcionário.
- Chegadas aguardam a área do portão fora da câmera. A saída aguarda os sobreviventes concluírem o percurso e ficarem fora da câmera. Cadáveres não são apagados pelo encerramento normal do cortejo enquanto a área está ativa.
- Visitantes têm aparência variada, partida escalonada e olham para a sepultura. O zelador usa a faixa oposta no retorno; os visitantes aguardam fora da faixa de passagem; o agente retorna à traseira do carro.
- Saves anteriores sem `deaths` continuam aceitos. O contrato está em `gameplay/urban_v1/PERSISTENCE_CONTRACT.md`.

## Validação funcional

- `tests/test_cemetery_routes.gd --no-save`: PASS, quatro percursos completos nos lotes 0, 1, 2 e 11, com a geometria real e os atores reais; nenhuma alteração manual de índice ou teletransporte dos participantes. Fixture física isolada, tempo de simulação 3x. Não certifica FPS.
- `tests/test_cemetery_npcs.gd --no-save --skip-arrival --population=8`: PASS na versão final integrada em `Main.tscn`. Dois lotes, chegada/saída físicas, controle positivo de visibilidade, raio atingindo a cápsula, dano e morte via Gameplay, explosão real, interrupção, JSON/restore, reentrada e validação do ledger.
- Execução renderizada do teste integrado durante a implementação: PASS; capturas `cemetery-npcs-ceremony-0928.png` e `cemetery-npcs-interrupted-0928.png`. As capturas antecedem os últimos refinamentos de circulação nos demais lotes.
- `tests/test_urban_operations.gd`: PASS após integrar dano/persistência e adequar o teste para aguardar também os visitantes.
- `tests/test_urban_snapshot_persistence.gd`: PASS, 14 verificações, armazenamento em pasta temporária exclusiva; nenhum save pessoal utilizado.
- Garagem: `test_garage_driver_restore` e `test_garage_rewards` passaram. `test_garage_vehicle_transfer` falhou em `Original Ironback admits with native hull`, antes de testar a transferência. Essa verificação permanece pendente; não foi alterado o código da garagem para contornar a falha.
- Algumas execuções emitiram avisos de liberação de ObjectDB/resources ou RID/texturas ao encerrar o Godot. Não são apresentados como uma validação limpa de teardown.

## Desempenho

Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop GPU, 1280×720, 24 pedestres solicitados, VSync desligado e limite efetivo de 144 FPS. `Main.tscn`, cemitério, horário .32, clima 0, câmera 32; 5 s de aquecimento e 30 s de amostras reais entre frames. Alvo provisório: 60 FPS / 16,67 ms; sinal para investigar regressão: aumento superior a 5% em p95/p99.

| Amostra | FPS | p50 ms | p95 ms | p99 ms | máximo ms | frames >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes, sem funeral | 29,74 | 33,386 | 38,019 | 52,027 | 66,530 | 464 / 0 |
| Depois, sem funeral | 29,66 | 33,423 | 38,354 | 49,068 | 65,677 | 479 / 0 |
| Depois, funeral ativo | 29,87 | 33,346 | 36,161 | 46,378 | 59,586 | 471 / 0 |

**Performance não aprovada.** As amostras ficaram abaixo de 60 FPS. Outras instâncias do Godot estavam abertas, o repositório foi alterado por sessões concorrentes e o número de veículos mudou de 18 para 25. Portanto os números não estabelecem uma comparação causal isolada da alteração do cemitério. Os JSONs preservam intervalos individuais, aquecimento, CPU, física, resolução e configuração.

Arquivos: `cemetery-npcs-before-0928.json`, `cemetery-npcs-after-0928.json` e `cemetery-npcs-funeral-0928.json`. As duas medições finais rodaram sequencialmente, sem outro teste desta tarefa em paralelo. A imagem `cemetery-npcs-funeral-0928.png` corresponde à versão final. Não há baseline anterior com funeral ativo.

## Trabalho concorrente

A correção externa da posição do zelador na casa foi preservada. Com autorização explícita do usuário foram acrescentadas somente as anotações `z: float` em `UrbanFootbridge3D.gd` e `key: int` / `start: int` em `FootbridgeCrossers.gd` para destravar compilação. A anotação de `offset: Vector2` em `HarborRoadGeometry3D.gd` foi feita pela outra sessão antes da aplicação local. Nenhuma alteração local foi descartada.
