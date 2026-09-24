# Serviços e interações — handoff V1 → V2 (2026-09-21)

Escopo desta rodada: revisão por código e correções isoladas em `runtime/Services.gd` e `data/catalogs/ServiceCatalog.gd`. `ServiceDialogue.gd` foi conferido e não precisou mudar. Godot, testes, benchmarks e commits não foram executados por instrução da rodada.

## Prioridade 1 — dinheiro consumido sem serviço

### Garagem genérica ao falar com o mecânico — defeito comprovado e contido

- Fonte V1 produtiva: `ui/MainMenu.gd:7,107-114` inicia `world/harbor/HarborGame.tscn`; `HarborGame.gd:111-124` instala `PersonalCarManager`; `world/harbor/monaliza/PersonalCarManager.gd:4-5,72-84,276-284` exige a Monaliza elegível e o jogador na garagem antes de cobrar R$ 50 e só então repara/recupera. `world/harbor/interiors/HarborGarageInterior.gd:459-503` reutiliza essa API e desabilita ações inelegíveis.
- Legado desconectado: `GarageMenu.gd:6-15` apenas emite `repaired` com preço de R$ 150; a árvore produtiva não o instancia. A única referência encontrada está em `legacy/city_demo/scripts/CityDemo.gd:85` via `GarageTrigger.tscn`.
- V2 já conectada corretamente: `runtime/PersonalCar.gd:4,43-65,82-133` fornece na bancada o menu existente de reparar/recuperar por R$ 50, valida localização, veículo, dano, saldo e baia antes de `Economy.spend`, entrega o reparo e salva.
- V2 defeituosa: `runtime/FullSession.gd:601-604,815-835` também manda a conversa com o mecânico para um menu genérico de R$ 150. O callback chama `Economy.spend` antes de `world.driving.car.repair()`, sem verificar se há veículo presente na garagem, se é a Monaliza ou se precisa de reparo. `scripts/Driving.gd:_ready,can_enter` mantém em `car` o último veículo criado/selecionado mesmo quando o jogador está a pé; assim, a conversa pode cobrar por um carro remoto e pode debitar R$ 150 sem mudança alguma quando esse carro já está íntegro.
- Contenção aplicada: `runtime/Services.gd:perform` intercepta somente `garage` dentro de `maciota`, impede que o menu genérico perigoso abra e orienta para a bancada já conectada. Não cria menu, não toca personagem, combate, transporte ou geometria.
- Integração definitiva recomendada em `runtime/FullSession.gd` (arquivo compartilhado vedado nesta rodada): remover o ramo genérico `service in ["garage","auto_service"]` e, no ramo `mechanic` após a introdução, manter conversa funcional ou direcionar para a interação da bancada. Não duplicar `PersonalCar._service`; ela já contém o contrato completo.

### Colete comprado com proteção cheia — defeito comprovado, depende do integrador

- Fonte V1 produtiva: `world/harbor/interiors/HarborAmmunationInterior.gd:303-318,362-367` desabilita comprar quando `armor >= max_armor`; `characters/Player.gd:1601-1610` volta a verificar o máximo antes de debitar R$ 500.
- V2: `runtime/FullSession.gd:836-856` oferece sempre “Colete · R$ 500”; o callback em 853-855 chama `Economy.spend` e depois apenas atribui `armor = 100`. Com colete já em 100 e saldo suficiente, há débito sem resultado novo e sem mensagem de falha.
- Encaixe exato para o integrador em `FullSession._show_shop`: antes de gerar o botão, tratar `world.gameplay.armor >= 100` como “Proteção completa” sem cobrança; no callback, repetir essa guarda antes de `spend`, mostrar “Dinheiro insuficiente” quando o débito falhar, atribuir 100 somente após sucesso e então salvar. A segunda guarda evita que estado mude enquanto o menu está aberto.
- `ServiceCatalog.gd` agora registra o requisito V1 “armor below maximum” e aponta para `_data`/`purchase` e `Player.buy_armor_amount`; o catálogo ainda não é consumido por `FullSession`.

## Prioridade 2 — fluxos conferidos e conectados

| Fluxo V2 | Início | Requisitos antes da cobrança | Entrega | Saída/cancelamento | Estado por leitura |
|---|---|---|---|---|---|
| Northgate Auto | parar na baia | carro dirigido, íntegro como instância, vivo e imóvel; saldo de R$ 100 | reparo + limpar procurado + save | sair/mover antes de 4,5 s cancela sem cobrar; afastar-se rearma | conectado |
| Monaliza | bancada da garagem | desbloqueada, carro/registro elegível, dano ou recuperação necessária, baia livre, saldo de R$ 50 | reparar ou recuperar na baia + save | “Fechar”; mudança de posição/vida invalida ação sem cobrar | conectado |
| Mecânico, menu genérico | conversar | nenhum requisito veicular suficiente | último carro selecionado por `Driving` | “Voltar” existia, mas ação insegura | contido; remover no integrador |
| Armas/roupas | balcão genérico do interior | item conhecido, desbloqueado, não possuído, saldo | compra/equipamento + save | “Voltar”/Esc | conectado |
| Munição | menu da loja de armas | arma possuída, quantidade/limite e saldo | reserva +30 + save | menu fecha | conectado |
| Colete | menu da loja de armas | **faltando:** proteção abaixo de 100 | atribui 100 + save | menu fecha | defeito depende do integrador |
| Hospital | cruz física / residente / triagem | a pé; cura somente se ferido e pickup disponível | vida 100 / diálogo | diálogo continua e fecha; pickup reaparece | conectado por código |
| Bombeiros | área de primeiros socorros / residente / alarme | a pé e ferido para cura | +9 HP/s / diálogo | sair da área para cura; diálogo fecha | conectado por código |
| Delegacia | residente / terminal | ponto físico individual | diálogo, sem limpar procurado | diálogo fecha; saída do interior prioritária | conectado por código |

