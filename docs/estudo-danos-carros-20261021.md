# Estudo: lataria deformável e peças destacáveis

Data: 21/10/2026. Escopo: estudar dano visível nas colisões do carro do jogador e dos demais veículos. Estado: proposta baseada no código atual; sem implementação de runtime, execução do jogo ou aprovação de performance nesta etapa.

Atualização: o protótipo autorizado depois deste estudo está registrado em [vehicle-breakaway-prototype-20261021.md](reviews/vehicle-breakaway-prototype-20261021.md), com modelos atendidos, limites e evidências. O texto abaixo preserva o diagnóstico da etapa de estudo.

## Recomendação

Evoluir a deformação já existente com **dano localizado por painel e peças destacáveis**. Uma pancada deve alterar a silhueta onde ocorreu, acumular dano e, quando suficientemente forte, deformar ou romper a fixação da peça atingida. O mesmo sistema deve atender veículos dirigidos pelo jogador, trânsito, carros estacionados, polícia e adversários das corridas, respeitando proteções de missão e diferenças entre modelos.

Exemplo desejado: Dante atinge o canto traseiro de outro carro. O canto dianteiro do seu carro amassa; a traseira atingida do outro também. O para-choque daquele lado pode ficar torto e depois cair. A porta do lado oposto permanece intacta. Ao roubar o carro atingido, ele conserva os mesmos danos.

Recomendo combinar deformação permanente da geometria, formas de dano preparadas por modelo e física de corpos rígidos para as peças já soltas. A decisão de arquitetura é uma recomendação; seu custo ainda precisa de protótipo e medição.

## Base encontrada no projeto

| Área | Situação observada por leitura | Consequência |
|---|---|---|
| Colisão entre veículos | `gameplay/street_physics/StreetPhysics.gd`, `_post_move` e `_stall_crash`, calcula aproximação relativa na normal e chama `receive_impact` nos dois carros. Há intervalo por par de veículos. | Já existe um ponto comum para alimentar dano dos dois envolvidos sem depender de quem dirige. |
| Entrada do dano | `scripts/Vehicle.gd`, `receive_impact`, encaminha para amassados, equipamento e vida. | Estender o evento existente evita um segundo sistema de colisão concorrente. |
| Amassado geométrico | `gameplay/vehicle_effects/VehicleBodyDents.gd` altera vértices, recalcula normais e tangentes e mantém a malha original para reparo. | A base já faz deformação real da malha renderizada. |
| Limitações atuais | Até 12 registros, deslocamento acumulado de até 0,34 m; profundidade inicial depende do dano à vida; direção cardinal inferida do ponto; região superior protegida. Só superfícies elegíveis de pintura são deformadas. | Não há resposta completa de capô, acabamento, vidro e fixações como conjunto. Ampliar somente o limite não resolve isso. |
| Exceções atuais | Amassados ignoram `bike_*`, `army_tank` e `biarticulated_510`; preparação tem teto de 60 mil vértices e ignora determinadas malhas. | Não afirmar que toda a frota já tem cobertura. Modelos especiais precisam de perfis próprios. |
| Colisor do carro | `Vehicle.gd` usa `CharacterBody3D` com caixa de colisão. O amassado não atualiza essa caixa. | Deformação visual já existe, mas não constitui simulação física de esmagamento estrutural. |
| Destruição final | `VehicleDamage.gd` cuida de desgaste, incêndio e carcaça; `VehicleWreckBody.gd` dá física à carcaça inteira. | Não encontrei nesses caminhos um sistema de capô, porta ou para-choque que se desprenda durante uma batida comum. |
| Portas | `VehicleDoorPresentation.gd` reutiliza folhas autoradas em modelos novos e recorta outros modelos ao preparar o embarque; `geometry_changed()` reaplica amassados. | O estado de uma porta arrancada precisa sobreviver à preparação de embarque e às reconstruções de geometria. |
| Persistência e reparo | `FleetState.gd` captura `body_dents`; há restauração no mundo, garagem e frotas específicas. `Vehicle.repair()` limpa os amassados. | Reaproveitar esse fluxo, acrescentando estado das peças com migração de saves. |
| Preparação dos modelos | `docs/vehicle-art-standard.md` prevê geometria preparada fora do runtime e agrupamento por material. Há modelos com portas autoradas e outros com partes agrupadas. | Preparar identificação de painéis nos autoradores; material de pintura não identifica uma peça mecânica. |

A força visual atualmente recebe o dano de gameplay: na colisão entre carros, `min(velocidade_de_aproximação × 0,5, vida_máxima × 0,12)`. Depois, a profundidade inicial usa `dano × 0,009`, com limites adicionais e resistência do veículo. Por exemplo, aproximação de 20 m/s produz 10 de dano antes da resistência e profundidade nominal de 9 cm, atenuada conforme a distância dos vértices. Isso sugere uma causa para pancadas pouco expressivas; a percepção na câmera do jogo ainda precisa de observação.

