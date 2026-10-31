"""Produção local e finita com VoiceDesign para o capítulo autorado de Harbor.

Usa o modelo/ambiente já em cache do projeto, sem rede nem clonagem de voz.
Chaves exatas de texto/persona mantêm gravações e legendas acopladas.
"""
from pathlib import Path
import hashlib, json, os, re, time, sys, ctypes
ROOT = Path(__file__).resolve().parents[1]
MODEL_ROOT = Path('D:/geteco/tools/opening_voice_models')
os.environ['HF_HOME'] = str(MODEL_ROOT)
os.environ['HF_HUB_OFFLINE'] = '1'
os.environ['TRANSFORMERS_OFFLINE'] = '1'
LIGHT = '--throughput' not in sys.argv
os.environ['OMP_NUM_THREADS'] = '1' if LIGHT else '4'
PRIVATE_LIMIT_MB = 6000  # O Windows também cobra aqui as alocações de apoio do CUDA.
RESIDENT_LIMIT_MB = 2048

def constrain_desktop_process():
    # O Windows impõe isto antes dos imports/carga do modelo, inclusive alocações
    # temporárias de pesos. Uma checagem só na decodificação não protege o pico da carga.
    if os.name != 'nt': raise RuntimeError('Light voice production requires the Windows memory limiter')
    class BasicLimits(ctypes.Structure):
        _fields_ = [('PerProcessUserTimeLimit',ctypes.c_int64),('PerJobUserTimeLimit',ctypes.c_int64),
            ('LimitFlags',ctypes.c_uint32),('MinimumWorkingSetSize',ctypes.c_size_t),
            ('MaximumWorkingSetSize',ctypes.c_size_t),('ActiveProcessLimit',ctypes.c_uint32),
            ('Affinity',ctypes.c_size_t),('PriorityClass',ctypes.c_uint32),('SchedulingClass',ctypes.c_uint32)]
    class IOCounts(ctypes.Structure):
        _fields_ = [(name,ctypes.c_uint64) for name in ['ReadOperationCount','WriteOperationCount',
            'OtherOperationCount','ReadTransferCount','WriteTransferCount','OtherTransferCount']]
    class ExtendedLimits(ctypes.Structure):
        _fields_ = [('BasicLimitInformation',BasicLimits),('IoInfo',IOCounts),
            ('ProcessMemoryLimit',ctypes.c_size_t),('JobMemoryLimit',ctypes.c_size_t),
            ('PeakProcessMemoryUsed',ctypes.c_size_t),('PeakJobMemoryUsed',ctypes.c_size_t)]
    kernel = ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.CreateJobObjectW.argtypes = [ctypes.c_void_p,ctypes.c_wchar_p]
    kernel.CreateJobObjectW.restype = ctypes.c_void_p
    kernel.GetCurrentProcess.restype = ctypes.c_void_p
    kernel.SetInformationJobObject.argtypes = [ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]
    kernel.AssignProcessToJobObject.argtypes = [ctypes.c_void_p,ctypes.c_void_p]
    kernel.SetPriorityClass.argtypes = [ctypes.c_void_p,ctypes.c_uint32]
    job = kernel.CreateJobObjectW(None,None)
    limits = ExtendedLimits()
    # Uma cota de working set por job exige privilégios que o usuário da área de trabalho não tem.
    # O commit privado é imposto pelo Windows; a residência é conferida a cada
    # bloco de 8 MB carregado e token gerado, sem pedir acesso de administrador.
    limits.BasicLimitInformation.LimitFlags = 0x100
    limits.ProcessMemoryLimit = PRIVATE_LIMIT_MB*1024**2
    if not job or not kernel.SetInformationJobObject(job,9,ctypes.byref(limits),ctypes.sizeof(limits)):
        raise ctypes.WinError(ctypes.get_last_error())
    process = kernel.GetCurrentProcess()
    if not kernel.AssignProcessToJobObject(job,process): raise ctypes.WinError(ctypes.get_last_error())
    if not kernel.SetPriorityClass(process,0x4000): raise ctypes.WinError(ctypes.get_last_error())
    return job

DESKTOP_JOB = constrain_desktop_process() if LIGHT else None
import numpy as np
import soundfile as sf
import torch
from qwen_tts import Qwen3TTSModel
from transformers import LogitsProcessor, LogitsProcessorList
import transformers.modeling_utils as modeling_utils

class StreamingTensorSlice:
    def __init__(self,archive,key): self.archive,self.key=archive,key
    def get_shape(self): return self.archive.header[self.key]['shape']
    def get_dtype(self): return self.archive.header[self.key]['dtype']
    def __getitem__(self,index): return self.archive.get_tensor(self.key)[index]

