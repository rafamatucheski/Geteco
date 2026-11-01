extends RefCounted
## Indícios do porão da Casa 1 e da rede secreta: os quatro dígitos do cofre do setor lacrado e as
## gravações 01–03 do Arquivo de Vicente. Saíram de gameplay/urban_v1/TruckersVillageSecretPassage.gd
## em 01/11 (só dados, para o dono caber na leitura); o dono reexporta VAULT_DIGITS e AUDIO_PICKUPS
## com o mesmo nome, então testes e quem lê `passage.VAULT_DIGITS`/`PASSAGE.AUDIO_PICKUPS` não mudam.
## O código do cofre (VAULT_CODE) e as funções que leem estas tabelas continuam no dono.

const VAULT_DIGITS := [
	{"id":"lab_access_badge","kind":"lab","digit":0,"local":Vector3(-2.9,.04,-6.3),"label":"Examinar crachá",
		"text":"No verso do crachá, riscado a caneta: 3."},
	{"id":"lab_power_report","kind":"lab","digit":1,"local":Vector3(-3.45,.04,-6.3),"label":"Ler relatório de energia",
		"text":"Relatório de energia do setor lacrado. Na margem, circulado: 1."},
	{"id":"lab_incident_photo","kind":"lab","digit":2,"local":Vector3(-4.0,.04,-6.3),"label":"Examinar foto do incidente",
		"text":"Foto do incidente. No canto, à mão: 9."},
	{"id":"audio_sealed_sector","kind":"audio","digit":3,"local":Vector3(3.4,.04,-4.1),"label":"Ouvir fita rotulada",
		"text":"A fita chia: \"...a última porta... o quarto número é 4. Depois disso, não volte.\""},
]
# Gravações 01–03 do Arquivo de Vicente (docs/roteiros-arquivo-vicente-20261031.md). A 04 é
# dígito do cofre (acima). Pontos em coordenadas locais do túnel, no chão em frente ao objeto da
# cenografia que já existia: cama de campanha do QG (SecretHeadquartersProps, HQ_CENTER+(5,0,4.75)),
# quadro de turnos da galeria (SecretTunnelDecor._shift_board em (12.9,1.15,-14.5)) e quadro de
# disjuntores com três faróis (SecretTunnelDecor._power_branch em (41.5,1.45,-.48)). Ficam a mais
# de 2 m dos consoles do QG para não disputar a ação com eles. O stream ainda não existe: coletar
# só registra o id em audio_logs (save da rede secreta) e libera a entrada no Arquivo.
const AUDIO_PICKUPS := [
	{"id":"audio_vicente_field","local":Vector3(61.9,.04,6.75),"label":"Pegar fita junto à cama",
		"text":"Uma fita com a letra do Vicente: \"Teste. Tá gravando.\""},
	{"id":"audio_maintenance_shift","local":Vector3(12.9,.04,-13.75),"label":"Pegar fita do quadro de turnos",
		"text":"Presa no quadro de turnos, uma fita: \"Galeria comprida.\""},
	{"id":"audio_blackout","local":Vector3(41.5,.04,.35),"label":"Pegar fita do quadro de disjuntores",
		"text":"Enfiada atrás das chaves do quadro, uma fita: \"Caiu tudo.\""},
]
