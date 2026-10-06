# Pacote da montanha: código preparado, integração pendente

Três subagentes escreveram as duas investigações, a descida noturna contra seis NPCs e a trilha de jipe em arquivos exclusivos. O agente principal preparou o agregador, a validação conjunta do save e um patch de integração. Nenhum arquivo de gameplay compartilhado foi alterado por esta entrega.

O outro chat estava corrigindo Jessica, chegada e streaming e alternando os testes com geração de voz. Para preservar seu trabalho e o uso do PC, esta entrega não iniciou Godot, compilação .NET, renderização ou geração de áudio. O código novo ainda não está habilitado na sessão do jogo.

## Conteúdo e responsabilidade

| Parte | Arquivos novos | Comportamento preparado |
| --- | --- | --- |
| Investigações | `activities/mountain_story/`, `systems/campaign/MountainStoryProgress.gd`, `data/campaign/mountain-story-dialogue.json` | Carga dos Cobras no avião; abrigo e anotação de Vicente na caverna. Quatro descobertas, duas side quests, recibos próprios. |
| Descida | `activities/mountain_downhill/`, `systems/campaign/MountainDownhillProgress.gd` | Dante e seis NPCs físicos, 20h–5h, checkpoints, classificação, cancelamento e prêmio único de R$ 2.400. |
| Jipe | `activities/mountain_jeep/`, `world/mountain_jeep/`, `systems/campaign/MountainJeepProgress.gd` | Trilha de aproximadamente 300 m, duas cristas suaves, checkpoints, jipe fornecido persistente e prêmio único de R$ 700. |
| Sessão e save | `runtime/MountainActivities.gd`, `systems/campaign/MountainPackState.gd` | Diário, objetivo, interação, exclusividade, cancelamento e validação conjunta dos recibos. |
| Preparação | `tools/mountain_pack/` | Geração de patch e prévias sem escrita nos fontes compartilhados; checagem leve de sintaxe, referências e hashes. |

As investigações não mudam os objetivos de Harbor, a arma e o dinheiro do avião, os colecionáveis do esqui ou a condição da ponte. A regra permanente continua sendo liberar a ponte para o mapa 2 somente após a última missão da cidade 1. Vincular a carga a uma missão principal requer coordenação posterior com a agente da campanha; não há esse vínculo aplicado neste pacote.

A ponte citada pelo usuário é a continuação norte, para cima no mapa da V1. A montanha fica no ramal lateral direito/leste, com saída/alça própria antes da obra. Preservar o acesso da serra e o retorno à cidade enquanto a continuação norte está bloqueada. A ponte foi implementada posteriormente em módulo independente, fora deste patch de atividades; consulte [a revisão da ponte](../evidence/auditoria-viaria/2026-10-05-north-gateway/relatorio.md). Seus ganchos foram aplicados somente em `WorldConnection3D.gd` e `CoastalProtection.gd`, sem aplicar os quatro ganchos deste pacote. A validação no motor de ambos continua pendente.

## Patch preparado

Executar, na raiz do projeto, depois de reler as alterações atuais da outra sessão:

```powershell
python tools/mountain_pack/prepare_integration.py
python tools/mountain_pack/validate_prepared.py
```

O primeiro comando escreve somente em `evidence/mountain-pack-20261005/integration/`:

- `mountain-pack.patch`: alterações pontuais propostas.
- `manifest.json`: hash dos fontes usados, hash das prévias e `shared_files_written: 0`.
- `preview/`: versões propostas com extensão `.gd.txt`, para revisão.

O gerador exige contexto único e confere os hashes novamente antes de publicar a prévia. Se um contexto ou hash mudou, interrompe em vez de aplicar texto sobre trabalho novo. Não copiar as prévias inteiras sobre os fontes: revisar e aplicar os trechos na versão corrente quando a outra sessão terminar de editar/testar esses arquivos. Nenhum dos comandos aplica o patch.

