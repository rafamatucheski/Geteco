# Cartas de Vicente — revisão de posições em 21/10/2026

As dez cartas destinadas ao Dante foram inspecionadas com a geometria renderizada e as colisões dos geradores usados pelo jogo, incluindo as edições de mapa salvas. Seis foram reposicionadas; IDs, textos das cartas, regras de coleta e recompensas permanecem iguais. O usuário fará o teste jogando.

| Carta | Resultado | Posição final X / Z (metros) |
|---|---|---|
| 01 | Saiu da pista da ponte de Foundry para o passeio do cais, entre os guindastes. | 197 / 94 |
| 02 | Saiu do meio do pátio para a lateral da fachada da oficina, fora da vaga e do portão. | 161 / 108 |
| 03 | Mantida no corredor lateral dos sobrados, próximo à caçamba. | 322 / -58 |
| 04 | Saiu da linha central da ponte da serra para o passeio sul, dentro do guarda-corpo. | 520 / -278,9 |
| 05 | Saiu de trás da cabana para a clareira diante dela. | 747 / -351,5 |
| 06 | Saiu do terreno entre pistas para o passeio diante do terminal da vila. | 732,375 / -409,2 |
| 07 | Mantida no salão da Caverna do Sussurro, com aproximação ao lado do vagonete. | Ponto local 0 / -3,6, giro 1,8 rad |
| 08 | Saiu de dentro da cama para o piso ao pé dela, no quarto 1 do Motel Oásis. | Local -13,4 / -3,3 |
| 09 | Mantida no corredor central da capela, antes do altar. | Local 0 / -5,2 |
| 10 | Mantida no piso da sala de cronometragem. | Local 19,5 / -0,4 |

Os nomes de localização das cartas 05 e 06 nos catálogos foram ajustados para cabana e terminal. As posições do deserto continuam relativas aos locais e com altura fixa para evitar que o raio de chão coloque o pickup no telhado.

## Evidências e limites

- `dotnet build Harbor.csproj --no-restore -v quiet`: aprovado, sem avisos ou erros.
- Godot 4.7.2 .NET, Forward+, inspeção renderizada dos dez pontos antes/depois. Cenário de Harbor e montanha via `EditableRegion`; ambientes do deserto pelos mesmos lotes `RoadsideBuild` usados em runtime, com coberturas removidas para inspecionar o interior.
- Cápsula de raio 0,32 m e altura 1,7 m livre nos dez pontos finais. Caminhos locais de aproximação amostrados a cada 0,125 m, incluindo apoio no chão nas seis posições exteriores. No deserto, a cena isolada verifica os sólidos do ambiente; o terreno do mapa não foi instanciado.
- A primeira rota de inspeção do motel cortava a parede lateral do vão. A rota corrigida entra reta por X local -14,7 até Z -1,75, vira para X -13,4 e segue até Z -3,3; está livre na consulta física. Nenhuma parede, cama ou cadeira foi modificada.
- Isso não equivale a caminhar com o controlador real, testar coleta, restauração de save, corte de teto ou oclusão com a câmera final. Esses testes ficam com o usuário. Não há certificação de interiores nem aprovação de FPS; não foram acrescentados objetos, luzes, colisões ou processamento em runtime.
- A tentativa de abrir a sessão completa não chegou à inspeção. A primeira execução encerrou com código 1 sem diagnóstico; a segunda foi interrompida por esta tarefa após não avançar. A inspeção foi concluída em cena dedicada.
- A montagem da montanha registrou o erro preexistente `alteração inválida ou origem ausente: path/mountain_zoo_walk`. Não foi alterado por esta tarefa.

Artefatos locais em `evidence/letters-placement-20261021/` (não versionados): `geometry.log` e imagens `geo-vicente_letter_*.png` são o estado inicial; `final.log` e imagens `final-vicente_letter_*.png` são as posições finais. `motel-approach.log` registra o caminho corrigido. A esfera magenta nas capturas indica o ponto inspecionado, não é um objeto adicionado ao jogo.

Motel: [antes](../evidence/letters-placement-20261021/geo-vicente_letter_08.png) / [depois](../evidence/letters-placement-20261021/final-vicente_letter_08.png).
