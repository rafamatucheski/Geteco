# Migração dos interiores para dentro dos prédios — V1

Inventário de 22/09/2026. A contagem usa **salas distintas acessíveis**, não o número de portas. Duas filiais que compartilham uma sala contam uma vez; três acessos ao mesmo abrigo também. Este plano cobre o porto e a serra da campanha V1, sem somar as salas do projeto separado `geteco_v2`.

**Inventário inicial: 29 interiores acessíveis**, dos quais 2 Ammu-Nation já eram físicos e 27 usavam salas isoladas. **Estado de aprovação: 29 concluídos** (15 na serra e 14 no porto). O avião da serra já é uma área externa física, e a oficina Northgate Auto permanece fora da migração por decisão anterior do usuário. O necrotério existe no código, mas não tem entrada conectada; não é contado. Caudas transitórias de frame time em Fire, garagem do chefe e Quayside permanecem registradas no checklist; as amostras aquecidas não reproduziram regressão persistente.

## Porto — 14 interiores concluídos

| Interior | Acesso atual | Etapa | Estado |
| --- | --- | --- | --- |
| Ammu-Nation | Duas fachadas, sala compartilhada | Concluída | Porta por proximidade, caminhada contínua, teto e zoom |
| Fuel, loja de conveniência | NorthFrontage4 | 1 | Concluída: 38/38 checks, save, oclusão e comparação de FPS |
| Union, loja de roupas | Fachada Union | 1 | Concluída: passagem, compra, recompensa, save, colisão/oclusão e FPS renderizado |
| Banco de North Pier | Fachada do banco | 3 | Concluído: porta física, roubo e recompensa preservados; colisão/oclusão, save e FPS renderizado |
| Garagem do Maciota | Oficina do Maciota | 3 | Concluída: acesso físico, restrição de armas/invulnerabilidade, Monaliza sob teto sem vazamento de sprite/sombra, embarque, save, profundidade e p95 interno 24,691 → 18,727 ms |
| Delegacia Harbor Patrol | Fachada da delegacia | 3 | Concluída: entrada física, atendimento, save, colisão/oclusão e p95 interno 17,753 → 17,464 ms |
| Hospital Bay Medical | Fachada do hospital | 3 | Concluído: entrada física, cura, ala da ambulância, save, colisão/oclusão e p95 interno 17,596 → 17,769 ms |
| Quartel Northgate Fire | Três portas, uma sala | 3 | Concluído com ressalva de cauda transitória nas primeiras amostras: três acessos/caminhões, save, profundidade e medição aquecida 60,063 FPS, p95 17,722 ms, 0 quadros >33,3 ms |
| Garagem do chefe | Acesso da garagem | 3 | Concluída com ressalva de cauda transitória: roubo, guardas, Neco, save e colisão aprovados; amostra aquecida 60,061 FPS, p95/p99 17,674/17,961 ms, 0 quadros >33,3 ms |
| Casa do coveiro | Acesso no cemitério | 2 | Concluída: caminhada, recompensa, save 6/6, oclusão renderizada e p95 interno 18,849 → 17,620 ms |
| Residência Westgate Garden | Porta da residência | 2 | Concluída: compra, caminhada, estações, recompensa, save, oclusão e p95 interno 17,608 → 17,790 ms |
| Residência Quayside | Porta da residência | 2 | Concluída com ressalva de cauda intermitente: compra/save/oclusão; controles normais p95 17,908–18,281 ms contra histórico 18,174 ms |
| Residência Canal North | Porta da residência | 2 | Concluída: compra, caminhada, save físico/legado, oclusão e p95 interno histórico 18,184 → 17,987 ms |
| Esgoto | Bueiro transitável | 3 | Concluído: descida e retorno automáticos no mesmo XY, combate isolado, save, colisão e oclusão de jogador/NPC renderizadas, FPS comparado |

## Serra — 15 interiores, 13 migrados nesta etapa

