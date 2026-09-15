# GETECO — Produção da campanha, tuning e testes

Plano de implementação, 10/09/2026. Esta entrega criou documentação; os itens abaixo são trabalho futuro salvo quando identificados como base documentada existente.

Referências: [bíblia](CAMPAIGN_STORY_BIBLE.md), [missões](CAMPAIGN_MISSIONS.md), [arquitetura atual](ARCHITECTURE.md).

## 1. Ordem de produção recomendada

1. **Protótipo completo do mapa 3:** entrada sem Monaliza → revenda/foto → compra → contato sobre Biela → prisão compacta → perseguição → galpão → oficina → instalação → volta de teste. Geometria provisória e um carro inicialmente.
2. **Persistência da perda e recuperação:** validar sequestro da Monaliza entre mapas, retenção de carga e recuperação única. O protótipo pode iniciar num snapshot após a corrida, sem fingir que M11 já está pronta.
3. **Tuning de um carro de ponta a ponta:** visual, condução, compra, retirada, save/load, preview. Só depois ampliar para três modelos.
4. **Deserto e recuperação de Cromo:** construir o antes/depois que dá sentido emocional ao protótipo.
5. **Cenas e missões de Helena em Vegas:** testar se jogadores lembram de objetivos e personalidade dela antes de produzir o final.
6. **Clímax com atores provisórios:** testar os quatro estados e o pós-game antes de cinematics caras.
7. **Arte, cinematics, áudio e balanceamento:** substituir provisórios após validar fluxo. Nenhuma fila exige produzir cinco mapas inteiros antes de jogar uma missão.

O pedido de “coisas em paralelo para testar” é atendido por frentes independentes de produção abaixo. Não houve execução nem delegação de agentes nesta entrega.

## 2. Locais necessários

| Local | Etapa | Escopo mínimo | Reutilização/estado |
|---|---|---|---|
| Harbor/Westgate/bairro Cobra | 1 | Base existente; novas pistas pontuais | Preservar missões e geografia atuais |
| Posto do circuito | 2 | Área social, pátio de largada, rádio | Antes e depois do golpe; posto de abandono é setor esvaziado |
| Circuito do deserto | 2 | Laço curto, reta, bifurcação autorada, pátio final | Qualificação e prova principal compartilham malha |
| Parada de carga | 2→3 | Abrigo, caminhão e embarque | Transição curta para não caminhar outro mapa |
| Revenda Batista | 3 | Pátio para três carros, escritório pequeno, espaço para CGI | Loja permanente de Joel Batista |
| Depósito de Célia | 3 | Uma sala e baia de inspeção | Missão de contato e cadeia de ferramentas |
| Penitenciária Pedra Seca | 3 | Exterior distante, anexo com três áreas, pátio e saída | Não modelar toda a prisão; ala do flashback pode compartilhar kit |
| Corredor da perseguição | 3 | Avenida, acesso industrial, via de busca, rotas de retorno | Teste de tuning e futuras perseguições |
| Galpão Oficina Livre | 3 | Baia, bancada, elevador, portão, área de conversa | Três estados: vazio, montagem, operação; base persistente |
| Complexo de Cromo | 3 | Pista reaproveitada, pátio, exposição, sala documental | M19 e M20 usam horários e portas diferentes |
| Garagem de apoio em Vegas | 4 | Baia de serviço e canto de descanso | Interface da oficina de Biela sem teletransportar Biela para todas as cidades |
| Mirante de Vegas | 4 | Trecho de rua e parada com vista | Romance e passeio opcional, sem mapa gigantesco de Strip |
| Casa de retenção | 4 | Dois cômodos e saída | Missão de Lia; não reutilizar como casa de Helena |
| Cassino Vilar | 4 | Fachada marcante, serviço, arquivo, garagem | Cenário compacto de boss, não cassino inteiramente simulável |
| Abrigo de Célia | 4/5 | Entrada segura e espaço de conversa | Evacuação e pós-game; separado da oficina foragida |
| Distrito de Lastro | 5 | Alojamentos, comércio, oficina antiga, vias industriais | Estados pós-game via elenco, placas e estabelecimentos |
| Centro de despacho do Pacto | 5 | Pátio, combate, sala final, duas saídas | Base comum dos quatro finais |
| Sala de visitas | Pós | Pequeno interior com elenco específico | Vicente preso em F2/F4; jamais visita na prisão onde Biela continua procurado |
| Memorial/cemitério | Pós | Pontos específicos em estrutura compatível | Reusar kit existente após inspeção; não afirmar já integrado |
| Destino do casal | Epílogo | Pequena parada costeira | Mesmo cenário em versões de presença/ausência |

