# Padrão de apresentação e custo dos carros

Referência: **Infernus GT Turbo (`sport_coupe`) redesenhado em 11/10/2026**.
O pedido estabelece este trabalho como referência para os próximos carros.
As [fotos, medições e limitações da validação](reviews/sport-coupe-redesign-20261011.md)
fazem parte do padrão; a referência não aprova automaticamente outro modelo.

Em 11/10/2026, o usuário autorizou aplicar o processo aos demais carros com
três agentes e inicialmente dispensou testes e benchmarks. Depois solicitou
testes dos carros e de performance; os [resultados e limites da validação](reviews/fleet-redesign-validation-20261011.md)
substituem aquela dispensa. Foram produzidos 59 recursos de apresentação,
com autoria, contagem de geometria e fotos. Aprovação de contratos não equivale
a aprovação de toda a iluminação, animação ou de FPS. A galeria e os números
por modelo ficam em `evidence/fleet-redesign-20261011/review.html` e
`manifest.json`; o [registro do lote](reviews/fleet-redesign-20261011.md)
descreve construção, escopo e pendências. O registro ativo é `runtime/RedesignedFleet.gd`.
O hatch Meshy foi retirado da seleção ativa por pedido posterior do usuário:
o novo Metro usa o corpo/dimensões do catálogo Metro. Essa substituição tem
7 malhas contra 5 do Meshy, com menos triângulos; não contar como redução de
malhas sobre o Meshy. Os demais 58 modelos reduzem ambos os números.

Estado do Infernus GT de referência: geometria e funcionamento validados. O ganho de FPS
permanece inconclusivo; a comparação inicial teve aumento de p99 e a confirmação
com carga/foco equivalentes não foi concluída. Não tratar este registro como
aprovação de performance nem dispensar essa etapa nos próximos carros.

## Referência visual

- Silhueta própria, volumes de carroceria e caixas de roda abertas.
- Rodas com raios, disco e pinça; pinça fixa, pneu e roda com pivô correto.
- Vidros enquadrados, retrovisores, maçanetas, grelhas, para-choques e detalhes
  traseiros legíveis tanto de perto quanto na câmera normal do jogo.
- Detalhes pela aparência, sem textos decorativos. Contorno e contraste têm
  prioridade sobre subdivisões invisíveis.

O cupê de referência tem **11 malhas, 17 superfícies e 4.908 triângulos** no
modelo produzido pelo `FleetCatalog`. O estado anterior tinha 39 malhas,
39 superfícies e 61.087 triângulos. Compare sempre as mesmas etapas do factory.
Esses valores orientam carros de porte semelhante; veículos de outra função
precisam de orçamento justificado. Cada redesenho deve diminuir malhas e
triângulos em relação ao próprio original, sem substituir isso apenas por LOD.

## Construção e integração

1. Preparar o recurso fora do runtime. Agrupar detalhes estáticos por material;
   usar cores por vértice quando evitarem materiais e objetos adicionais.
2. Manter rodas, folhas de porta e lentes separadas quando sua função exigir.
   Reduzir nós não basta: registrar também superfícies, triângulos e custo
   renderizado. Evitar geometria oculta redundante.
   Papéis de material são identificadores completos: usar os predicados de
   `VehicleSurfaceRoles` para lentes. Nunca reconhecer lanterna pela substring
   `tail`, pois `detail` também a contém. Acionar farol/freio/sirene deve manter
   grades, bagageiros, retrovisores e demais acabamentos sem mutação emissiva.
3. Preservar escala, colisão, pivôs, pontos de embarque e identificador do
   catálogo. A economia visual não pode alterar a dirigibilidade por acidente.
4. Preservar pintura individual, desgaste, dano, reparo, lentes e metadados
   consultados pelos sistemas. Portas prontas reutilizam suas malhas durante a
   abertura, sem recortar a carroceria novamente ao entrar.
   A chapa da porta precisa conservar área nas duas faces após simplificação;
   contar folhas e testar sua rotação não detecta um painel vazado.
   Preservar faces grandes já simples (`batch_ratio=1.0` quando necessário),
   especialmente em superfícies com caixas desconectadas. Conferir a folha
   aberta: um contorno fechado aceitável pode esconder uma chapa eliminada.
   Preservar as dimensões da cabine em `vehicle_interior_spec` quando agrupar
   vidros desconectados ou materiais refletivos puder confundir a inferência.
   O banco e o motorista devem permanecer na cabine, alinhados ao vão da porta;
   janelas de carga não podem determinar a posição do volante ou do assento.
5. Não criar luzes, reflexos, SubViewports ou processamento por quadro para
   compensar um modelo sem acabamento.

## Evidência necessária para o próximo carro

Guardar o original e capturar frente, traseira, lado e topo com a mesma câmera,
pintura e iluminação. Acrescentar fotos no jogo e sequência temporal de
entrada, direção, esterçamento, frenagem, luzes noturnas e saída. Imagens de
conceito não substituem imagens do recurso instalado.

Validar geometria, pintura independente, rodas, portas, motorista, dano/reparo
e contato com o chão. Usar Godot 4.7.2 .NET e compilar `Harbor.csproj` antes.
Aplicar `testes-com-criterio`, `performance-do-jogo` e, quando houver alteração
de luzes/lentes, `validar-iluminacao`.

Comparar frame time em `Main.tscn` renderizada, com aquecimento separado,
amostras finitas, mesma câmera/qualidade/foco e inventário da carga efetiva.
Registrar mediana, p95, p99 e travadas. Confirmar suspeitas de regressão com
hipótese explícita; não repetir até obter um número favorável. Distinguir
economia direta do modelo de oscilações de FPS causadas pelo restante da cidade.
Não marcar performance ou iluminação como aprovadas com pendências materiais.

Autorador de referência: `tools/fleet_fixups/build_sport_coupe_gt.gd`.
O comando sem opções grava um candidato; `--install` grava o asset de produção.
