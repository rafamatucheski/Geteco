# Validação — primeiro quarteirão vivo

Implementação e créditos: [audio/living_city/README.md](../../../audio/living_city/README.md).

## Resultado

- `test_living_city_soundscape.gd`: **0 falhas**, executado com Godot 4.7.2
  e backend WASAPI. Verifica café, pânico dos clientes, oficina dentro/fora,
  terminal, cais, noite, saída para a montanha, redução em diálogo, limite
  fixo de emissores, canais de volume, retomada, desligado e R mantido por
  oito quadros. O teste posiciona o carro junto ao ouvinte para exercitar o mixer.
- `test_harbor_presentation_audio.gd`: **0 falhas**, incluindo abertura e
  transições das camadas do porto.
- `tools/check_living_city_audio.py`: **21 arquivos** decodificados,
  duração conferida, sinal não silencioso e picos abaixo de -1 dBFS.
- `tools/check_references.py`: **0 referências novas quebradas**.
- Capturas de imagem/áudio com renderização Vulkan e saída WASAPI reais;
  não foi feita medição de desempenho nem avaliação subjetiva de audição.

Os logs também registram erros preexistentes de importação dos controles
salvos em `GameInput.import_bindings` durante a inicialização e, na suíte de
apresentação, um aviso de ObjectDB ao encerrar. Não houve erro de script nos
novos sistemas na execução final. Esses avisos não foram tratados nesta mudança.

## Prévia

[Ouvir o percurso](previa_bairro.mp3): diner → terminal → fachada da oficina →
interior da oficina → cais, com cerca de cinco segundos em cada lugar. A montagem
preserva os volumes originais da captura e separa os locais por 250 ms de silêncio.
As capturas individuais e os relatórios numéricos estão nesta pasta.

As imagens mostram os aparelhos nas mesas/bancada e os clientes no diner.
A aparência do restante da cidade e dos personagens é a versão corrente do
projeto compartilhado durante a captura.