class StreamingSafeOpen:
    """Lê um tensor verificado por vez em vez de mapear um arquivo de 3,6 GB.

    O Windows cobra o mapeamento privado inteiro do safetensors no orçamento do
    processo, mesmo quando o modelo carrega direto na GPU.
    Este adaptador vale só para este processo de produção offline de um dispositivo.
    """
    def __init__(self,filename,framework,device='cpu'):
        if framework != 'pt': raise ValueError('Only the local PyTorch checkpoint is supported')
        self.filename=filename
        self.device='cuda:'+str(device) if isinstance(device,int) else device
        with open(filename,'rb') as file:
            size=int.from_bytes(file.read(8),'little')
            if size<=0 or size>16*1024**2: raise ValueError('Invalid safetensors header length')
            self.header=json.loads(file.read(size))
        self.offset=8+size
        self.file_size=os.path.getsize(filename)
    def __enter__(self): return self
    def __exit__(self,*args): return False
    def metadata(self): return self.header.get('__metadata__')
    def keys(self): return [key for key in self.header if key!='__metadata__']
    def get_slice(self,key): return StreamingTensorSlice(self,key)
    def get_tensor(self,key):
        description=self.header[key]
        dtype=modeling_utils.str_to_torch_dtype[description['dtype']]
        begin,end=description['data_offsets']
        count=1
        for dimension in description['shape']: count*=dimension
        if begin<0 or end<begin or self.offset+end>self.file_size or end-begin!=count*torch.empty((),dtype=dtype).element_size():
            raise ValueError('Invalid tensor bounds for '+key)
        tensor=torch.empty(count,dtype=dtype,device=self.device)
        item_size=tensor.element_size()
        buffer=bytearray(min(end-begin,8*1024**2))
        view=memoryview(buffer)
        with open(self.filename,'rb') as file:
            file.seek(self.offset+begin)
            for at in range(0,end-begin,len(buffer)):
                chunk=view[:min(len(buffer),end-begin-at)]
                if file.readinto(chunk)!=len(chunk): raise EOFError(key)
                first=at//item_size
                tensor[first:first+len(chunk)//item_size].copy_(torch.frombuffer(chunk,dtype=dtype))
                check_desktop_memory()
                time.sleep(len(chunk)/(64*1024**2))  # limita a leitura do modelo a 64 MB/s
        return tensor.reshape(description['shape'])

class ProcessMemory(ctypes.Structure):
    _fields_=[('cb',ctypes.c_ulong),('PageFaultCount',ctypes.c_ulong)]+[(name,ctypes.c_size_t) for name in ['PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage','PrivateUsage']]

def process_memory():
    if os.name!='nt': return (0,0)
    counters=ProcessMemory();counters.cb=ctypes.sizeof(counters)
    ctypes.windll.kernel32.GetCurrentProcess.restype=ctypes.c_void_p
    ctypes.windll.psapi.GetProcessMemoryInfo.argtypes=[ctypes.c_void_p,ctypes.POINTER(ProcessMemory),ctypes.c_ulong]
    handle=ctypes.windll.kernel32.GetCurrentProcess()
    if not ctypes.windll.psapi.GetProcessMemoryInfo(handle,ctypes.byref(counters),counters.cb): raise RuntimeError('Process memory accounting unavailable')
    return (counters.PrivateUsage/1024**2,counters.WorkingSetSize/1024**2)

def private_memory_mb(): return process_memory()[0]

def check_desktop_memory():
    if not LIGHT: return
    private,resident=process_memory()
    if private>PRIVATE_LIMIT_MB or resident>RESIDENT_LIMIT_MB:
        raise MemoryError('Voice desktop memory budget exceeded: private='+str(round(private))+' resident='+str(round(resident)))

class DesktopBudget(LogitsProcessor):
    def __init__(self): self.started=time.monotonic()
    def __call__(self,input_ids,scores):
        check_desktop_memory()
        if time.monotonic()-self.started>900: raise TimeoutError('Voice production exceeded the 15 minute finite budget')
        time.sleep(.06)
        return scores
BASE = 'Native Brazilian Portuguese, natural everyday Brazilian accent, clear consonants, dry clean studio dialogue. '
VOICES = {
    'dante': BASE + 'Man aged 32, warm medium-low slightly textured voice, understated, conversational, never an announcer.',
    'maciota': BASE + 'Man aged 50, warm relaxed low baritone, easygoing mechanic, calm and personal, a little roughness, unhurried.',
    'caller': BASE + 'Man aged 50, warm relaxed low baritone, easygoing mechanic, calm and personal, a little roughness, speaking quietly on a telephone.',
    'jessica': BASE + 'Woman aged 28, delicate soft clear voice, warm and self-confident, subtle playful humor, natural everyday conversation.',
    'helena': BASE + 'Woman aged 40, clear warm professional voice, calm and concise.',
    'ferrugem': BASE + 'Man aged 38, slightly rough middle-low voice, practical mechanic, understated.',
    'neco': BASE + 'Man aged 55, dry low voice, experienced workshop owner, direct and practical.',
    'moradora': BASE + 'Woman aged 45, ordinary natural voice, worried but intelligible, relieved when thanking someone.',
    'takeshi': BASE + 'Man aged 41, low firm voice, controlled and confident racer, understated.'
}

from harbor_voice_lines import authored

def main():
    rows=authored()
    output=ROOT/'audio/mission_voices/harbor_story'
    output.mkdir(parents=True,exist_ok=True)
    manifest_path=ROOT/'audio/mission_voices/recordings.json'
    manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    previous_path=output/'production.json'
    previous=json.loads(previous_path.read_text(encoding='utf-8-sig')) if previous_path.exists() else {}
    statuses={line['key']:line.get('status','generated') for line in previous.get('lines',[])}
    for row in rows: row['status']=statuses.get(row['key'],'generated')
    missing=[row for row in rows if not (output/(row['key']+'.wav')).exists()]
    model=None
    if missing:
        cached=next((MODEL_ROOT/'hub/models--Qwen--Qwen3-TTS-12Hz-1.7B-VoiceDesign/snapshots').iterdir())
        print('VOICE_MODEL_LOADING '+str(len(missing)),flush=True)
        torch.set_num_threads(1 if LIGHT else 4)
        if LIGHT:
            torch.cuda.set_per_process_memory_fraction(.60)
            if os.name=='nt':
                ctypes.windll.kernel32.GetCurrentProcess.restype=ctypes.c_void_p
                ctypes.windll.kernel32.SetPriorityClass.argtypes=[ctypes.c_void_p,ctypes.c_ulong]
                ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(),0x4000)
        original_open=modeling_utils.safe_open
        original_warmup=modeling_utils.caching_allocator_warmup
        if LIGHT:
            modeling_utils.safe_open=StreamingSafeOpen
            # O pré-aquecimento opcional do alocador reserva um segundo bloco do
            # tamanho do modelo, estourando o orçamento da GPU antes de carregar qualquer peso.
            modeling_utils.caching_allocator_warmup=lambda *args,**kwargs: None
        try:
            model=Qwen3TTSModel.from_pretrained(str(cached),device_map='cuda:0',dtype=torch.bfloat16,attn_implementation='sdpa',local_files_only=True,low_cpu_mem_usage=True)
        finally:
            modeling_utils.safe_open=original_open
            modeling_utils.caching_allocator_warmup=original_warmup
        if LIGHT and private_memory_mb()>PRIVATE_LIMIT_MB: raise MemoryError('Voice model exceeds the desktop allocation budget')
    # A produção na área de trabalho usa por padrão uma tomada e orçamentos rígidos de recursos.
    # Lotes de vazão exigem adesão explícita na linha de comando.
    batch_size=1 if LIGHT else 3
    budget=DesktopBudget() if LIGHT else None
    for offset in range(0,len(missing),batch_size):
        batch=missing[offset:offset+batch_size]
        torch.manual_seed(8131+list(VOICES).index(batch[0]['persona'])*701)
        began=time.monotonic()
        options={'logits_processor':LogitsProcessorList([budget])} if LIGHT else {}
        waves,rate=model.generate_voice_design(text=[r['text'] for r in batch],language='Portuguese',instruct=[VOICES[r['persona']] for r in batch],max_new_tokens=360 if LIGHT else 600,temperature=.7,top_p=.9,**options)
        for row,wave in zip(batch,waves):
            signal=np.asarray(wave,dtype=np.float32)
            active=np.flatnonzero(np.abs(signal)>.004)
            if len(active): signal=signal[max(0,int(active[0]-rate*.08)):min(len(signal),int(active[-1]+rate*.16))]
            peak=float(np.max(np.abs(signal)))
            if peak>.9: signal*=.9/peak
            sf.write(output/(row['key']+'.wav'),signal,rate,subtype='PCM_16')
        print('VOICE_BATCH '+str(offset+len(batch))+'/'+str(len(missing))+' '+str(round(time.monotonic()-began,1))+'s private_mb='+str(round(private_memory_mb())),flush=True)
        for row in rows:
            path=output/(row['key']+'.wav')
            if not path.exists(): continue
            row['seconds']=sf.info(path).duration
            row['path']='res://audio/mission_voices/harbor_story/'+path.name
            if row['status']=='review_required': manifest.pop(row['key'],None)
            else: manifest[row['key']]=row['path']
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        completed=[r for r in rows if 'path' in r]
        (output/'production.json').write_text(json.dumps({'model':'Qwen3-TTS VoiceDesign','language':'pt-BR','voice_cloning':False,'complete':False,'lines':completed},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for i,row in enumerate(rows):
        path=output/(row['key']+'.wav')
        if not path.exists():
            raise RuntimeError('Voice batch did not produce '+row['key'])
        row['seconds']=sf.info(path).duration
        row['path']='res://audio/mission_voices/harbor_story/'+path.name
        if row['status']=='review_required': manifest.pop(row['key'],None)
        else: manifest[row['key']]=row['path']
        manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        (output/'production.json').write_text(json.dumps({'model':'Qwen3-TTS VoiceDesign','language':'pt-BR','voice_cloning':False,'complete':False,'lines':rows[:i+1]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    playable=sum(row['status']!='review_required' for row in rows)
    (output/'production.json').write_text(json.dumps({'model':'Qwen3-TTS VoiceDesign','language':'pt-BR','voice_cloning':False,'complete':playable==len(rows),'usable_lines':playable,'lines':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('VOICE_PRODUCED '+str(len(rows))+' playable='+str(playable),flush=True)

if __name__=='__main__': main()