## 3. Sistema de tuning

### Modelos e catálogo inicial

Três modelos fictícios de trabalho: hatch Risco (leve e ágil), cupê Vértice (potente e mais exigente), sedã Linha (estável e equilibrado). Quarto modelo antigo, Bruto, entra depois se o custo permitir. Nomes/modelos precisam de revisão visual; não são carros já criados.

Cada carro tem catálogo próprio e pontos de encaixe. O jogador pode montar estilo sem perder performance por escolher um aerofólio que gosta. Visual não altera física nesta primeira versão, exceto regulagem limitada de altura, cujo intervalo deve manter dirigibilidade e colisões corretas.

| Categoria | Primeira versão por carro | Comportamento |
|---|---|---|
| Aerofólio | Original/sem peça e 3 opções | Mesh com pontos de fixação específicos |
| Para-choque dianteiro | Original e 2 opções | Pode ser instalado separado do kit |
| Para-choque traseiro | Original e 2 opções | Compatibilidade registrada por modelo |
| Saia lateral | Original e 2 opções | Par esquerdo/direito como uma compra |
| Capô | Original e 1 opção | Pintura coerente e sem recorte na carroceria |
| Rodas | 4 desenhos compartilháveis | Offset/escala aprovados por modelo |
| Pintura | Paleta e cores personalizadas | Preservar no save e no reparo |
| Altura | 3 posições seguras | Limites fixos por carro; sem controle ilimitado |
| Motor | Original + 3 estágios | Ganhos de potência calibrados no controlador |
| Turbo | Original/sem kit + 3 estágios compatíveis | Entrega progressiva de torque; áudio combina com comportamento |
| Transmissão | Original + 3 estágios | Troca e relação curta/equilibrada/longa, com escolhas simples |
| Pneus | Original + 3 estágios | Aderência e resposta, sem aderência infinita |
| Freios | Original + 3 estágios | Distância de frenagem perceptível |
| Suspensão | Original + 3 estágios | Resposta e estabilidade nos limites da física atual |

Escopo adiado: editor livre de adesivos, neon completo, danos individuais de cada acessório, troca irrestrita de motor e física de aerodinâmica. Turbo mecânico não é nitro. A documentação histórica registra nitro desativado; não reativá-lo incidentalmente por inspiração em NFS.

### Experiência da garagem

Carro central com câmera giratória em preview, categoria e comparação visível, peças provisórias antes de confirmar compra, preço total e saldo. Cancelar restaura o estado original. Confirmar desconta uma vez e instala atomicamente. Peças já compradas podem ser reinstaladas sem nova cobrança. Customização não consome munição nem muda posição do carro no mundo.

Mostrar aceleração, velocidade, aderência e frenagem com descrições curtas. Números são estimativas calibradas, não estatísticas inventadas sem relação com a condução. Volta de teste próxima permite comparar e desfazer ajuste de regulagem. Manter pintura e identidade exclusiva da Monaliza até definir seu catálogo próprio.

### Economia e propriedade

