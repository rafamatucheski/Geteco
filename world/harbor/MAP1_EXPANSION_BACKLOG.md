# Mapa 1 — Cobra, expansão oeste e corridas

Estado atualizado: o primeiro enclave jogável Ashbend Court foi integrado à
HarborPreview/HarborGame; detalhes e limites em `cobras/README.md`. As propostas
abaixo são o histórico do plano, não uma alegação de que toda a expansão,
progressão, persistência ou corridas já estejam implementadas. Não carregar este
arquivo como conteúdo de jogo.

## Decisões do usuário

### TODO — pedidos de 07/09/2026

Itens registrados para desenvolvimento; ainda não implementados por esta lista.

- [ ] **Interior da Ammu-Nation:** melhorar o ambiente atual ou criar um interior
  3D, com apresentação mais rica da loja. Definir a abordagem visual.
- [ ] **Armas secretas por pistas:** criar armas descobertas pela exploração,
  exigindo encontrar e reunir pistas até localizar a recompensa.
- [ ] **Área de desmanche de carros:** adicionar um local dedicado ao desmanche;
  definir funcionamento, recompensas e possível relação com os Cobras.
- [ ] **Diversidade visual dentro do mapa inicial:** diferenciar territórios e
  bairros por arquitetura, vegetação, terreno, pavimentação e ambientação.
  A variedade deve existir dentro do próprio mapa, além de contrastes entre
  mapas temáticos como deserto e gelo.
- [ ] **Imagem conceitual para discussão:** preparar uma proposta visual da
  diversidade do mapa inicial para o usuário avaliar antes de definir o cenário.
- [ ] **Minigame de entrega de pizza:** permitir ganhar dinheiro com entregas,
  usando os ganhos para comprar armas e coletes.
- [ ] **Missões de táxi:** transportar passageiros do ponto A ao ponto B;
  definir embarque, destino, conclusão e pagamento.

- Cada um dos cinco mapas terá uma gangue com personalidade própria.
- A gangue do mapa 1 é a Cobra. Criar seu covil na região indicada à direita
  da parte leste do distrito na imagem de referência.
- Podemos expandir à esquerda/oeste para desenvolver o Bairro 1.
- Incluir carros secretos mais velozes que o tráfego comum, também utilizáveis
  em corridas. Desenvolver a ideia de corridas como missões.

Referência espacial: imagem `codex-clipboard-d15e3981-b26f-4f97-bcba-652b637942bc.png`
enviada na conversa. O círculo fica à direita do núcleo leste, sobre a área azul.
É indicação de região, não coordenada autorada. Conferir terreno, água, limites
e acessos na cena antes de posicionar o covil. Não construir sobre água nem
eliminar costa/canal automaticamente para reproduzir o círculo.

## Propostas para aprovação — não são cânone fechado

## Adição aprovada: núcleo residencial e domínio territorial

O usuário pediu uma rua principal com término circular e casas ao redor,
inspirada na leitura espacial de Grove Street, sem copiar seu layout/identidade.
O território deve diferir do centro em casas, moradores, vegetação, rochas,
pavimentação e calçadas. A expansão ainda é um plano, não cenário construído.

Reação desejada: desconhecidos sem reputação atraem atenção se permanecerem;
moradores da gangue reclamam e exigem saída, com possibilidade de confronto.
Violência do jogador provoca reação e falas de expulsão. Separar moradores
civis de membros da gangue; residência no bairro não significa hostilidade.

Proposta de implementação a validar:
- Via de acesso curva chegando a um bolsão de retorno assimétrico; casas
  térreas/sobrados, quintais, oficina e passagens de pedestres pelos fundos.
- Identidade costeira periférica: afloramentos de pedra, árvores inclinadas
  pelo vento, capim e arbustos em grupos; calçadas contínuas porém remendadas,
  sarjetas, entradas de garagem e iluminação próprias, sem objetos na pista.
- Estados: observar → abordar → avisar para sair → confronto. Contar permanência
  apenas quando percebido, sem timer global que faça todos atirarem juntos.
- Sair durante aviso permite desescalar. Sacar/disparar/agredir pode acelerar
  a reação; não esperar o timer enquanto um membro sofre ataque. Avisos por
  voz/legenda com cooldown; aliados próximos respondem, não todo o mapa.
- Reputação altera tolerância e acesso, mas não torna o jogador imune a agredir
  membros. Missões, pausas e diálogos obrigatórios não devem criar armadilhas
  de hostilidade por tempo. Tempos e limiares ainda não definidos.
- Civis procuram abrigo; membros procuram cobertura e rotas existentes.
  Não gerar inimigos infinitos nem enxergar através de paredes.
- Validar passagem inocente, permanência advertida, retirada, agressão,
  reputação, save/load, desempenho e legendas PT-BR/English.

## Propostas anteriores

### Cobra

Organização territorial ligada a desmanches, veículos roubados e controle de
acessos ao porto. Identidade sugerida: verde escuro, cobre e símbolo de serpente;
evitar uniformizar todos os membros. Definir líder, linguagem, hierarquia,
relação com moradores, economia e modo de agir, não apenas cores e armas.

Covil sugerido: oficina/depósito industrial reaproveitado, pátio de veículos,
área de encontro e acesso de serviço. Deve parecer um lugar utilizado antes
de servir como arena. Prever chegada a pé e de carro, cobertura, saída e
circulação dos NPCs. Integrar ao arco do mapa 1 sem antecipar revelações do mapa 2.

### Bairro 1 a oeste

Criar transição entre comércio, ruas residenciais e oficinas, com becos úteis
e vias menores. Planejar conexões com a malha existente antes dos lotes.
Evitar expansão vazia: cada quadra deve servir à exploração, rotina ou missão.

### Carros secretos e corridas

Primeira proposta: três recompensas de exploração, com silhuetas e condução
distintas (compacto leve, cupê preparado e carro potente de maior porte).
Mais rápidos que os veículos comuns, mas com diferenças de frenagem, aderência
e resistência; não simplesmente multiplicar velocidade de todos.

Proposta de progressão: descoberta/recuperação de veículo → prova curta de
habilidade → corrida autorada com rivais. Não exigir um segredo para concluir
uma missão obrigatória sem oferecer um veículo competitivo acessível.
Não vincular todas as corridas à Cobra automaticamente; pode haver rivais independentes.

Missões fixas no quadro: manter as concluídas riscadas, sem geração infinita.
Checkpoints ordenados, largada, vitória/derrota, reinício, recompensa única e
persistência precisam ser implementados. Nomes e textos devem suportar PT-BR/English.

## Ordem e critérios de aceite

1. Resolver circulação pendente e validar acessos da região escolhida.
2. Aprovar planta do covil e personalidade da Cobra; definir limites do Bairro 1.
3. Construir uma expansão pequena funcional e auditar prédios, pistas, calçadas,
   água, entradas, caminhos de pedestres e rotas de emergência.
4. Entregar um carro secreto e uma corrida completos antes de expandir o catálogo.
5. Testar percurso real, sem teleporte; impedir atalhos que pulem checkpoints,
   pagamento duplicado e bloqueios permanentes causados pelos rivais.
6. Validar descoberta/pintura/reparo/save do carro sem clonagem por reload.
7. Medir performance com rivais, tráfego e polícia; não desligar sistemas
   silenciosamente para fazer o teste passar.

Nomes/identidades das gangues dos mapas 2–5 ainda precisam ser definidos.
Consultar o documento narrativo reservado para as restrições de spoilers.
