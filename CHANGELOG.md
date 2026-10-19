# Histórico de versões

A versão aparece na marca d'água do canto superior esquerdo (`ui/BuildWatermark.gd`,
lida de `application/config/version` no `project.godot`), seguida do commit.

## Não lançado — 18/10/2026 (sobre a 0.3.3)

As versões 0.3.1 a 0.3.3 não foram registradas aqui; o histórico delas está no `git log` e no
board (`docs/painel-geteco.html`). Esta entrada cobre a revisão cruzada de 18/10.

**Save**
- Slot com um bloco opcional quebrado aparece como "Recuperável" no Carregar; só a escolha
  aplica e as cópias originais ficam ao lado (`.pre-recovery`).
- Salvamento desligado mostra o motivo no canto em vez de parar calado.

**Jogo**
- Morte no Harbor volta pelo Bay Medical, prisão pela delegacia; 10% do dinheiro (teto
  R$ 2.000) e a prisão leva a munição carregada.
- A história do Harbor paga R$ 21.500 e libera as faixas melhores do guincho (R$ 600 a 2.400);
  carro-forte R$ 20.000. Saves antigos recebem o bônus das missões já feitas.
- Diário (J) com todas as histórias em andamento, de qualquer região.
- Crime igual por arma e atropelamento; pescador, convidado e moradores contam como pessoa.

**Mundo**
- Cavernas do deserto pagam uma vez e de verdade; foras-da-lei, bandidos, moradores e o
  caminhão do assalto aparecem na hora a 60 fps.
- Serra: viagem e resgate não ficam mais presos no tabuleiro da ponte.

**Desenvolvimento**
- `tools/run_core_suite.sh` (fast/full) pela fila, com preferências isoladas por teste.
- Valores de dinheiro ajustáveis em `data/catalogs/EconomyBalance.gd`.
- 109 arquivos de código morto removidos (inventário antigo, menu_presentation, aberturas
  antigas, protótipo sandbox).

## 0.3.0 — 25/09/2026

Tudo o que entrou desde a promoção da V2 à raiz do repositório (24/09).

**Mundo e clima**
- Mar do Harbor com ondas e brilho; espuma nos pilares da ponte; altura visual da
  ponte sobre o mar.
- Montanha: chão com textura procedural e relevo, capim 3D, trilha de pedestre,
  postes de luz, lago alpino em bacia de verdade.
- Chuva com poças dinâmicas da V1; chafariz do hospital com água de verdade.
- Ursos da V1 de volta, com investida, filhotes e sons.
- Noite com fases da lua (ciclo de 8 dias de jogo) e postes gerados nas calçadas.

**Trânsito e veículos**
- Semáforo com fases reais (verde, amarelo e vermelho geral) e PARE onde não há
  poste.
- O trânsito contorna obstáculo parado (viatura, carcaça, fila travada), não
  bloqueia o cruzamento com a saída ocupada, e carro travado sai de cena fora
  da câmera.
- Roubar carro e moto do trânsito em movimento; embarque por porte do veículo.
- Explosão, batida e carcaça com colisão própria; fogo procedural.
- Embarque sem deslizar; streaming de carros sem queda na borda das células.

**Polícia e emergência**
- Camburão tático, reforços até seis estrelas, roubo de viatura com saída dos
  ocupantes.
- Bombeiros com hidrante e jato d'água que apaga fogo; caminhão chega rápido.

**Dante e combate**
- Locomoção armada direcional, golpes com dano no contato, braços sem salto.
- Moto com as mãos nas manoplas reais.

**Lugares**
- Entrar e sair caminhando, com porta física e zoom, em 25 acessos (banco,
  Maciota, Garagem do Chefe, bombeiros, chalés, lojas, residências, esgoto,
  porão, caverna).
- Ammu-Nation: bancada legível, acessórios corretos e reentrada sem travar.
- Porto: frete de entrega, segurança que autoriza visitante, trabalhadores que
  fogem de tiro.

**Interface**
- Marca d'água de build alpha com versão e commit.
- Cursor próprio nos menus, oculto durante o jogo.

**Pendências conhecidas:** a queda original do veículo abaixo do mapa não foi
reproduzida; a primeira entrada na Ammu-Nation ainda tem um quadro residual de
~60 ms; FPS não certificado nesta versão. Relatórios em `docs/video-review-*`.

## 0.2.0 — 24/09/2026

V2 promovida a jogo principal na raiz do repositório. A V1 fica no ramo
`v1-legado` e na tag `v1-final`.