### Northgate Auto

- V1 produtiva: `HarborGame.gd:120-123` instancia `world/harbor/HarborAutoService.gd`. O fluxo em `HarborAutoService.gd:54-84,93-131,144-205` exige veículo controlado e parado na baia, verifica R$ 100, permite cancelamento sem cobrança se o alvo deixa de ser válido, cobra somente na entrega, repara, limpa procurado e libera controles/saída.
- V2 conectada: `FullSession.gd:271-274` instala `Services`; `Services.gd:_physics_process,_auto_eligible,_tick_auto` verifica veículo ocupado/parado, baia e saldo, cancela ao mover/sair antes de 4,5 s, cobra R$ 100 imediatamente antes de reparar, limpa procurado, salva e impede cobrança repetida até o veículo sair.
- Diferença restante: a V2 não reproduz a animação/persiana do V1; isso é apresentação, não quebra do contrato do serviço. Exige execução para confirmar coordenadas da baia, prompt percebido pelo jogador e saída física.

### Hospital, bombeiros e delegacia

- Hospital V1: `HospitalHealthPickup.gd` herda `economy/HealthPickup.gd`, cura até 100 e reaparece após 180 s; `HarborHospitalInterior3D.gd` mantém Enfermeira Clara, Dr. Miguel e triagem.
- V2: `Services.gd` conserva cura gratuita, limite 100, recarga de 180 s, ponto físico, persistência do cooldown e diálogos físicos dos dois residentes/triagem. O estado é salvo em `FullSession.gd:961` e restaurado em 271-275.
- Bombeiros V1: `HarborFireStationInterior.gd:26-35,486-554` cura gratuitamente a 9 HP/s apenas dentro da área; alarme fecha por E/Esc ou ao sair. V2 conserva a cura por proximidade, diálogo do Capitão Rocha e inspeção do alarme; o menu compartilhado fecha por continuar/Esc, e a saída do interior permanece prioritária em `FullSession.nearest`.
- Delegacia V1: `HarborPoliceInterior.gd` contém os cinco residentes e o terminal #304. V2 usa `OriginalResidentData.json` + `ServiceDialogue.gd`, pontos individuais e o terminal físico. Conversar não limpa nível de procurado.
- `ServiceDialogue.gd` foi comparado com os textos produtivos acima; não houve adaptação de conteúdo nesta rodada.

### Lojas já conectadas

- Armas, munição e roupas reutilizam o menu compartilhado em `FullSession._show_shop`; compras de armas/roupas passam por `Economy.purchase`, que valida catálogo, desbloqueio, duplicidade e saldo antes de debitar. Munição passa por `Economy.buy_ammo`, que verifica posse e limites antes da cobrança interna.
- A falha específica do colete é a exceção porque usa `Economy.spend` diretamente, fora da compra validada.
- `harbor_fuel` não é um serviço de compra no V1 produtivo: ele é criado por `HarborRobberies.gd` como interior de evento. Na V2, `Robberies.nearest_action` tem prioridade sobre o ponto genérico. O ponto `service=fuel` que abre e fecha “Atendimento” não foi transformado em serviço novo.

## Arquivos alterados

- `geteco_v2/runtime/Services.gd`: contenção da rota genérica insegura do mecânico.
- `geteco_v2/data/catalogs/ServiceCatalog.gd`: remove a falsa referência ao preço legado de R$ 150 e registra os contratos produtivos de reparo/recuperação da Monaliza a R$ 50, Northgate e colete.
- `geteco_v2/docs/historico/SERVICES_FLOW_HANDOFF_2026-09-21.md`: evidências, integrações e lacunas desta frente.
- `geteco_v2/data/catalogs/ServiceDialogue.gd`: conferido, não alterado.

## Hipóteses e verificações não executadas

- Defeitos comprovados por código: cobrança da garagem genérica sem validar presença/identidade/dano do carro; tarifa/origem incorretas no catálogo; cobrança do colete já completo.
- Hipóteses que exigem execução: alinhamento real da baia Northgate; alcance confortável dos pontos de interação; foco/fechamento de cada menu com teclado e controle; percepção da orientação da bancada; entrega visual e persistência após reiniciar o jogo.
- Não foram validados compilação, execução, colisão, desempenho, menus em runtime nem persistência real. A mudança não adiciona processamento por frame, iluminação, física ou streaming; por isso a skill de performance não foi acionada.
