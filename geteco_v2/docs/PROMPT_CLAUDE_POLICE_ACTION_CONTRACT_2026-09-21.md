# Claude — contrato externo da ação policial V2

## Escopo

Complete apenas os contratos de animação, arma e evento de crime que ficaram fora da revisão do ciclo policial. Não reescreva `gameplay/dispatch/`, não altere roteamento, limites, ultrapassagem, ownership ou máquina de estados das viaturas.

## 1. Evento de crime contra policial

Fonte V1: `police/PoliceOfficer.gd::take_damage/_die` e `police/WantedManager.gd::report_officer_killed`.

- Agressão do jogador a policial vivo deve garantir no mínimo 2 estrelas (`crime_points >= 30`), inclusive atropelamento com veículo realmente dirigido pelo jogador.
- Morte de policial pelo jogador deve chegar a pelo menos 3 estrelas e preservar a soma V1: depois da agressão, acrescentar `max(30, 60 - crime_points)`.
- Não atribuir crime a viatura de despacho, tráfego, fogo sem autoria do jogador ou fonte inválida.
- Preservar a deduplicação já existente para pelotas, dano contínuo e um atropelamento por contato.
- O `PoliceAgent.receive_damage(source)` já identifica o alvo real para reação tática; o registro penal deve continuar central em `Gameplay`, sem duplicar estrelas no agente.

## 2. Arma do policial

`PoliceAgent` decide percepção, perseguição, distância, 0,65 s de mira e autorização para atacar. Faça o backend de arma/apresentação consumir essa decisão, sem criar um segundo alvo ou segundo laço policial.

- Corrigir a tabela V1: patrulha/detetive causam 6; army/FBI/SWAT causam 8. O caminho atual está invertido (`8` nos patamares baixos e `6` nos altos).
- Preservar bloqueio de garagem por `weapons_allowed()`, linha de visão física e dano somente no alvo real atual.
- Portar, se mantido no V2, pente/recarga, rajada de 2 tiros na patrulha e 3 nos demais, pausa de 1,7–2,5 s e cadência por patamar. Não deixe a recarga alterar procura ou despacho.
- Não trocar por dano remoto sem traço/feedback; a simulação pode continuar central em `Gameplay.police_shoot`, mas precisa emitir um evento visual/sonoro único por disparo.

## 3. Animação e apresentação

- Usar o `PoliceModel` nativo, sem `SubViewport` privado.
- Expor/consumir eventos de mirar, disparar, recarregar, receber impacto e cair. Eles não podem escrever estrelas, alvo, rota ou estado da unidade.
- Preservar locomoção/colisão do `CharacterBody3D`; animação nunca move o corpo lógico nem atravessa sólidos.
- A queda deve terminar sem colisão bloqueadora e sem manter processamento por quadro.

## 4. Uma estrela / prisão

O agente revisado não atira sem agressão em 1 estrela e segura a aproximação a 34 px equivalentes (2,125 m). Falta um contrato externo de rendição/prisão no V2: depois de aviso e imobilidade comprovada, solicitar a transição de prisão/respawn; não limpar a procura silenciosamente e não transformar a prisão em execução.

## Aceitação dirigida

1. Ferir um policial do zero: no mínimo 2 estrelas; matar: no mínimo 3.
2. Atropelar com carro do jogador conta uma vez; atropelar com viatura não conta.
3. Uma estrela sem agressão: aproxima/ordena, não atira; agressão real: reage.
4. Parede bloqueia tiro e percepção; perda de contato zera mira.
5. Dano por patamar, rajada e recarga observáveis sem duplicar projétil/dano.
6. Garagem continua sem armas e sem dano.