Há alterações locais de outras sessões em frota, portas, equipamentos e `StreetPhysics.gd`. Este estudo considera o conteúdo encontrado em disco e não altera esses arquivos. Uma implementação futura precisa revalidar esses pontos contra o estado então vigente.

## Comportamento proposto

| Intensidade | Lataria | Peças |
|---|---|---|
| Encostão ou raspada | Risco localizado e pequena marca quando houver energia suficiente. | Continuam presas; contato prolongado não gera uma peça nova a cada quadro. |
| Pancada média | Deformação localizada e permanente, claramente legível na câmera normal. | Para-choque desalinhado, capô vincado, retrovisor ou acabamento danificado conforme o contato. |
| Pancada forte | Região atingida comprimida; vincos e desalinhamento coerentes entre painéis vizinhos. | Peça perde fixações, pode oscilar por pouco tempo e se desprender. |
| Repetição na mesma região | Aprofunda o dano até o limite do perfil; preserva o restante do carro. | Uma peça já arrancada não reaparece nem se solta outra vez. |

Os limiares devem ser calibrados no jogo. Separar **integridade mecânica**, que determina continuar funcionando/incendiar, de **dano visual e integridade das fixações**. Assim a carroceria pode reagir de forma expressiva sem tornar todo impacto fatal. Blindagem e proteções precisam de regras explícitas nas duas dimensões.

Rodas arrancadas e suspensão quebrada ficam como evolução posterior: exigem alteração de dirigibilidade, IA e recuperação. A primeira entrega deve concentrar-se em lataria, para-choques, capô, porta-malas, retrovisores e portas quando existentes no modelo. Não se limita a carro de jogador.

## Arquitetura proposta

### 1. Um evento de impacto compartilhado

Ampliar a entrada atual com ponto, normal, velocidade relativa antes da resposta, intensidade física estimada, identificador do contato e origem. Converter ponto e direção para o espaço local de cada carro. Preservar a deduplicação por par, intervalos e proteções existentes.

Para resposta visual, usar aproximação normal e massa/resistência do perfil como aproximação de energia; não tratar a massa relativa da dirigibilidade como quilogramas reais sem conferir suas unidades. Separar raspada tangencial de impacto frontal. Conservar o balanceamento de vida até existir justificativa de gameplay para mudá-lo.

Carro contra carro, parede e objetos sólidos devem alimentar esse mesmo contrato. Em `Vehicle.gd` há um caminho específico para parede; em `StreetPhysics.gd` há objetos que recebem/aplicam `receive_damage` sem ponto de amassado. Esses produtores precisam ser mapeados, evitando dano duplicado.

### 2. Deformação por região

Evoluir `VehicleBodyDents` para conhecer os painéis e seus limites, usando máscaras/vínculos preparados por modelo. Manter a malha de repouso compartilhada; criar estado e geometria exclusivos apenas nos carros danificados.

Combinar amassado procedural no ponto real com formas autoradas para grandes dobras: capô arqueado, canto frontal comprimido e traseira recolhida. Essas formas ajudam a controlar o aspecto metálico de modelos com poucos vértices. Acrescentar subdivisões apenas onde a malha não permite a dobra desejada; não aumentar indiscriminadamente toda a frota.

A peça mantém costuras, espessura aparente, pintura, adesivos, acabamento e normais coerentes. Vidros e lentes não devem esticar como chapa. A região atingida deve deformar sem puxar o lado oposto ou abrir fendas acidentais na cabine.

`ArrayMesh` oferece construção de geometria por arrays e suporte a blend shapes. A escolha entre atualização de buffers, reconstrução parcial e formas autoradas depende do formato dos recursos e de medição no projeto. Não há ganho de FPS presumido por trocar a API. [Documentação oficial de ArrayMesh](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html).

### 3. Peças e fixações

Criar um perfil por modelo/família, com identificadores estáveis de peça, geometria correspondente, pivô, zona de contato, resistência de fixações, deformação permitida, colisor simples e aparência interna exposta. Nomes como `bumper_front`, `hood` e `door_left` seriam contrato novo, não APIs já existentes.

Preparar essas informações nos autoradores/exportação. Evitar recortar uma malha inteira durante uma colisão. Manter agrupamento de partes estáticas quando possível, com versões preparadas da carroceria sem os painéis destacáveis. Comparar o custo de peças separadas desde o início com o de substituir uma representação compacta no primeiro dano; escolher no protótipo, sem fabricar todas as combinações possíveis de carroceria.

