# Redesenho da frota — 11/10/2026

59 apresentações de veículos instaladas pelo `FleetCatalog.create`, além do Infernus GT anterior. O usuário pediu três agentes e fotos durante a autoria. Depois da dispensa inicial, solicitou testes funcionais e de performance; a cobertura atual consta abaixo.

[Galeria com 236 fotos reais, antes/depois e frente/traseira](../../evidence/fleet-redesign-20261011/review.html) · [Inventário por veículo e hashes](../../evidence/fleet-redesign-20261011/manifest.json)

Fotos adicionais da variante de sorvete: [frente](../../evidence/fleet-redesign-20261011/utility/icecream/front.png), [traseira](../../evidence/fleet-redesign-20261011/utility/icecream/rear.png) e [junção no teto](../../evidence/fleet-redesign-20261011/utility/icecream/roof.png).

## Resultado de geometria

| Inventário dos 59 modelos | Antes | Depois | Redução |
|---|---:|---:|---:|
| Malhas | 2.156 | 424 | 80,3% |
| Triângulos | 1.082.166 | 263.949 | 75,6% |
| Superfícies | 2.287 | 1.102 | 51,8% |

As contagens usam a apresentação completa, incluindo acabamentos do factory original. 58 modelos reduzem malhas e triângulos individualmente. O Metro substitui o hatch Meshy rejeitado: passa de 5 para 7 malhas, mas reduz os triângulos. A diferença de malhas está exposta na galeria. O novo Metro retoma as dimensões do catálogo do hatch; não usa a colisão curta do piloto Meshy.

## Design e construção

- Utilitários e serviços receberam carrocerias autoradas por família, com caixas de roda abertas, cabines, caçambas e equipamentos legíveis. Os demais mantêm sua identidade de carroceria e receberam rodas, acabamento frontal/traseiro e detalhes específicos.
- Pneus foscos, aros com raios, discos/pinças, molduras de faróis, grades, saias e difusores distribuem detalhe onde aparece na silhueta e na câmera. Materiais fixos usam cores por vértice.
- A revisão fotográfica corrige apoios de bagageiros, suporte de equipamentos, junções de cabine e painéis de fechamento. Pequenas peças e painéis de vidro são preservados durante a redução; reduzir uma malha inteira sem separar componentes havia apagado alguns desses detalhes.
- Geometria estática é consolidada fora do runtime. Rodas preservam pivôs; detalhes de porta ficam separados quando necessários. O blindado preserva os ramos do cofre. A intenção de manter essas funções não substitui teste de abertura, animação ou interação.
- `runtime/RedesignedFleet.gd` carrega os recursos sob demanda. Não foram adicionados loops por quadro, luzes de jogo ou alterações de dirigibilidade para produzir o acabamento.
- O Supra exposto pelo Takeshi também usa o modelo novo, mantendo a mesma apresentação antes e depois de ser obtido. A variante de sorvete recebe adaptação do vidro e do ornamento ao novo Courier.

## Processo reproduzível

Os autoradores ficam em `tools/fleet_fixups/`: `build_passenger_batch.gd`, `build_utility_batch.gd`, `build_service_batch.gd` e `build_special_batch.gd`. Usam `FleetBatchMesh.gd`, `PassengerDesign.gd`, `ServiceMeshKit.gd`, `SpecialFleetDesign.gd` e `SpecialMeshReduction.gd`. Os resultados são `assets/fleet/redesigned/<id>.scn`. Os originais e os inventários de partida foram preservados.

`capture_fleet_batch.gd` fotografa os recursos no Godot 4.7.2 .NET, com câmera, luz e pintura comparáveis. `--variant=after --production` usa o factory ativo; `--variant=before` seleciona o original apenas naquele processo. O Metro mudou de dimensões por substituir o Meshy, portanto o enquadramento acompanha sua nova carroceria.

`python tools/fleet_fixups/publish_fleet_redesign.py` recompõe o registro, o manifesto, esta revisão e a galeria a partir dos relatórios de autoria. Depois de alterar um asset, refotografar o respectivo carro e republicar para manter contagens e evidência alinhadas.

## Cobertura e limites

59 modelos dirigíveis: passeio, esportivos, utilitários, serviço, deserto e personagens; Infernus GT mantém o redesenho anterior. Motos, ônibus, tanque, empilhadeira e máquinas de mineração ficam fora deste lote de carros.

Contratos dos 59 modelos aprovados; dez recursos corrigidos e classificação compartilhada de lentes corrigida. Fluxo Main de seis modelos passou após corrigir o runner. Sete modelos têm vídeos e inspeção limitada. Benchmark final e única confirmação concluídos: economia de geometria comprovada, resultados de frame time mistos. Sem aprovação global de performance ou iluminação.

[Resultados, tentativas e limites da validação](fleet-redesign-validation-20261011.md).

Menos triângulos reduz o trabalho geométrico da GPU; menos instâncias e superfícies pode reduzir trabalho de preparação/submissão da renderização na CPU. Isso não reduz na mesma proporção física, IA, tráfego, iluminação ou o custo dos pixels. Os percentuais acima são de geometria, não ganho de FPS. O contador presente nas fotos inclui carregamento e captura do showroom; não é benchmark do jogo.

O padrão visual continua em [vehicle-art-standard.md](../vehicle-art-standard.md). Esta entrega não certifica o funcionamento ou a performance dos 59 veículos em gameplay.
