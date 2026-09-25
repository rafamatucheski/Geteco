# Histórico de versões

A versão aparece na marca d'água do canto superior esquerdo (`ui/BuildWatermark.gd`,
lida de `application/config/version` no `project.godot`), seguida do commit.

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