| Fonte compartilhado | Ganchos propostos |
| --- | --- |
| `runtime/FullSession.gd` | Instalação do agregador, interações, diário, HUD, save e cancelamento em transição/morte/prisão. |
| `runtime/GameState.gd` | Recusa de blocos inválidos e recibos sem resultado correspondente, aceitando saves antigos sem atividades da montanha. |
| `runtime/ProductionWorld.gd` | Cancelamento antes da conclusão de viagem entre regiões. |
| `world/regions/NativeRegion.gd` | Acesso e máscara de terreno da trilha, cristas e balizas por chunk, reserva de espaço contra árvores e decoração. |

O patch não edita `HarborMissions.gd`, `CampaignRuntime.gd`, `MissionWorld.gd`, Jessica, chegada, garagem, casa de Takeshi ou áudio. Os ganchos de sessão e mundo só devem entrar junto com todos os módulos novos.

## Verificação feita

O parser gdtoolkit aceitou os scripts novos e as quatro prévias de fontes compartilhados. As referências literais de recursos foram encontradas, os JSONs foram lidos e os scripts Python passaram por análise sintática. Os hashes dos quatro fontes coincidiram com a prévia no momento da checagem. Isso não executa nem substitui a compilação e a análise de tipos do Godot.

A revisão estática corrigiu a prioridade do objetivo perante atividades existentes, cancelamento de leitura com callbacks antigos, guarda de tipos dos saves, recibos órfãos, pausa dos sete carros em menus, autosave dos resultados e precedência do estado recente do jipe sobre uma captura antiga da frota.

## Fila de validação após integração

Antes de aplicar o patch, registrar baseline renderizado dos cenários afetados, com a outra sessão e a geração pesada de voz paradas. Executar cada etapa em sequência. Usar exclusivamente Godot 4.7.2 .NET da instalação indicada em `AGENTS.md`, compilando `Harbor.csproj` antes do motor. O runner abaixo faz essa compilação e usa armazenamento temporário isolado:

```powershell
.\tests\run_suite.ps1 -Only 'test_mountain_story_progress,test_mountain_downhill_progress,test_mountain_jeep_progress,test_mountain_jeep_course,test_mountain_pack_state,test_mountain_story_runtime,test_mountain_downhill_runtime,test_mountain_jeep_integration'
```

Esses oito testes foram escritos, mas não executados. Os testes runtime exigem o agregador instalado; fixtures iniciais de posição não certificam trajetos completos. A opção `--drive` do teste da descida acrescenta uma corrida física inteira, sem teleporte ou avanço injetado após a largada. Deve ser rodada separadamente pela variante .NET `_console.exe`, com `--no-save`, `--skip-arrival` e armazenamento isolado. O runner normal não passa `--drive`.

Também são necessárias verificações focadas das alterações compartilhadas: save/load da campanha, chegada, Jessica, garagem, viagem entre regiões, esqui e missão de Tonico. Não repetir a suíte inteira sem evidência de impacto ou falha.

Continuam pendentes:

- Jogar as duas investigações e percorrer o acesso real lago–caverna; verificar interação, colisão e oclusão separadamente. Atualizar o checklist compartilhado de interiores com evidências, sem sobrescrever o trabalho da garagem.
- Dirigir a descida completa à noite: competitividade dos seis NPCs, frenagem, ultrapassagens, recuperação, vitória/derrota e apoio durante streaming. Teto de velocidade no código não comprova velocidade alcançada.
- Dirigir a volta de jipe completa, calibrar 110 segundos, atravessar cristas e limites de chunk pelos dois sentidos, estacionar, sair e retornar. Validar correspondência visual do solo e da colisão, sem árvores/rochas invadindo o corredor.
- Verificar interrupções reais por morte, prisão, saída/troca de veículo, menus e troca de região; repetir/load não pode recriar prêmios nem duplicar o jipe.
- Observar temporalmente os faróis e a estrada na cena renderizada. Comparar frame time antes/depois (p50, p95, p99 e picos) em primeira visita, grid de sete carros, corrida noturna, trilha e retorno/cancelamento, com configuração idêntica e sem concorrência.

Não há aprovação de física, apresentação, iluminação, performance ou regressões da campanha nesta etapa.
