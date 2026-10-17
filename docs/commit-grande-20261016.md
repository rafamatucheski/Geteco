# Commit de consolidação — 16/10/2026

Este commit junta o que estava solto na árvore de trabalho no fim de 16/10 (várias sessões e agentes), para o usuário testar com `Jogar.cmd` e depois reexportar. **Ninguém testou o conjunto**: o usuário pediu para não rodar testes e validar no jogo.

## O que NÃO entrou (continua solto no disco)
- `artifacts/` (7,4 GB de exports e medições), capturas e vídeos de `evidence/`, `isolated-maciota-after.png`, `tests/tmp_claude_roof_*` (testes temporários de outra sessão), logs e `.bak`.

## Atenção: o HEAD anterior não carregava
`gameplay/Gameplay.gd` no commit anterior tinha `func police_reload(...)` sem corpo (erro de sintaxe). A cópia desta árvore, de outra sessão, corrige isso: sem este commit o HEAD puro não abre.

## Fachadas pintadas: interruptores
Padrão LIGADO (variável `=0` desliga; `GETECO_PAINTED_FACADES=0` desliga todo o kit): delegacia, bombeiros, banco, galpão Vértice, loja Tônico (`GETECO_PAINTED_TONICO`), casas rurais (`GETECO_PAINTED_TRUCKERS_HOMES`), casa do zelador (`GETECO_PAINTED_KEEPER`), ala oeste da clínica (`GETECO_PAINTED_CLINIC`), torre cívica/CivicTower (`GETECO_PAINTED_TALL`), garagem Piston & Co (`GETECO_PAINTED_GARAGE`), os prédios do porto (lavanderia, marcenaria, mercado, frete, aquário, museu, câmara fria, lanchonete, mercearia da ilha, cinema, café).

## Riscos conhecidos para o teste
- Zelador: `test_door_push_physics` falhou 4 checks com a pintura ligada (sem comparação com ela desligada); `test_keeper_house` travou uma vez.
- Casas rurais: quatro testes da vila não rodaram com a casca ligada; a casa 3 saiu esbranquiçada.
- Tônico: `test_truckers_village_integration` falhou em "Main starts with urban operations" sem causa provada.
- Clínica: o piso do telhado de serviço fica 0,35 m acima do telhado pintado; porta, acesso e interior não foram vistos no jogo.
- Torre cívica: imagem de 16 m espremida em 10,6 m; letreiro CIVIC TOWER mas o nome no jogo é HORIZON; duas portas pintadas na frente, só uma abre.
- Sem relação com a pintura, falhas já conhecidas: `test_native_driving` (carro inicial nasce no túnel do canal: corrida na partida), `test_harbor_service_roofs` (telhado frio do banco), `test_vertice_hideout` (a grade recusa 90 balas da M4A1), `test_vehicle_twotone`.
- Desempenho: nada foi medido.

## Conteúdo por área (arquivos novos/modificados)
Resumo gerado dos arquivos no stage: som de motores (`audio/engine_design`, `audio/engine_el`, `tools/audio`), sons de veículos e ambiente (`audio/*` .import), arte de interface (`ui/art`, `ui/icons`), pesca (`activities/fishing`, `assets/fishing`), assalto no deserto (`gameplay/desert_heist`), atmosfera e chuva (`runtime/atmosphere`), materiais (`assets/materials`), regiões e prédios (`world/*`), testes e medições (`tests/*`), ferramentas (`tools/*`).
