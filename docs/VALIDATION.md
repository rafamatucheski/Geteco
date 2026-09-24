# Geteco V2 — validação do primeiro trecho

21/09/2026, Godot 4.7.2, RTX 4060 Laptop, Vulkan Mobile, 1280×720, MSAA 2×, VSync e limite de 60 FPS. Estes resultados são da base urbana pequena e da garagem, não uma certificação da campanha inteira.

## Funcional e físico

- `test_progression.gd`: 90 verificações aprovadas; ordem, repetição, inventário, save versionado, backup, corrupção, números JSON e restrição de armas derivada da localização.
- `test_maciota_world.gd`: aprovado; cápsula inteira no spawn, aproximações e saída; varreduras contra parede/mesa; passagem do escritório; residentes fora dos móveis e sem métodos de dano/morte.
- `test_v2_session.gd`: aprovado; interações por proximidade, entrada/saída, câmera, ordem da tarefa, coleta única, conclusão idempotente, destino ocupado recusado, save e restauração física do checkpoint/câmera/missão/restrição.
- `test_v2_walk.gd`: aprovado; Dante caminha continuamente da entrada ao escritório, ao mecânico e à peça, com colisões reais e sem teletransportes intermediários.
- Regressões do protótipo em `--sandbox`: direção/entrada/saída/colisão/tráfego/percurso **46 verificações**, controles/reinício **15**, sem falhas.
- Teste obrigatório V1 `tests/test_garage_weapon_restrictions.gd`: **0 falhas**, saída 0. Emite avisos de recursos/RIDs não liberados no encerramento do jogo antigo; não é execução limpa de recursos. Nenhum código V1 foi alterado para mascarar esses avisos.

Ainda não existe combate V2. O teste do bloqueio cobre o contrato de estado; armas futuras precisam consumi-lo. Os moradores essenciais não possuem entrada de dano/morte.

## Visual e profundidade

Capturas reais em `evidence/v2-exterior.png`, `v2-interior-entry.png`, `v2-dialogue.png`, `v2-mechanic-part.png`. Fachada usa apenas MACIOTA; indicador compacto de acesso sem letra sobreposta. Escala comparada a Dante. Câmera alinhada e fixa no interior. Corte de paredes/viga preserva volume físico. Removidos visual do pátio externo herdado e linhas remanescentes fora da planta.

`depth_v2.gd` aprovado: controla cena sem personagem e cena sem mesa, verificando cápsula livre nos pontos fotografados. Razão de pixels visíveis com/sem mesa: **atrás 0,848; frente 0,999; ao lado 1,021**. Pequena variação de antialiasing/iluminação é esperada. A sombra do personagem é desligada somente nesse teste para não contaminar a contagem de sua silhueta. Arquivo: `evidence/v2-depth.json`.

O primeiro ponto de controle de profundidade coincidiu com a poltrona; o harness foi corrigido para pontos fisicamente livres. Não se alterou a colisão da mesa para fazer o teste passar.

## Desempenho renderizado

Cada execução registra inventário de processos durante a amostra; sem outro jogo em execução, editor V1 aberto. Cinco segundos de aquecimento separados e 30 segundos medidos por relógio real. Testes headless não entram nestes resultados.

| Cenário | FPS | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Base antes, 24 pedestres | 60,002 | 16,664 | 17,124 | 17,952 | 19,424 | 0 / 0 |
| V2 integrada, mesma rota exterior e 24 pedestres | 60,002 | 16,665 | 17,288 | 18,001 | 22,684 | 0 / 0 |
| V2 final, caminhada no interior | 60,003 | 16,662 | 17,506 | 18,647 | 22,409 | 0 / 0 |
| V2 final, dirigindo com 96 pedestres | 60,007 | 16,663 | 17,678 | 18,852 | 22,228 | 0 / 0 |

Arquivos `evidence/v2-before-isolated-population24.*`, `v2-after-isolated-population24.*`, `v2-interior-final-isolated-population24.*`, incluindo amostras por frame e monitor `*-processes.json`.

Sem perda de FPS ou quadros acima de 33,3 ms no comparativo exterior; variação de p95 de 0,164 ms não demonstra capacidade para cidade maior. O interior novo estabelece sua própria referência: não existe comparação equivalente V1/V2 desta sala. Dante percorreu **52,50 m** no interior final; máximo de aquecimento **18,923 ms**. Inicialização global do processo/importação não está incluída no intervalo de gameplay.

A primeira amostra `v2-interior-isolated-population24` ficou com movimento bloqueado pela parede porque a rota de medição cortava diagonalmente o acesso do escritório. Foi preservada e substituída pela amostra final com rota pelo vão real. Não é apresentada como benchmark de caminhada.

Esforço final: 96 pedestres, seis carros de tráfego, carro do jogador percorrendo **191,11 m**. Evidências `v2-driving-final-isolated-population96.*`. Aquecimento exterior: máximo **40,586 ms antes / 62,137 ms depois**; dirigindo com 96 pessoas: **74,296 ms**, um quadro acima de 66,7 ms. Esses picos permanecem registrados; não se certifica ausência de engasgos iniciais. Não houve repetição suficiente para atribuir a variação a um componente específico. As amostras estáveis não incluem esses cinco segundos iniciais.

## Escopo concluído

1 lugar V2 / 1 interior distinto: garagem Maciota, com o trecho curto funcional, físico e visual validado. Não equivale a migrar a missão completa, converter saves V1 ou certificar todos os interiores. Próximas etapas e critérios estão em `MIGRATION.md`.