Estado por peça: **íntegra → amassada → fixações comprometidas → destacada**. Nem toda peça precisa passar por todos os estágios. Uma oscilação curta pode ser calculada apenas enquanto a peça ainda está presa e se move; juntas físicas permanentes em toda a frota não são necessárias para a primeira versão proposta.

Ao romper, a peça sai com sua deformação e pintura atuais. Usar `RigidBody3D` para queda, giro e colisão com o cenário, herdando a velocidade do carro e recebendo um impulso limitado. O motor já oferece impulsos e suspensão de corpos em repouso. [Documentação oficial de RigidBody3D](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html).

Um gerenciador de destroços do mundo deve possuir a peça solta, para ela não acompanhar o transform do carro nem desaparecer por engano quando o tráfego o descarregar. Manter relação de propriedade para limpeza e reparo, com referências que não retenham o veículo indefinidamente.

### 4. Colisão, ciclo de vida e persistência

- Usar colisores simples preparados para destroços; impedir sobreposição inicial que lance o carro ao nascer a peça. Definir máscaras para evitar que um fragmento cosmético paralise o trânsito ou gere dano/crime em cascata.
- Vidros e fragmentos pequenos podem usar partículas; painéis reconhecíveis recebem corpo físico. Peças devem repousar sobre a pista correta, inclusive em rampas e pontes, e não atravessar o chão.
- O casco dirigível pode conservar um proxy estável na primeira fase, desde que não deixe colisões invisíveis perceptíveis. Deformações grandes exigem ajuste limitado de proxies por região, validado separadamente da malha; não reconstruir colisão triangular complexa a cada pancada.
- Porta ausente precisa continuar ausente ao entrar, sair, trocar de motorista ou construir a cabine. Adaptar a apresentação do embarque sem criar bloqueio permanente para o jogador.
- Equipamento deve ler o estado da peça: farol quebrado ou arrancado não pode continuar iluminando pelo ponto antigo. Hoje `VehicleEquipment.snapshot()` grava liga/desliga de farol e sirene, mas não `broken_left/right`; integrar persistência de dano de lentes ao contrato novo.
- `repair()` restaura geometria, fixações e equipamentos e resolve destroços associados sem duplicar peças. Respeitar as regras da garagem e de seus personagens.
- Salvar versão do esquema, amassados e estado por identificador de peça no mesmo registro do veículo. Save antigo assume peças íntegras quando não há dados novos. Retomar sem reproduzir impulso, som ou novo desprendimento.
- O estado de peça ausente persiste mesmo se o fragmento de chão expirar. Recomendo que fragmentos temporários não precisem ser salvos; a ausência no carro precisa ser salva. Isso deve ser regra explícita de produto.
- Troca de região, despawn, pausa, morte/resgate, reparo e destruição final precisam cancelar filas/animações e limpar referências. A carcaça final não pode reconstruir peças já ausentes.

## Alternativas consideradas

| Abordagem | Utilidade | Avaliação para este projeto |
|---|---|---|
| Só riscos e normal maps | Detalhe superficial econômico a verificar. | Complemento: não muda a silhueta nem solta peças. |
| Só aumentar a deformação atual | Protótipo rápido de intensidade. | Insuficiente: não define fixações, painel, interior exposto ou dano consistente em acabamento. |
| Deformação localizada + formas autoradas + peças físicas | Acumula dano, muda o volume e permite desprendimento mantendo a direção atual. | Caminho recomendado para prototipar. |
| Carro completo com simulação contínua de estrutura deformável | Pode representar mudanças estruturais e de dirigibilidade mais amplas. | Projeto muito maior; não é necessário para validar primeiro a experiência pedida. |

