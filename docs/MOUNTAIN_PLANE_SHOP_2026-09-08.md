# Avião explorável e Ammu-Nation 3D — integração de 08/09/2026

## Contratos de instalação

- Avião: `preload("res://district/mountain_pass/MountainCargoPlane.gd").new()` como filho do `SecretMountainLake`, posição local zero, sem rotação adicional. Substitui o antigo `SmugglerPlaneWreck` 2D. Escala de 16 px por metro; reservar clareira/lago de pelo menos 560 × 500 px. O modelo tem cerca de 28 m de envergadura.
- Loja: `preload("res://district/mountain_pass/MountainGunShopFacade.gd").new()` na posição local da montanha `(7750, -220)`. Depois de `add_child`, chamar `facade.install_entrance(interior_mgr)`. Retirar a fachada e a porta antigas para não duplicar geometria ou interação.
- A constante `AMMUNATION_SCRIPT` de `MountainInteriorManager.gd` aponta para `MountainGunShopInterior.gd`. Nenhuma alteração em `HarborAmmunationInterior.gd`; a versão da montanha herda os contratos existentes.
- `MountainCargoPlane` aplica `mountain_shelter` ao jogador enquanto está dentro. A raiz da montanha deve considerar essa flag junto do abrigo de interiores e túneis. Não usa `mountain_interior_id`: o avião é explorado no próprio mapa, sem teleporte ou troca de cena.

## Comportamento

O avião usa o modelo de cargueiro do Antigravity, em escala humana. Entrar pela rampa abre o teto e demais partes superiores que ocultavam o corredor. A câmera aproxima suavemente usando `mountain_zoom`; sair restaura o estado anterior. Paredes, asas, carga e cabine têm colisões projetadas pela mesma câmera que desenha o modelo. A carga foi acomodada junto à parede esquerda no wrapper para liberar um corredor realmente transitável.

A caixa de contrabando está junto à frente do compartimento de carga: E concede $1.800 uma única vez, com som e aviso. A chave `mountain_cargo_plane_treasure_01` usa `Player.world_pickups_collected`, já incluído no save. Recriar a região mantém a caixa aberta e impede novo pagamento.

A Ammu-Nation usa fachada e interior 3D, com parede, balcão, estande de tiro, bancada e estufa alinhados aos colisores. Vance renderiza dentro do mesmo mundo 3D, atrás do balcão; preserva falas e gestos. E abre a loja; F conversa. O catálogo compra pistola, espingarda e rifle de caça pelos preços de WeaponCatalog; reposição da arma equipada custa $120 e usa os métodos existentes de Player. O vidro foi tornado transparente e o plinto ajustado no wrapper para permitir ver as pistolas da vitrine.

Os modelos estáticos atualizam seus viewports uma vez. Avião redesenha apenas ao mudar cutaway/tesouro. A loja ativa desenha a 20 Hz para os gestos do NPC e desativa renderização quando vazia.

## Ajustes pontuais nas fontes externas

O avião referenciava `iron_mat` sem declarar: o manche reutiliza `roller_mat`. O interior referenciava `steel_mat` e `stone_mat` sem declarar: acrescentados alias do aço existente e material da base da estufa. Não houve refatoração dos modelos externos. Ajustes de corredor, vidro e corte superior ficam nos wrappers.

## Verificação

`tests/test_mountain_plane_shop.gd` passou em Godot 4.7.2 headless e Vulkan real / RTX 4060. Cobre caminhada contínua da rampa até o tesouro através das duas fileiras de carga, bloqueio de saída lateral, teto/abrigo, pagamento único, serialização JSON e `Player.restore`, recriação do avião, saída restaurando câmera/abrigo, registro da porta, compra real de arma/munição e Vance no viewport correto.

Capturas reais do cenário de verificação, com Dante para referência de escala:

- `D:/geteco/mountain-plane-exterior-review.png`
- `D:/geteco/mountain-plane-cutaway-review.png`
- `D:/geteco/mountain-gunshop-exterior-review.png`
- `D:/geteco/mountain-gunshop-interior-review.png`

Logs: `D:/geteco/mountain-plane-shop-rendered.log` e `D:/geteco/mountain-plane-shop-test.log`.

As capturas são do cenário isolado de verificação; a instalação no lago e nas estradas fica com a integração da raiz. O teste headless ainda informa dois objetos remanescentes no encerramento; o teste Vulkan terminou sem esse aviso. Nenhum save do usuário foi gravado.

## Abrigo dos lenhadores

Adicionado `LumberjackShelterInterior.gd`, com modelo próprio `LumberjackBunkhouse3D.gd`. Tem quatro beliches (oito camas), bancada com serra de dois homens e machados, mesa coletiva com mapa/canecas/garrafa térmica, estufa com fogo discreto, vapor da chaleira, lenha, casacos e botas. Mantém calor, colisões projetadas, escala de Dante, spawn e retorno; não duplica a arma/faca do chalé.

As três entradas das casinhas de `MountainSettlement.gd` agora usam `lumberjack_shelter`. O manager registra o quarto em `(29500, 20000)` e continua usando os pontos de retorno individuais das portas. Os três abrigos compartilham este novo alojamento; o chalé principal permanece separado.

`MountainInteriorManager.region_ready` só passa a true depois de construir os quatro interiores. Em região com `streamed_region=true`, há uma pausa de quadro entre cada interior; no modo isolado o contrato síncrono anterior permanece. Isso distribui a construção, sem afirmar ausência de todo pico de frame.

`tests/test_lumberjack_shelter.gd` passou headless e Vulkan real: quatro beliches, bancada própria, ausência de loot duplicado, entrada/saída, renderização desligada quando vazio, separação do chalé e construção distribuída em três quadros. Captura real inspecionada: `D:/geteco/lumberjack-shelter-interior-review.png`. Log: `D:/geteco/lumberjack-shelter-rendered.log`.
