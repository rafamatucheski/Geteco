# Mapa do catálogo do Mixamo (30/10/2026)

Lido pela API do site logado: **2.484 itens** (1.481 nomes únicos, já que muitos têm
variações) e **30 pacotes**. O jogo hoje usa do Mixamo só três bibliotecas do Dante
(`assets/dante/mixamo/`: morte, greatsword da katana e veículo). Os golpes de soco,
taco e machado são feitos à mão em `gameplay/MeleeMoveset.gd`.

## O catálogo por área

| Área | O que tem (exemplos) | Uso no Geteco |
|---|---|---|
| **Espada e escudo** | Pacotes *Pro* e *Lite Sword and Shield*: Idle, Walk, Run, Strafe, Turn/180, Jump, Crouch, Slash, Attack, Kick, Block, Block Idle, Crouch Block, Impact, Power Up, Casting, Death; Draw/Sheath Sword 1-2 | **Kit completo pronto para a ideia da espada e escudo** |
| **Greatsword** | Pacote *Great Sword*: Slash, High Spin Attack, Slide Attack, Kick, Blocking, Impact, Draw/Sheath | Já usado na katana; sobram o giro, o deslize, o chute e a defesa |
| **Espada de uma mão / genérico** | One Hand Sword Combo, Two Hand Sword Combo, Stable Sword Inward/Outward Slash, Thrust Slash, Slash Advance, Sword Fight One, Standing Melee Attack (360 High/Low, Backhand, Downward, Horizontal), Melee Combo Ver. 1-3, Run Jump Attack, Two Hand Club Combo, Heavy Weapon Swing | Combos para a espada; o Two Hand Club serve para o taco e o machado |
| **Boxe e MMA** | Boxing, Jab Cross, Body Jab Cross, Hook, Uppercut, Elbow/Knee combos, Quad Punch, Punch Combo, Mma Idle/Kick, Roundhouse, Side Kick, Fight Idle, Bouncing Fight Idle | Trocar os socos à mão por mocap; guarda de luta |
| **Defesa e esquiva** | Standing Block Start/Idle/End/React Large, Inward/Outward/Left/Right/Center Block, Standing Dodge Forward/Left/Right, Dodging, Evading A Threat | Botão de defesa e esquiva, que hoje não existem |
| **Receber golpe** | ~30 reações: Hit To Head/Body/Legs/Back, Receive Uppercut, Kidney/Rib/Stomach Hit, Standing React Small/Large (de cada lado), Shoved, Shove Reaction, Walking Hit Reaction | NPC e jogador reagem conforme o lado e a força do golpe |
| **Nocaute e queda** | Knocked Down/Out/Unconscious, Livershot Knockdown, Shoulder Hit And Fall, Sweep Fall, Falling Back/Forward Death, Getting Up, Kip Up, Hit By Car | Nocaute sem matar; levantar; atropelamento |
| **Luta em dupla (2 papéis)** | Double Leg Takedown (atacante/vítima), Shoulder Throw (agressor/vítima), Hostage Situation e Release Hostage (vilão/refém), Taken Hostage, Restrain, Strangling, Stealth/Brutal Assassination, Pull Pilot From Seat / Pulled From Seat | Agarrão, finalização, refém no assalto, polícia algemando, roubo de carro |
| **Capoeira** | Ginga (várias), Au, Armada, Meia Lua de Frente/Compasso, Martelo, Queixada, Rasteira, Bênção, Chapa, Esquivas 1-4, Macaco | Estilo de luta brasileiro, com a cara do jogo |
| **Academia** | Punching Bag, Speedbag, Jumping Rope, Bicep Curl, Back/Air/Overhead Squat, Clean And Jerk, Snatch, Kettlebell Swing, Burpee, Push Up, Situps, Plank, Jumping Jacks, Treadmill Running, Warming Up, Arm/Neck Stretching | **Academia funcional: treinar = ganhar atributo** |
| **Tiro** | Pacotes Pistol, Rifle 8-Way, Pro Rifle, Shooter: andar/correr mirando em 8 direções, agachado, deitado, recarregar, sacar, coronhada | Locomoção mirando, cobertura, deitado |
| **Cobertura e furtividade** | Stand To Cover, Cover Idle, Crouch Cover To Cover, Left/Right Cover Sneak, Peek Around Corner, Sneak Walk | Sistema de cobertura nos tiroteios |
| **Parkour e escalada** | Braced/Free Hang + Shimmy, Climbing Up Wall, Wall Run, Vault Over Box, Ladder, Rope Climb, Running Slide, Rolls | Escalar muro, pular obstáculo, rolar na queda |
| **Arco e magia** | Longbow Pro/Lite, Magic Spell Pack | Arco serve para a serra (caça); magia não combina |
| **Locomoção e estados** | Locomotion Male/Female, Injured Pack, Drunk Pack, Catwalk, Old Man Walk, Swagger/Strut | Andar ferido quando a vida está baixa, bêbado saindo dos bares, NPCs variados |
| **Vida na rua (NPC)** | Texting, Talking On Phone, Smoking, Drinking, Leaning On A Wall, Waving, Arguing (Angry Gesture/Point, Insult), Cheering, Shaking Hands, Sitting (várias), Bartending, Cards, Dice | Cidade viva; Bartending e Cards nos bares Lastro e Sede |
| **Trabalho e interação** | Pick Up Item, Opening Door, Pulling Lever, Button Pushing, Typing, Searching Pockets, Rummaging, Digging, Farming Pack, Wheelbarrow, Fishing, Administering CPR | Lojas, oficina, socorro no hospital, pesca |
| **Veículo** | Entering/Exiting Car, Driving, Honking Horn, Jostled Passenger, Skateboarding | Parte já em uso pelo mocap de veículos |
| **Dança e festa** | Breakdance Pack, Hip Hop (várias), Samba, Salsa, Belly Dance, Twerk etc. | Balada, encontro noturno dos Cobras |
| **Esporte** | Futebol (goleiro, pênalti, embaixadinha), Basquete, Beisebol, Golfe | Minigames futuros |
| **Criaturas** | Zombie e Mutant Packs, Creature Pack | Para os ursos não serve (são bípedes) |

