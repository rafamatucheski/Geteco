# Roteiro de teste no jogo — noite de 28/10/2026

Tudo aqui entrou com testes automáticos, mas ninguém viu no jogo. Marque o que viu e anote o que
estranhou (lugar, hora do jogo, o que fazia). Ordem pensada para um caminho só: Harbor, Vila Cobra,
deserto e serra. Os interruptores `GETECO_*` servem para comparar com o comportamento antigo.

## Harbor

- [ ] **Lastro** (porto, perto da estação): fachada pintada com porta dupla. Andar contra a porta: ela
  abre e você entra? Lá dentro: quadros, neon, estante, piso e parede de tijolo; os dois do balcão
  conversando; a atendente passando pano; música tocando. Jogar dardos e sinuca (E perto do alvo e da
  mesa). Na sinuca: toque curto na seta faz ajuste fino? O taco aparece? Encaçapar a branca tira 50?
- [ ] **Fagulha**: moldura nova dos fliperamas e os quatro jogos.
- [ ] **HUD**: aviso de rádio ao trocar de estação (centralizado, sem cobrir a legenda); legenda de
  fala não cobre munição nem dica de ação; avisos de skate e de corrida no lugar certo.
- [ ] **Polícia**: com 1–2 estrelas, viatura chega e os policiais descem rápido (≈1 s). Atirar num
  policial: ele recua, manca abaixo de metade da vida. Com 4+ estrelas o helicóptero circula, solta a
  equipe por corda depois de ~9 s e vai embora mais tarde.
- [ ] **Tiros e gritos**: som das variantes (pistolas, SMGs, escopetas); cada pessoa grita diferente;
  bala no corpo tem som.
- [ ] **Pneu**: atirar na roda de um carro parado; só aquele pneu esvazia, com estouro. Passar nos
  ferros da blitz.
- [ ] **Bombeiros**: explosão perto de rua; o fogo espera o caminhão chegar e a equipe apagar.
  Entrar no quartel: textura nova, dois caminhões e dois bombeiros de plantão.
- [ ] **Ambulância e IML (consertado hoje)**: ferir um pedestre sem matar e esperar a ambulância
  (12–22 s). Se ele morrer com o paramédico já atendendo, o corpo deve ficar até o carro preto do IML
  buscar. Quem morre sem atendimento continua sumindo em ~4 s (de propósito).

## Vila Cobra (à noite, 18 h–3 h)

- [ ] **Encontro de lowriders**: cinco carros, nove pessoas, trilha G-funk. Entrar num lowrider:
  Ctrl (L3) + W/S/A/D sobe cada lado, Espaço pula. Faltam ainda os sons de alívio e de batente.
- [ ] **Cobras no trânsito** em muscle cars e lowriders, com pintura de gangue.
- [ ] **Tuning**: saias, lábio, difusor e aerofólio num carro vivo; aerofólio no lugar certo.

## Deserto

- [ ] **Sede** (-420, -583): fachada de saloon pintada com placa "SEDE" na varanda; porta de saloon
  abre; interior (quadros, cabeça de boi, neon do cacto), clientes de frente para o balcão, jogos.
- [ ] **Pedreira mineradora**: entrar pelo portão da estrada, pela galeria e pelo pátio. O teste
  passa o carro e o caminhão gigante sem bater; o relato antigo (12/10) era "não está entrando".
- [ ] **Paredes invisíveis**: se bater em alguma, anotar o ponto exato (a sonda só achou e consertou
  o pátio do ponto Cobre).

## Serra

- [ ] Estação Zero, Cume Branco, lojas, cabanas e Posto Florestal com fachada pintada; interiores com
  textura; de dia e à noite.
- [ ] Snowmobile: modelo, pintura e som.

## Painel de desenvolvedor

- [ ] Interruptor "Câmera nas costas": câmera de perseguição em qualquer lugar; zoom e reset desligam.

## Se der tempo

- [ ] Abrir o jogo frio (primeira sessão do dia) e anotar se trava ~1 s nos primeiros segundos.

## Testes que só rodam com janela (o Claude roda, ~5 min, antes da bancada)

- `tests/test_umbra_expansion_session.gd -- --no-save`: atualizado para a porta de empurrar (13a084e4);
  a falha antiga em "walk to exit" era do teste.

## Depois de jogar: liberar o PC para a bancada fria (~1 h)

Export já pronto em `artifacts/perf-q10-20261028`. Antes: fechar o jogo e o editor, pausar o OneDrive,
monitor de 3440 ligado, nenhuma outra sessão rodando Godot. Aí é só avisar o Claude, que roda
`COLD_PART_A=shader COLD_PART_B=pipeline tools/bench/cold_ab.sh artifacts/perf-q10-20261028 q10 ABBAABBAABBA`
e lê o resultado com `tools/bench/cold_ab_spikes.py` (doc de desempenho §19).
