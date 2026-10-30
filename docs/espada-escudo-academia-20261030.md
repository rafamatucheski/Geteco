# Espada e escudo do gelo + academia Ferro Velho: desenho (30/10/2026)

Pedido do usuário: espada e escudo achados numa cabana secreta no gelo, com melhorias visuais, golpes
com as pernas e uma academia na cidade com interior vivo. O que está **feito** e o que é **próximo**.

## 1. Como o jogador acha a espada e escudo

| Etapa | Estado | Como |
|---|---|---|
| Cabana do Cavaleiro na serra | feito | `mountain_cabin_secret` (PlaceCatalog), mundo (655, −905): 75 m a noroeste da cabana do Mestre Aurélio, sem trilha nem placa. Por fora é a cabana de toras; por dentro, o chalé. A arma fica no fundo do chalé. |
| Pegar, salvar e liberar | feito | Mesmo caminho do rifle da cabana dos caçadores: `grant_world_reward` → `grant_weapon` → descoberta `mountain_cabin_secret_sword_shield`. Vai no espaço "corpo a corpo" do equipamento e não é vendida na loja. |
| Pista | próximo | O Mestre Aurélio (`BladeForgeTalk`, etapa `seek_hermit` em diante) comenta "um cavaleiro de longe que morou acima da minha cabana". O diário (`JournalArcs`) ganha um arco curto: *"Cabana sem trilha, acima do eremita."* |
| Chegar lá | próximo | Pegadas apagadas na neve saindo do pátio do eremita (decalque do terreno, sem colisão) e um estandarte rasgado preso num pinheiro: o jogador que explora acha sem marcador no mapa. |

## 2. Combate

- **Feito.** Parado, andar, correr e virar com os clipes do *Pro Sword and Shield Pack*. Três cortes em
  combo, com o pico da ponta medido no Dante: 0,60 s, 0,83 s e 1,40 s (o 3º é o pesado).
- **Feito: escudo.** Segurar mira levanta o escudo (*Block Idle*): o dano pela frente (cone de ~70°) cai
  para 15% e o Dante anda a 55% da velocidade.
- **Feito: chute.** Com o escudo erguido, o ataque vira o *Sparta Kick*: metade do dano e empurrão 3,5×.
  Serve para abrir a guarda e afastar um grupo.
- **Próximo: reação.** *Blocked Impact* tocado quando o escudo segura um golpe (o `shield_block_frame` já
  marca o quadro); *Unblocked Impact* quando apanha sem defender.
- **Próximo: golpes com as pernas nos punhos.** O catálogo tem *Mma Kick*, *Roundhouse Kick*, *Side
  Kick*, *Knee Jab*, *Flying Kick* e *Hurricane Kick*. Proposta: no 4º soco do combo dos punhos entra um
  chute alto (Roundhouse), e correndo o ataque vira *Flying Kick*. Mesmo caminho dos clipes `ual/Punch_*`.
  Precisa baixar e converter com `tools/retarget_mixamo_sword_to_dante.gd` (nova lista).

## 3. Melhorias visuais (upgrade)

Na Forja da Serra, como a faca, o machado e a katana (`BladeForge`), em três níveis:

| Nível | Visual | Efeito |
|---|---|---|
| Achada ("do gelo") | aço frio, escudo de madeira com cruz de ferro e umbo azul-gelo (modelo atual) | base |
| Afiação / Têmpera | lâmina polida com runas gravadas; aro de aço no escudo | +12% dano / golpe 8% mais curto (regra da forja) |
| Lendária "Coração da Geleira" | lâmina com veio azul emissivo e névoa fria saindo do escudo | +25% dano, escudo segura 90% (em vez de 85%) |

O modelo definitivo vem do Meshy (texto → 3D, remesh e textura; fluxo em `reference_meshy_workflow`):
espada de uma mão de ~92 cm e escudo redondo de ~68 cm. Ele substitui `SwordShieldModel.gd` mantendo a
origem no cabo e a face do escudo em −Z. Material novo entra no pré-aquecimento (`ForgePrewarm`).

## 4. Academia Ferro Velho (Harbor)

- **Feito.** Galpão de 11 × 8 m ao lado do Anchor Diner, com 8 aparelhos, cada um com seu clipe: saco
  de pancada, speedbag, rosca, flexão, esteira, corda, agachamento e abdominal. Uma série dura 8 s e sobe
  1 nível de **Força** (até +30% de dano corpo a corpo) ou **Fôlego** (até +8% na corrida), no máximo
  20 cada. Fica salvo em `world_state.gym`, validado no carregamento.
- **Interior vivo (esta rodada).** O saco de pancada balança quando o Dante treina nele, a bolinha do
  speedbag vibra, a esteira tem a lona correndo e há um halter na mão durante a rosca. Tudo é animação
  barata por `_process` só com o Dante treinando: nada de física.
- **Próximo.** Dois frequentadores (`BarPatronModel` com os clipes da academia) treinando em laço;
  professor que destrava o chute alto dos punhos depois de Força 10; fachada no kit pintado
  (`PaintedBarFacade`) e uma placa "MATRÍCULA ABERTA".

## Verificação

- `tests/test_sword_shield_gym.gd`: catálogo, prêmio da cabana pelo caminho real, save da academia e
  bibliotecas de clipes (51 verificações).
- `tools/probe_sword_shield_grip.gd`: pico dos golpes e orientação da lâmina e do escudo nos clipes.
- `tests/probe_gym_and_cabin_sites.gd`: chão da cabana (desnível de 0,20 m em 16 × 16 m).
- `tests/capture/capture_sword_shield_session.gd`: fotos no jogo (espada, academia e cabana).
- **Não verificado:** o 2º e o 3º golpe do combo na captura (o clique do roteiro não disparou), a
  sensação de jogo e o desempenho em release.
