# Harbor no Android

Alvo inicial: Galaxy Z Fold7. APK ARM64 .NET, pacote `com.geteco.harbor`, versão 0.3.2.

## Instalar

1. Copie `builds/android/harbor-0.3.2-debug.apk` para o celular e instale sobre a versão anterior.
2. Abra o arquivo no aplicativo Meus Arquivos e permita a instalação por esse
   aplicativo quando o Android solicitar.
3. Ative a rotação automática do Android e abra Harbor. Retrato, paisagem e suas
   posições invertidas acompanham o aparelho. A interface se adapta à tela disponível.

É um APK de teste assinado com a chave de depuração local. Uma atualização com
outra chave exige um procedimento de migração; preserve os saves antes de
desinstalar. Não é uma publicação na Play Store.

## Controles

- Analógico esquerdo: andar no curso interno, correr ao puxar até a borda; dirigindo, vira o veículo.
- O centro dos analógicos tem zona morta para evitar movimento involuntário.
- Tela estreita ou quase quadrada usa controles maiores e opções em três colunas.
- Analógico direito: mirar. Atacar dispara ou executa o ataque equipado.
- Ação: interagir; Entrar/Sair: veículo. Recarregar e Arma fazem as ações indicadas.
- Dirigindo: Acelerar, Frear/Ré e Freio mão, com direção simultânea.
- Dirigindo, Rádio ‹/› muda a estação; Liga/desliga desliga diretamente e retoma a última estação.
- Pausa, Mapa e Inventário ficam no alto. `•••` abre comandos secundários, incluindo
  câmera, bagagem, diário, lanterna, rendição e os acessórios dos veículos.
- Inventário: toque no item e nos botões de ação ou arraste para mover.
- Mapa: arraste para mover, use `+`/`−` para zoom e toque para selecionar.
- Gazua: setas ajustam o ângulo; segure Girar. Cofre/viatura: toque em Travar.
- Voltar fecha menus. A perda de foco no Android libera os toques e pausa a
  jogabilidade quando ela está ativa. Redimensionar a tela também libera toques.

A garagem preserva suas restrições: não há ataque ou troca de arma disponível.

Novo jogo começa com dois bolsos. A primeira mochila é recolhida ao abrir fisicamente
o porta-malas da Monaliza conquistada no Primeiro Giro, uma vez por save. Bolsas já
possuídas e malas de recuperação de saves antigos preservam seus itens.

## Travadas no aparelho

O contador opcional mostra o maior intervalo real entre quadros a cada segundo,
além do FPS médio. O Android registra até 128 pausas acima de 50 ms em memória,
com posição, CPU e física. Ao pausar/abrir menu ou colocar o app em segundo plano,
grava `user://frame-stalls.json`; não escreve no disco durante a jogabilidade.
O registro não mede separadamente GPU/driver e não certifica a causa da pausa.
Em APK debug, com depuração USB autorizada, o arquivo pode ser lido com:

```powershell
adb shell run-as com.geteco.harbor cat files/frame-stalls.json
```

## Build reproduzível

Use Godot 4.7.2 **.NET (mono)** e seus templates oficiais **mono**, Java 17 e
Android SDK configurado no editor. O desktop usa .NET 10; o alvo Android usa
.NET 9, correspondente ao runtime dos templates. As texturas também são
importadas em ETC2/ASTC para Android. O script compila C# antes de exportar.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1 -CheckOnly
powershell -NoProfile -ExecutionPolicy Bypass -File tools/build_android.ps1
```

O script gera o APK em `builds/android/` e informa SHA-256. APKs e chaves não
entram no Git. Para revisar os controles no desktop, inicie com `--touch-controls`.

Validação física no Fold7 (instalação, multitarefa, dobrar/desdobrar, aquecimento,
autonomia e FPS) depende do aparelho. A validação desktop não substitui essa etapa.