- Crédito inicial explícito cobre carro básico, revisão e primeira preparação de M17; testar com saldo zero e saldo negativo legado, se existir.
- Primeira prova não exige compra máxima. Corridas secundárias financiam variedade, não desbloqueio obrigatório de história.
- Carro comprado recebe ID persistente e garagem. Roubar carro comum continua permitido; roubo não concede automaticamente catálogo/permanência de carro comprado.
- Catálogo da Monaliza é separado; recuperar o carro não transfere upgrades do substituto por magia.
- Porta-malas de carro comprado permite capacidade definida e transferência física de loadout. Armas pessoais continuam pessoais; carga da Monaliza sequestrada fica inacessível e retorna na recuperação.
- Antes da tomada, missão garante um equipamento pessoal mínimo na transição; não apagar inventário do personagem. Registrar esse contrato na UI da sequência.
- O jogador escolhe qual carro dirige ao trocar de região; o outro permanece guardado. Nada de cópias espalhadas em cada oficina.

## 4. Frentes paralelas de protótipo

| Frente | Entrega isolada | Dependência/contrato | Critério de aceite |
|---|---|---|---|
| A — Revenda e foto | Cena pequena, três escolhas provisórias, compra persistente | Recebe saldo/crédito e emite ID do carro | Compra única; foto tem data coerente; continuar sem dinheiro é possível |
| B — Prisão e escolta | Anexo provisório, Biela, portões, alarme e embarque | Recebe missão iniciada e entrega Biela no veículo | Biela não prende em portas; falha/retry consistente |
| C — Perseguição | Corredor com pressão em etapas e busca | Começa com fugitivo embarcado; emite despistado | Intensidade legível sem spawn diante da câmera; destino seguro não acessível sob observação |
| D — Tuning | Um carro, uma peça visual por slot e pacote funcional | Interface estável de atributos/encaixes | Preview = instalado = recarregado; condução muda de forma perceptível |
| E — Narrativa e finais | Cenas textuais e estados dos quatro resultados | IDs de missão e personagens; nenhum asset final necessário | Todos os caminhos chegam ao pós-game correto com Dante vivo |

Integração: uma pessoa/frente responsável pelos contratos compartilhados de save, veículos e missão. Protótipos não editam esses contratos de maneiras divergentes. Trabalhar em cenas isoladas até a interface estar definida; não criar agentes automaticamente a partir desta tabela.

## 5. Estados e persistência propostos

Namespaces abaixo são desenho de dados, não APIs existentes. Adaptar a CampaignState e SaveManager depois de ler o código atual.

```text
story.version
story.completed_missions[]
story.current_checkpoint
story.known_clues[]                 # apenas conhecimento de Dante
story.monaliza_status               # available / seized / recovered
story.monaliza_escrow               # estado preservado durante sequestro
story.biela_status                  # imprisoned / escort / safe
story.workshop_stage                # closed / setup / open
story.preparations                  # evacuation, custody, extraction
story.ending                       # unset / F1 / F2 / F3 / F4
story.vicente_status                # active / arrested / dead
story.helena_status                 # active / dead
story.postgame_completed[]
owned_vehicles[id].model
owned_vehicles[id].owned_parts[]
owned_vehicles[id].installed_parts
owned_vehicles[id].performance
owned_vehicles[id].paint
owned_vehicles[id].stored_loadout
owned_vehicles[id].garage_or_world_location
```

Invariantes: `seized` bloqueia recuperação automática e GPS; só há uma Monaliza; compra e recompensa são transações únicas; Helena morta não participa de chamadas novas; Vicente morto não aparece em visita; oficina continua operante em todos os finais; F4 exige preparações e mantém ambos vivos. Ao migrar save antigo, default preserva a campanha existente e não marca carro como sequestrado por ausência de campo.

A campanha Cobra atual cancela tentativas ativas ao carregar. Checkpoints propostos para missões longas exigem extensão consciente desse contrato; não assumir restauração intermediária já existente. Guardar snapshots em fronteiras autoradas, não serializar toda IA no meio de tiroteio para a primeira versão.

## 6. Matriz de testes a executar na implementação

