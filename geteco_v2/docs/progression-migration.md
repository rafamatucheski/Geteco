# Progressão do primeiro trecho V2

`systems/Progression.gd` é um objeto de dados `RefCounted`, sem autoload, dependências do V1 ou processamento por frame. A cena controla proximidade, diálogo, apresentação, checkpoint e salvamento; o estado controla ordem das interações, inventário e restrições da localização.

## Fontes reaproveitadas e adaptação

- `characters/JagerNPC.gd`, `DIALOGUES[0]`: saudação original de Maciota, preservada em `data/GarageSequence.gd`.
- `world/harbor/campaign/HarborStoryArrival.gd`, chamada de `meet_maciota`: objetivo original “Entre na garagem e converse com Maciota.” e identificador da fase.
- `systems/CampaignState.gd`: separação conceitual entre estado persistente e apresentação. Não foi copiado o autoload que contém outros sistemas e processamento por frame.
- A sequência `harbor_arrival_v2` é uma adaptação nova para validar o trecho, **não** migração concluída de `HarborArrivalMission`. No original, conhecer Maciota abre o quadro de missões; aqui Maciota pede uma peça, o mecânico libera a bancada e Dante entrega a peça. Os diálogos de ligação são novos. Telefone, quadro, contratos e passeio original ainda não foram migrados.

## Contrato de integração

```gdscript
var progress = preload("res://systems/Progression.gd").new()
var result = progress.load_game() # loaded / recovered_backup / missing / invalid
progress.set_location("harbor_garage") # também guarda a arma
var dialogue = progress.interact("maciota") # ok, message, speaker, changed
if dialogue.changed:
    var error = progress.save_game()
```

- Localizações: `harbor_street`, `harbor_garage`. A cena resolve esses IDs em pontos seguros de chegada, sem persistir coordenadas arbitrárias.
- Interações: `maciota`, `mechanic`, `workbench`. A cena deve garantir presença física, proximidade e ausência de outra conversa antes de chamar. O estado recusa interações da garagem quando a localização é rua.
- Propriedades somente leitura: `location_id`, `stage`, `part_available`. `objective()` retorna o objetivo; `snapshot()` produz cópia profunda independente.
- Fases: `meet_maciota`, `talk_mechanic`, `collect_part`, `return_maciota`, `complete`. Coleta e entrega são idempotentes; sair não bloqueia o progresso.
- Inventário não depende dos nós da cena. A peça é adicionada uma vez e consumida uma vez. O esquema contém IDs reservados de armas para o contrato de restrição; isso não significa que armas ou combate já estejam implementados.

## Persistência

Save padrão `user://GetecoV2/progress.json`, com namespace de projeto separado configurado pelo integrador. Os métodos aceitam caminho alternativo para testes. Nunca abrem saves do V1. Esquema 1 contém marcador `geteco_v2`, ID de missão, fase, localização, inventário, arma equipada e missões concluídas; formato V1 e versões desconhecidas são recusados. Conversão de saves antigos fica para uma migração explícita futura.

Escrita: arquivo temporário no mesmo diretório, flush, fechamento, leitura e validação, rotação do principal validado para `.bak`, promoção do temporário por rename. Interrupção entre rotação e promoção recupera `.bak`. Principal corrompido nunca substitui backup. Leitura ausente ou inválida não modifica a sessão em memória nem escreve em disco. Isso é uma publicação por rename com recuperação de backup; não é garantia contra falha física do disco.

`restore_snapshot` valida versão, tipos, IDs, contagens inteiras limitadas e consistência entre fase, peça e conclusão. Reaplica a restrição pelo ID da localização: arma equipada dentro da garagem é guardada sem perda de inventário.

## Segurança da garagem e limite atual

`equip_weapon` bloqueia saque/troca na garagem e exige posse do item. `can_attack` é o contrato comum para futuros disparos, explosivos e corpo a corpo, inclusive desarmado. A integração desses sistemas **ainda não existe**; o teste atual comprova o estado e seus bloqueios, não proteção contra um combate já funcional. Os NPCs não devem receber vida nem rotinas de dano/morte. O teste obrigatório do projeto original `tests/test_garage_weapon_restrictions.gd` continua necessário quando esses personagens/transições são alterados no V1; ele não equivale ao teste de integração do V2.

## Validação

`tests/test_progression.gd`: sequência e repetição, ordem incorreta, isolamento de snapshots, dados inválidos, inventário, restrições na entrada/restauração/saída, roundtrip em disco, backup, arquivos corrompidos, ausência do principal, esquema futuro e limite de tamanho. Cria arquivos em diretório exclusivo de teste e remove somente esses arquivos. Executar com Godot headless e `--script res://tests/test_progression.gd` em janela coordenada com a medição do jogo. Não certifica FPS ou integração visual.

Em 21/09/2026, Godot 4.7.2: **90 checks aprovados, exit 0**. A execução inicial no sandbox não permitiu criar `user://`; a execução autorizada encontrou uma divergência de tipos numéricos após JSON. Corrigida a normalização para inteiros na restauração, o teste passou. Essa evidência se refere ao estado de progressão e persistência isolado.