| Interior | Acesso atual | Etapa | Estado |
| --- | --- | --- | --- |
| Ammu-Nation | Fachada da loja | Concluída | Porta por proximidade, caminhada contínua, teto e zoom |
| Boutique Alpina | Loja do resort | 1 | Concluída: 59/59 checks, oclusão e FPS confirmados |
| Último Abrigo | Loja de roupa térmica | 1 | Concluída: caminhada, compra, oclusão, save/reload 7/7; p95 interno 16,912 → 16,981 ms |
| Casacos da Vila | Loja da vila | 1 | Concluída: caminhada, compra, oclusão e save físico; p95 interno 16,921 → 17,037 ms |
| Chalé Pinhais | Porta do chalé | 2 | Concluído: caminhada, recompensa, oclusão e reload em disco; p95 histórico 16,967 → 16,972 ms |
| Chalé Encosta | Porta do chalé | 2 | Concluído: caminhada, recompensa e oclusão; p95 histórico 16,978 → 16,952 ms; mesmo fluxo de save do Pinhais |
| Chalé do Posto Florestal | Porta do chalé | 2 | Concluído: caminhada, recompensa e oclusão; p95 histórico 16,974 → 16,947 ms; mesmo fluxo de save do Pinhais |
| Chalé Vila 01 | Porta do chalé | 2 | Concluído: caminhada, recompensa e oclusão; p95 histórico 17,012 → 16,931 ms; mesmo fluxo de save do Pinhais |
| Chalé Vila 02 | Porta do chalé | 2 | Concluído: caminhada, recompensa e oclusão; p95 histórico 17,036 → 17,011 ms; mesmo fluxo de save do Pinhais |
| Chalé Vila 03 | Porta do chalé | 2 | Concluído: caminhada, recompensa e oclusão; p95 histórico 16,912 → 16,983 ms; mesmo fluxo de save do Pinhais |
| Chalé Vila 04 | Porta do chalé | 2 | Concluído: caminhada, recompensa e oclusão; p95 histórico 16,931 → 16,971 ms; mesmo fluxo de save do Pinhais |
| Abrigo dos lenhadores | Três fachadas, três salas físicas; um ID e recompensa | 2 | Concluído: três acessos, machado único, oclusão/save; p95 interno 16,904 → 17,019 ms |
| Refúgio Cume Branco | Portas frontal e da pista | 3 | Concluído: duas saídas, aluguel, ski, oclusão/save; p95 interno 16,902 → 16,912 ms |
| Estação Zero | Acesso do bunker | 3 | Concluída: recompensa/missão, oclusão/save; p95 interno 16,929 → 17,052 ms |
| Caverna da Queda | Boca da caverna | 3 | Concluída: diário e RPG, oclusão/save; p95 interno 16,897 → 16,882 ms |

## Ordem de execução

1. **Lojas (5):** Fuel e Boutique Alpina como pilotos paralelos; depois Union, Último Abrigo e Casacos da Vila. Adequar planta, balcões, estoque, vendedor e pontos de interação à área real de cada fachada.
2. **Casas e abrigos (12):** três residências e casa do coveiro no porto; sete chalés e abrigo compartilhado na serra. Preservar ocupantes, recompensas e persistência por lugar.
3. **Serviços, missões e áreas especiais (10):** banco, duas garagens, delegacia, hospital, bombeiros, esgoto, lodge, bunker e caverna. Tratar separadamente portas múltiplas, circulação de veículos, missões e saídas especiais.

Os pontos de integração atuais ficam em `world/harbor/interiors/HarborInteriorManager.gd` e `world/harbor/HarborGame.gd` para o porto, `world/harbor/HarborRobberies.gd` para Fuel/banco, `world/harbor/HarborClothingShops.gd` para Union e `world/harbor/residences/ResidenceManager.gd` para as casas. Na serra, o registro, as portas e o save passam por `world/mountain_pass/MountainInteriorManager.gd`, `world/mountain_pass/MountainPass.gd` e `systems/RegionTravel.gd`; as roupas compartilham `world/harbor/interiors/ClothingRoomStandard.gd`. Alterações nessa sala compartilhada precisam selecionar explicitamente a variante para não mover outras lojas por acidente.

## Contrato de cada migração

- Levantar a pegada física do prédio e medir a sala antes de mover conteúdo. Reorganizar mobiliário e interações dentro dos limites, com passagem real para o jogador e NPCs.
- Porta abre ao aproximar; o jogador atravessa caminhando, sem teleporte, ação E, retângulo laranja ou aviso flutuante de entrada. Remover a cobertura durante a presença, aproximar a câmera e restaurar ambos ao sair. Manter E nas ações funcionais que ainda o exigem, como compra ou diálogo, sem mensagem flutuante redundante de compra.
- Verificar entrada e saída por todas as portas, reentrada, save carregado dentro/fora, interações existentes (catálogo onde houver, missão e recompensa) e retorno à fachada correta. Desligar renderização e trabalho desnecessário quando a sala fica vazia.
- Conferir colisão e profundidade separadamente em piso, paredes, porta e móveis, com jogador e NPCs; nenhuma passagem deve nascer sobre sólidos ou desenhar o ator à frente de mobiliário que o encobre.
- Fotografar exterior e interior reais antes/depois, registrar checks no [checklist](interior-standard-checklist.md) e medir frame time renderizado em cena real por 30 s antes/depois, nas mesmas condições e sem sessões concorrentes. Headless sozinho não aprova visual ou FPS.

As regras de acesso acima aplicam o fluxo contínuo solicitado para esta migração. Para interiores que continuem em cena separada, vale o indicador e a ação de entrada descritos no [padrão geral](interior-standard.md). Nenhuma linha pendente é considerada concluída sem validação física, visual e de desempenho.