| Teste | Cenário | Resultado esperado |
|---|---|---|
| T01 | Ganhar a corrida armada antes do evento | Manipulação ainda ocorre; missão conclui sem repetir derrota |
| T02 | Carregar logo após perder Monaliza | Sem instância, marcador ou resgate automático; inventário preservado no estado sequestrado |
| T03 | Ir de mapa 2 ao 3 sem carro | Viagem de passageiro funciona; compra só no destino |
| T04 | Comprar com saldo zero e confirmar duas vezes | Uma compra válida, uma cobrança, um veículo |
| T05 | Cancelar test drive/preview de tuning | Nenhuma perda de dinheiro/peça ou clone |
| T06 | Escolher cada modelo | Missões de extração e corrida continuam possíveis; assentos de missão garantidos |
| T07 | Biela alcançar porta estreita e embarque | Sem bloqueio permanente; recuperação local de pathing sem teleporte visível |
| T08 | Biela/Dante morrer durante resgate | Retry de checkpoint sem cobrar/recompensar duas vezes |
| T09 | Ir direto ao galpão perseguido | Entrada segura negada com orientação; perseguição pode ser resolvida |
| T10 | Despistar e reabrir o save | Oficina progride uma vez e não regenera perseguição indevida |
| T11 | Equipar todas as peças compatíveis | Sem interseções graves, mesh flutuante ou conflito com portas/rodas |
| T12 | Medir carro original e preparado | Diferenças repetíveis em aceleração, frenagem e curva; nenhuma combinação quebra estabilidade |
| T13 | Recuperar Monaliza dirigindo carro preparado | Ambos persistem, carga retorna uma vez, GPS aponta só carro correto |
| T14 | Interromper chamada por combate | Conteúdo essencial disponível depois; sem conversa sobreposta à ação |
| T15 | Concluir cada final e carregar | Mortos, presos, contatos e missões correspondem à matriz |
| T16 | Tentar F4 sem preparação | Alternativa indisponível com motivo e possibilidade de voltar antes de iniciar |
| T17 | Completar preparações com escolhas de diálogo diferentes | F4 continua disponível; nenhum medidor oculto de romance |
| T18 | Rejogar final em seleção de capítulo | Save canônico de pós-game não é contaminado |
| T19 | Abrir save anterior à expansão | Harbor, carros e missões existentes permanecem consistentes |
| T20 | Medir perseguição no hardware alvo com renderização real | Definir orçamento de viaturas/atores por evidência; não prometer FPS com teste headless |

Polícia numerosa não significa centenas de agentes ativos. A arquitetura documentada possui pool limitado de emergência; o espetáculo precisa de encontros em etapas, som, pontos de cerco e distâncias de renderização. Inspecionar código e medir antes de ampliar pool global. A mesma autoridade deve controlar polícia de missão e ambiente para evitar duplicação de perseguições.

## 7. Sessões de teste humano

Primeira sessão: pessoa nova joga compra → prisão → oficina com marcadores provisórios. Observar onde se perde, se entende quem Biela é, por que o resgata e por que não pode entrar no galpão perseguida. Perguntar que diferença sentiu no carro antes de mostrar as barras.

Segunda sessão: perda e recuperação. Verificar se a armadilha parece parte clara da história e se o jogador criou apego ao substituto. Se todos abandonam o novo carro ao recuperar a Monaliza, revisar identidade e diferenças, sem enfraquecer artificialmente a Monaliza.

Terceira sessão: cenas de Vicente/Helena e final provisório. Pedir que o jogador explique a injustiça original, os crimes atuais e o risco de cada escolha. Se não consegue, revisar apresentação antes de adicionar mais documentos e personagens.

Registrar duração por missão, retries, tempo de deslocamento sem evento, compras, chamadas ignoradas e motivo declarado da escolha final. Metas de 5–7 horas e contagem de missões só sobrevivem se a experiência justificar. Missões tranquilas são ritmo intencional; repetição e espera obrigatória não são profundidade.

## 8. Limite desta entrega

Foram compilados e autorados história, cronologia, elenco, missões, locais, estados e critérios de teste. Não foram criados mapas, modelos, CGI, tuning ou missões executáveis. As bases existentes citadas vieram da documentação local, não de uma auditoria de runtime realizada nesta sessão.