O `SoftBody3D` documentado pelo Godot é um mecanismo genérico de corpos deformáveis, com compromisso entre subdivisão, precisão e custo. A documentação não fornece um sistema pronto de plasticidade automotiva, fixações e persistência para esta frota. Minha recomendação de adiar essa abordagem resulta do escopo e da arquitetura atual, não de um benchmark demonstrando inviabilidade. [Documentação oficial de SoftBody3D](https://docs.godotengine.org/en/stable/tutorials/physics/soft_body.html).

As referências acima são documentação oficial `stable` consultada em 21/10/2026. Antes de implementar, conferir as APIs efetivas no Godot 4.7.2 .NET instalado; os links não substituem validação nessa versão.

## Sequência de implementação sugerida

1. **Protótipo vertical:** um carro de passeio do catálogo, com os dois para-choques e capô preparados. Testar várias instâncias do mesmo modelo e colisão jogador/trânsito, demonstrando que o dano é individual. Medir desde esta etapa, inclusive a primeira colisão.
2. **Integração completa do modelo:** completar peças previstas, reparo, save/load, roubo, embarque, troca de região, equipamento e carcaça. Produzir vídeo no enquadramento normal do jogo.
3. **Frota por famílias:** adaptar hatch/sedã, esportivo, picape/SUV, van e veículos pesados; cobrir polícia, corridas e estacionados. Manter inventário explícito de modelos convertidos e pendentes. Um modelo demonstrado não aprova toda a frota.
4. **Exceções:** tratar blindados, ônibus articulado e motos com comportamento próprio, se incluídos no escopo final. Não aplicar peças ou deformações de um sedã onde não fazem sentido.

O esforço principal está na preparação e revisão dos modelos e na consistência dos estados, além do algoritmo. A quantidade definitiva de peças por modelo e o prazo dependem desse inventário; não foram estimados como se toda a frota tivesse a mesma estrutura.

## Validação e orçamento antes da entrega futura

Estado atual inspecionado: projeto declara Godot 4.7/C#, Forward Plus, física `GodotPhysics3D`, viewport base 1280×720 e limite de 60 FPS. Isso descreve configuração em arquivo, não ambiente renderizado medido nem garantia de 60 FPS. Usar Godot **4.7.2 .NET** e compilar `Harbor.csproj` antes de executar os testes.

Reaproveitar, após conferir o contrato de cada teste: `tests/test_vehicle_body_dents.gd`, `test_vehicle_body_dents_incremental.gd`, `test_vehicle_crash_damage.gd`, `test_vehicle_impact_momentum.gd`, `test_vehicle_wreck_collision.gd`, os testes de portas/equipamento e os testes de garagem pertinentes. Acrescentar casos duráveis para ruptura única, isolamento entre duas instâncias, restauração sem recriar peças, reparo e limpeza de destroços.

| Cenário | Critério necessário |
|---|---|
| Batidas frontal, traseira, lateral e oblíqua, leves/fortes/repetidas | Dano localizado nos dois carros; severidade coerente; sem dano multiplicado pelo contato contínuo. |
| Jogador, trânsito, estacionado, viatura e adversário | Mesmo contrato de dano; só origem/IA mudam; proteções explícitas preservadas. |
| Modelos iguais com pinturas diferentes | Bater em um não modifica malha, cor ou peças do outro. |
| Peça torta e depois arrancada | Continuidade visual, pintura correta, vão acabado, queda física sem atravessar pista nem impulsionar o carro artificialmente. |
| Roubo, embarque, reparo, save/load isolado e transição de região | Estado persiste; nada ressurge antes do reparo; controle e câmera recuperam corretamente. |
| Noite/chuva e farol atingido | Dano legível, iluminação coerente e sem piscadas involuntárias; aplicar `validar-iluminacao` se alterar esse sistema. |
| Engavetamento durante gameplay e posterior dispersão | Limites de trabalho e destroços respeitados; memória/entidades se recuperam; sem filas de dano acumulando indefinidamente. |

Comparar baseline e candidato em `Main.tscn` real renderizada, com mesma máquina/GPU, versão, renderer, resolução, qualidade, câmera, rota, clima, população e save isolado. Usar alvo provisório de 60 FPS/16,67 ms; registrar configuração normal e diagnóstico sem limitador quando necessário. Separar aquecimento, primeira batida, impactos seguintes e recuperação. Amostrar pelo menos 30 segundos por cenário crítico, com frames brutos, FPS por frames/tempo, p50/p95/p99, máximo e contagem acima de 33,3/66,7 ms. Aumento acima de 5% em p95/p99 exige confirmação finita equivalente, sem mudar o critério depois.

`tests/measure/measure_vehicle_dents.gd` já oferece um diagnóstico na cena real com população, mas fixa câmera/carro e injeta impactos. Reutilizar para localizar custos; complementar com colisões durante condução e engavetamento reais. Não aprovar por headless ou screenshot.

Preservar a economia atual de trabalho por evento. Os comentários de `VehicleBodyDents.gd` registram hitches históricos na leitura de arrays de malha; são um alerta para preparar/cachear dados fora do impacto, não uma medição atual. Definir limites de corpos ativos, animações e reconstruções a partir do protótipo. Ao atingir o orçamento, manter o estado de dano e a silhueta; reduzir primeiro simulação transitória de fragmentos distantes. Não esconder a peça ausente ou curar NPCs para economizar.

## Resultado deste estudo

Viabilidade arquitetural favorável, com uma base já existente para amassado nos dois participantes. Recomendação: protótipo de dano por painel e desprendimento compartilhado, seguido da adaptação explícita da frota. Não houve mudança de gameplay, execução de testes ou benchmark nesta etapa documental. Qualidade visual, sensação das colisões e performance continuam sem medição.