## Proposta: espada e escudo

Tudo o que o sistema precisa já vem pronto no **Pro Sword and Shield Pack**, que é o
pacote mais completo de combate do site:

1. **Achar a arma:** uma espada e escudo lendários escondidos (na Forja da Serra, por
   exemplo, ligando com a pista ferreiro → eremita → minerador) ou comprados do
   ferreiro.
2. **Combate na rua:** Slash e Attack encadeados no combo (como o `CHAIN` do
   `MeleeMoveset`), segurar o botão para defender (Block Idle; Impact quando o golpe
   bate no escudo), esquiva lateral (Standing Dodge), chute de escudo para
   desequilibrar e Power Up como ataque pesado carregado.
3. **Escudo contra bala:** Block segurado cobre a frente; a polícia passa a tentar
   flanquear. Rende uma mecânica nova.
4. **Academia:** saco de pancada, speedbag, corda e pesos aumentam força e fôlego; um
   professor de capoeira ou de espada destrava golpes (Meia Lua, Armada, Spin Attack).
   Treinar é uma atividade (`activities/`), com as poses da lista da academia.
5. **Reação dos NPCs:** as reações de golpe por lado, o nocaute e o Getting Up fazem a
   briga de rua parecer real; Shoulder Throw e Takedown viram finalizações.

## Ordem sugerida

1. Baixar os pacotes **Pro Sword and Shield**, **Lite Sword and Shield** e as
   **reações/nocaute** no rig do Dante (mesmo fluxo de `dante_mixamo_sword.res`).
2. Protótipo de espada e escudo: idle, andar, combo de 3, defesa, impacto e morte.
3. Reações de golpe e nocaute para os NPCs (também melhoram os socos atuais).
4. Academia com treino ligado à progressão.
5. Depois: capoeira, cobertura, andar ferido/bêbado, vida na rua.

Cuidados: os clipes do Mixamo vêm com deslocamento na raiz ("in place" precisa ser
marcado no download), nomes repetidos têm variações diferentes, e as animações de dois
papéis precisam alinhar os dois personagens. Pela regra do projeto, cada biblioteca nova
precisa entrar num pré-aquecimento e não pode ser carregada com `load()` síncrono no meio do jogo.
