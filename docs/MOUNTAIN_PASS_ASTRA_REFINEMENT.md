# Mountain Pass — revisão Astra, 07/09/2026

> Histórico da etapa isolada. Em 08/09 a conexão oficial foi implementada e
> `connect_to_harbor` passou a ser verdadeiro. Veja
> [a entrega e validação atuais](history/MOUNTAIN_PASS_HARBOR_INTEGRATION_2026-09-08.md).

A região permanece isolada. `connect_to_harbor` é falso por padrão.
Os relatórios anexados são contexto histórico: havia divergências de coordenadas,
conexões ativas e promessas de funcionamento não cobertas pelos testes.

## Aplicado
- Duas paredes físicas contínuas no túnel, sem fechar os portais.
- Zoom contextual de 2,5 no túnel, inclusive na câmera dinâmica do carro.
- Abrigo explícito nos interiores e túnel: partículas invisíveis, emissão suspensa,
  vento abafado e recuperação térmica. Retomada do clima ao sair.
- Faróis dos três veículos da serra projetados a partir das lentes reais dos modelos
  3D, em cada orientação, em vez das coordenadas fixas herdadas do cupê.
- Hipotermia desconta vida diretamente, respeitando morte e proteção de respawn.
  Nevasca aumenta drenagem; casaco reduz exposição em 80%, sem imunidade.
- Último Abrigo na saída do túnel: fachada 3D própria, balcão externo F, casaco
  de $650, compra única e propriedade incluída em serialize/restore do Player.
- Clareira preservada na geração de árvores; perímetro físico fechado da região.
- Leitura de altitude aproximada e sentido de deslocamento vertical. Isto não
  converte o terreno 2D em uma malha 3D com elevação física.
- Mara e Ivo: NPCs 3D conversáveis, dicas e conexão narrativa com o Porto.
- Composição inicial do covil Estação Zero no bunker existente, bandeiras,
  barricadas visuais e Whiteout dourado dirigível. Boss 2 ainda não implementado.
- Silhueta ilustrativa da futura cidade junto ao cume; ainda não é uma sequência
  cinematográfica nem uma passagem para um distrito novo.
- Cartões do chalé escondidos por padrão e menores, ativados por proximidade.

## Direção narrativa proposta
Após a queda dos Cobras, Dante descobre que os carregamentos continuam seguindo
para a estação meteorológica tomada pelos Lobos de Gelo. Mara oferece o primeiro
ponto de apoio; os trabalhadores indicam a subida. O chefe controla a passagem
com que a gangue financia sua operação. Após o confronto futuro, um mirante revela
a rodovia no deserto e a cidade das luzes. O deserto poderá concentrar corridas;
a próxima cidade é o destino penúltimo. Não foram criadas missões novas.

## Porta-malas e loadout — proposta, não implementado
Uma arma curta e duas principais equipadas; faca utilitária separada. Armas
compradas continuam pertencendo ao jogador. O porta-malas permite trocar o loadout
com o carro parado, próximo da traseira; bloquear durante perseguição/combate.
Não usar `weapon_inventory` como armazenamento temporário: ele representa posse.
Criar slots equipados separados e persistentes, filtrar roda e troca rápida pelos
slots e tratar pickups com escolha de substituição. Migrar saves antigos sem
apagar armas. Definir recuperação do arsenal se o carro for destruído antes de
atrelar a propriedade das armas a um veículo físico.

## Próximos trabalhos visuais e de progressão
O conjunto ainda precisa de uma revisão maior do terreno e do lago, elevação visual
coerente entre patamares, interior próprio do covil, confronto do Boss 2 e vista
panorâmica final. A loja tem balcão externo; não há interior de loja de roupas.
O Whiteout usa o modelo ártico com pintura e desempenho próprios; não é uma
carroceria inédita. Não apresentar essa primeira composição como região finalizada.

## Validação
Testes de integração da região, armas do chalé, regressão de câmera e teste novo
`test_mountain_refinement.gd`. Capturas via Forward+ na RTX 4060, revisadas para
achar e corrigir árvores sobre a loja e cartões do chalé abertos indevidamente.
O ambiente restringe o user://: não foi validada gravação real de save em disco;
o contrato de serialização/restauração do casaco é testado em memória.
O Godot emite aviso de certificados do sistema e há aviso de dois objetos no
encerramento do teste da região, também presente antes das últimas mudanças.


## Segunda etapa — Estação Zero e proporção dos interiores

Concluída a primeira versão navegável do interior próprio do bunker, com alojamento,
rádio, suprimentos e salão de comando. Entrada por E na fachada do bunker do cume;
F no rádio ou na mesa de rotas para informações narrativas. A área e o marcador
Boss2Anchor preparam o encontro futuro, mas não há boss nem missão implementados.

A câmera do bunker enquadra o cômodo e devolve o controle à câmera exterior ao sair.
Colisões dos móveis e paredes são projetadas a partir das medidas do modelo 3D.
A mesma correção de colisões foi aplicada ao chalé, com spawn e saída alinhados.
O gerenciador agora reconhece também InteriorExit, corrigindo as saídas existentes.

Após o feedback sobre tamanhos, a representação do jogador usa altura de referência
1,80 m na projeção da câmera do ambiente, inclusive variação de escala em perspectiva
no chalé. O sprite continua usando o rig animado existente; os pés são ancorados à
posição física. A resolução do render do jogador sobe temporariamente a 384² para
não ampliar o sprite de 128² com perda de nitidez. Escala, posição e resolução são
restauradas no exterior, inclusive quando um respawn dispensa a porta.

Efeitos novos: cinco pequenas chamas animadas e sete wisps discretos por emissor,
vapor leve na chaleira, luz quente oscilando suavemente e variação sutil na luz da
sala de rádio. Modelos, efeitos e SubViewports dos interiores desocupados param.
O Último Abrigo passou a oferecer o ponto de recuperação da região isolada.

Validação desta etapa: test_mountain_bunker, test_mountain_cabin_scale,
test_mountain_pass_integration, test_mountain_cabin_weapons_and_entrance,
test_mountain_refinement e test_dynamic_camera_finite, todos com zero falhas.
Os novos testes fazem travessias pelos sensores reais e movimento do collider do
jogador nos corredores, além de verificar restauração após saída e respawn.
Capturas revisadas: D:/geteco/mountain-bunker-interior.png e
D:/geteco/mountain-cabin-human-scale.png. Alguns testes ainda emitem o aviso de
dois objetos no encerramento; não houve erro de script nos logs finais.
