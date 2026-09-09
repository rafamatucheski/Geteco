# Monaliza — carro pessoal do Dante

Integração no Harbor oficial em 08/09/2026. O cupê azul e laranja fica exposto na oficina Westgate antes da primeira entrega. A conclusão da entrega libera o mesmo veículo, mantém a recompensa original de $150 e acrescenta a fala do Maciota sobre cuidar da Monaliza e conferir a surpresa no porta-malas.

## Fluxo jogável

- Antes da entrega: carro bloqueado, sem dano, sem possibilidade de dirigir. Não entra nos sorteios de trânsito.
- Depois da entrega: entrada pelo controle normal de veículos. Acelerar pela saída frontal da vaga leva o carro para fora da oficina pelo contrato existente de interiores.
- A pé, parado atrás da Monaliza: **T** abre o porta-malas real e a interface; **Esc** ou o botão fecha. Trocas remotas são recusadas. Tomar dano, morrer, afastar-se ou o carro começar a mover fecha a interface.
- A primeira abertura entrega escopeta, 16 cartuchos e faca uma única vez. Ativa três espaços: curta, longa, corpo a corpo. Punhos continuam disponíveis.
- Armas adquiridas sem espaço livre permanecem no arsenal. A roda e as teclas numéricas só selecionam as três escolhidas. Trocar uma arma preserva a propriedade e a munição da anterior. Outros carros não ganham arsenal.
- Na vaga da Westgate, **T** permite recuperar/reparar por $250. A recuperação mantém o arsenal. O desmanche recusa o carro pessoal.
- Saves anteriores com a primeira entrega concluída recebem a Monaliza liberada na oficina; a surpresa continua disponível se ainda não foi aberta.

## Modelo, cenário e áudio

`district/harbor_preview/monaliza/MonalizaModel.gd`: carroceria facetada original inspirada na referência, azul repintável com faixa laranja fixa, intercooler, faróis com projetores, rodas de seis raios, saias, escape e aerofólio. Tampa e aerofólio abrem juntos em uma dobradiça própria. Escala aproximadamente 4,46 m de comprimento, compatível com Dante e com a vaga de 3,5 × 6 m.

A garagem foi ampliada e recebeu o kit 3D do Antigravity (`art/monaliza_workshop/MonalizaWorkshopProps3D.gd`), com bancada, ferramentas e iluminação. Os 11 obstáculos declarados pelo kit viram colisões projetadas no mesmo sistema visual. O cenário usa um viewport estático; as peças antigas da oficina tiveram escala reduzida e o elevador foi deslocado para liberar a circulação. A oficina ainda combina esse cenário 3D com elementos anteriores em 2D; não é uma conversão integral de todo o interior.

Os WAVs originais do Claude (`audio/monaliza_review/`) estão conectados: partida, motor com modulação de RPM/marcha, assobio sob carga e alívio ao soltar o acelerador. O carregador restaura explicitamente os metadados de loop que o WAV não preserva. O controlador comum de RPM não substitui mais o áudio exclusivo durante a condução. Há fallback procedural e cache por tipo.

## Persistência

`Player.serialize()/restore()` inclui `personal_car_state`, `personal_loadout_enabled` e `personal_loadout`. Estado do carro: posição estacionada, orientação, cor, integridade e avaria. O marcador `monaliza_starter_case` em `world_pickups_collected` impede duplicar a surpresa. Inventário e munição continuam nas estruturas existentes.

O manager captura o carro mesmo quando Dante está a pé ou dirigindo outro veículo. A restauração funciona tanto na cena atual quanto em uma nova cena criada pelo SaveManager. O RegionTravel reutiliza a instância pessoal quando o save foi feito ao volante, evitando duplicação. Marcas individuais de deformação na malha não são serializadas; a integridade é preservada.

## Verificação executada

- `tests/test_monaliza_reward.gd`, Vulkan/RTX 4060: recompensa real, bloqueio inicial, proteção no desmanche, surpresa única, seleção real do OptionButton, reserva preservada, recusa de troca remota, restauração a pé e ao volante, saída com aceleração real, sons durante a condução, recuperação paga e recriação da cena com posição/dano/pintura preservados. Resultado: `MONALIZA REWARD FAILURES []`.
- `tests/test_monaliza_audio.gd`, headless: arquivos, PCM, picos, emendas de loop, envelopes e demo. Resultado: `MONALIZA_AUDIO_TEST failures=0`.
- `tests/test_monaliza_workshop_art.gd`, Vulkan: dimensões, corredor livre, 11 obstáculos e 117 meshes; capturas reais. Zero falhas.
- `tests/test_tutorial_preview.gd`, headless: 60 verificações. Zero falhas.
- `tests/test_gameplay_tutorials.gd`, headless: bloqueios de combate/modal/pausa e contextos reais na montanha. Zero falhas.
- `tests/test_harbor_campaign_flow.gd`, Vulkan e headless: chegada, conversa, quadro, primeira entrega, recompensa, hospital e saves. `HARBOR CAMPAIGN FLOW: 0 failure(s)`. No modo sem janela, o helper de teclas precisou descarregar eventos e aguardar um frame de processamento para não perder a interação do quadro; todas as verificações foram mantidas.
- `tests/test_monaliza_garage_access.gd`, Vulkan: interação nativa com o quadro no novo espaço e desmontagem da cena com o quadro aberto. Corrigido o callback que tentava atualizar a campanha depois de sair da árvore.

As dicas de porta-malas e capacidade foram ativadas no jogo quando a surpresa libera o sistema. As dicas aguardam o nome do veículo desaparecer para não sobrepor textos no canto da tela.

Capturas reais: `D:/geteco/monaliza-front-review.png`, `D:/geteco/monaliza-trunk-review.png`, `D:/geteco/monaliza-garage-review.png`, `D:/geteco/monaliza-loadout-review.png`. Demo sonora: `audio/monaliza_review/demo_start_accelerate_release.wav`.

Não houve medição conclusiva de FPS para o mapa inteiro nesta entrega, nem audição humana do áudio pelo agente. A análise de áudio foi técnica e a demo está disponível para avaliação. Os testes de mundo ainda imprimem um aviso de uma instância ObjectDB retida ao encerrar, também observado anteriormente; não foi apresentado como resolvido.

Prompts originais da divisão de trabalho: `docs/PROMPT_CLAUDE_MONALIZA_AUDIO.md` e `docs/PROMPT_ANTIGRAVITY_MONALIZA_WORKSHOP.md`. Os arquivos entregues por eles foram integrados, sem substituir seu trabalho.
