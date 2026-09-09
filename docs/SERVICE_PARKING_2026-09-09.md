# Estacionamentos de emergência

Ambulância e IML usam vagas distintas na lateral leste da clínica, conectadas a Warehouse Way. ClinicAccess permanece acesso de pedestres. A polícia parte deslocada do eixo da porta, no estacionamento existente da delegacia.

EmergencyDepotDirector registra o ponto de ligação com a rua no veículo. EmergencyVehicle segue esse ponto na saída e permite o retorno pelo segmento do acesso ao estacionamento. O pool limpa esses dados na reutilização.

Também corrigidas duas transições do resgate: o paciente aceita embarque uma única vez durante transporte/tratamento hospitalar; paramédicos não iniciam atendimento por timeout quando ainda estão longe da vítima.

Validação: tests/test_service_parking_0909.gd passou com Vulkan real: vagas desobstruídas, saída física de ambulância e polícia, ausência de passagem pela quadra na saída da ambulância e retorno da ambulância ao pool. Captura: D:/geteco/medical-parking-0909.png. Cenário automatizado no HarborPreview com despacho real e alvos de teste. O retorno é solicitado pelo teste; não prova uma ocorrência médica completa.

tests/test_harbor_emergency_dispatch.gd passou com zero falhas antes da última alteração visual e limpeza de metadados. Houve aviso de três ObjectDB no encerramento.

A execução inicial de test_rescue_and_burial_flow.gd, anterior à mudança dos estacionamentos, falhou na asserção de distância da ambulância (vítima próxima à antiga base), embora o paciente tenha concluído o tratamento. Também houve erros de cenário de renderização em Mortician e avisos de posição não finita no Player. A suíte completa de resgate/enterro não está aprovada.

Pendentes: ocorrência médica completa partindo das novas vagas; recuperação de obstáculos em perseguições longas; manobra de estacionamento mais detalhada; entrega de paciente na entrada hospitalar; recolhimento/enterro completo; performance por região. Pasta do Antigravity preservada.
