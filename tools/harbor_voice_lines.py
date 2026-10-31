"""Lê o diálogo autorado sem importar modelos de síntese nem usar GPU."""
from pathlib import Path
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]

def authored():
    rows = []
    source = (ROOT/'runtime/ArrivalDialogue.gd').read_text(encoding='utf-8-sig')
    for name in ['HOME_CALL','MEETING','TOUR']:
        block = re.search(r'const '+name+r' := \[(.*?)\]\s*(?=const|static)',source,re.S).group(1)
        for entry in re.findall(r'\["[^\n]+?\]',block):
            who, pt, en = json.loads(entry)
            rows.append(('caller' if who=='VOZ AO TELEFONE' else who.lower(),pt,en,'arrival:'+name))
    source = (ROOT/'data/GarageSequence.gd').read_text(encoding='utf-8-sig')
    block = re.search(r'const INTRO_LINES := \[(.*)\]',source,re.S).group(1)
    for entry in re.findall(r'\["[^\n]+?\]',block):
        who,pt,en=json.loads(entry); rows.append((who.lower(),pt,en,'garage'))
    for file in ['first-favors-dialogue.json','cobra-dialogue.json','jessica-dialogue.json','helena-act1-dialogue.json']:
        data=json.loads((ROOT/'data/campaign'/file).read_text(encoding='utf-8-sig'))
        for section, entries in data.items():
            if not isinstance(entries,list): continue
            for line in entries:
                rows.append((line['speaker'].lower().split(' · ')[0],line['pt'],line['en'],file+':'+section))
    rows.extend([
        ('takeshi','Ganhou. Pode entrar na minha casa e olhar os registros. Depois disso, a escolha é tua.','','race_finale'),
        ('ferrugem','Tá. Você dirige bem. O motorista vai atender o Maciota. Teu irmão queria sair de Harbor, mas não parecia estar fugindo.','','race'),
        ('dante','A lista da casa de Takeshi tem o Vicente como responsável pelas corridas do deserto.','','epilogue'),
        ('maciota','Então é pra lá que vamos. Vou te passar um contato e um lugar pra ficar. Não chega apostando o que é teu.','','epilogue'),
        ('dante','Depois de todo esse tempo, eu preciso falar com ele.','','epilogue'),
        ('maciota','Eu sei. O Ironback está na oficina. Você conquistou minha confiança, Dante.','','epilogue')
    ])
    unique={}
    for persona,pt,en,section in rows:
        key=hashlib.sha256((persona+'|'+pt).encode()).hexdigest()
        unique.setdefault(key,dict(key=key,persona=persona,text=pt,en=en,section=section))
    return list(unique.values())
