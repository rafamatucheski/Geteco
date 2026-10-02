"""Capture native stacks only after an owned x64 process main thread stops using CPU.

No debugger, symbol downloads, privilege changes or memory dumps. Each thread is
resumed in finally immediately after copying its context/stack; symbol work occurs
afterwards. This is diagnostic instrumentation, not a performance benchmark.
"""
import argparse
import ctypes as C
from ctypes import wintypes as W
import json
from pathlib import Path
import struct
import time

K = C.WinDLL('kernel32', use_last_error=True)
D = C.WinDLL('dbghelp', use_last_error=True)
P = C.WinDLL('psapi', use_last_error=True)
U64 = C.c_ulonglong
PTR = C.c_void_p


def bind(lib, name, restype, args):
    fn = getattr(lib, name)
    fn.restype, fn.argtypes = restype, args
    return fn


open_process = bind(K, 'OpenProcess', W.HANDLE, [W.DWORD, W.BOOL, W.DWORD])
open_thread = bind(K, 'OpenThread', W.HANDLE, [W.DWORD, W.BOOL, W.DWORD])
close = bind(K, 'CloseHandle', W.BOOL, [W.HANDLE])
suspend = bind(K, 'SuspendThread', W.DWORD, [W.HANDLE])
resume = bind(K, 'ResumeThread', W.DWORD, [W.HANDLE])
context = bind(K, 'GetThreadContext', W.BOOL, [W.HANDLE, PTR])
read = bind(K, 'ReadProcessMemory', W.BOOL, [W.HANDLE, PTR, PTR, C.c_size_t, C.POINTER(C.c_size_t)])
wait = bind(K, 'WaitForSingleObject', W.DWORD, [W.HANDLE, W.DWORD])
times = bind(K, 'GetThreadTimes', W.BOOL, [W.HANDLE] + [C.POINTER(W.FILETIME)] * 4)
sym_init = bind(D, 'SymInitializeW', W.BOOL, [W.HANDLE, W.LPCWSTR, W.BOOL])
sym_cleanup = bind(D, 'SymCleanup', W.BOOL, [W.HANDLE])
sym_options = bind(D, 'SymSetOptions', W.DWORD, [W.DWORD])
sym_addr = bind(D, 'SymFromAddr', W.BOOL, [W.HANDLE, U64, C.POINTER(U64), PTR])
sym_module = bind(D, 'SymGetModuleBase64', U64, [W.HANDLE, U64])
sym_table = bind(D, 'SymFunctionTableAccess64', PTR, [W.HANDLE, U64])
stack_walk = bind(D, 'StackWalk64', W.BOOL,
                  [W.DWORD, W.HANDLE, W.HANDLE, PTR, PTR, PTR, PTR, PTR, PTR])
enum_modules = bind(P, 'EnumProcessModulesEx', W.BOOL,
                    [W.HANDLE, PTR, W.DWORD, C.POINTER(W.DWORD), W.DWORD])
module_name = bind(P, 'GetModuleFileNameExW', W.DWORD, [W.HANDLE, W.HMODULE, W.LPWSTR, W.DWORD])
duplicate = bind(K, 'DuplicateHandle', W.BOOL,
                 [W.HANDLE, W.HANDLE, W.HANDLE, C.POINTER(W.HANDLE), W.DWORD, W.BOOL, W.DWORD])
current_process = bind(K, 'GetCurrentProcess', W.HANDLE, [])
final_path = bind(K, 'GetFinalPathNameByHandleW', W.DWORD, [W.HANDLE, W.LPWSTR, W.DWORD, W.DWORD])
local_module = bind(K, 'GetModuleHandleW', W.HMODULE, [W.LPCWSTR])
proc_address = bind(K, 'GetProcAddress', PTR, [W.HMODULE, C.c_char_p])


def remote_read_address(process):
    modules = (W.HMODULE * 1024)()
    needed = W.DWORD()
    if not enum_modules(process, modules, C.sizeof(modules), C.byref(needed), 3):
        return 0
    for base in modules[:min(len(modules), needed.value // C.sizeof(W.HMODULE))]:
        path = C.create_unicode_buffer(1024)
        module_name(process, base, path, len(path))
        if Path(path.value).name.lower() == 'ntdll.dll':
            local = local_module('ntdll.dll')
            return base + proc_address(local, b'NtReadFile') - local
    return 0


class ProcessMemory(C.Structure):
    _fields_ = [('size', W.DWORD), ('page_faults', W.DWORD)] + [(n, C.c_size_t) for n in
                ('peak_working_set', 'working_set', 'peak_paged_pool', 'paged_pool',
                 'peak_nonpaged_pool', 'nonpaged_pool', 'pagefile', 'peak_pagefile', 'private_bytes')]


class SystemMemory(C.Structure):
    _fields_ = [('size', W.DWORD), ('load_percent', W.DWORD)] + [(n, U64) for n in
                ('total_physical', 'available_physical', 'total_pagefile', 'available_pagefile',
                 'total_virtual', 'available_virtual', 'available_extended_virtual')]


process_memory = bind(P, 'GetProcessMemoryInfo', W.BOOL, [W.HANDLE, C.POINTER(ProcessMemory), W.DWORD])
system_memory = bind(K, 'GlobalMemoryStatusEx', W.BOOL, [C.POINTER(SystemMemory)])


def memory_stats(process):
    proc, system = ProcessMemory(), SystemMemory()
    proc.size, system.size = C.sizeof(proc), C.sizeof(system)
    result = {}
    if process_memory(process, C.byref(proc), proc.size):
        result.update(page_faults=proc.page_faults, working_set=proc.working_set, private_bytes=proc.private_bytes)
    if system_memory(C.byref(system)):
        result.update(available_physical=system.available_physical, memory_load_percent=system.load_percent)
    return result


class ThreadEntry(C.Structure):
    _fields_ = [('size', W.DWORD), ('usage', W.DWORD), ('tid', W.DWORD),
                ('pid', W.DWORD), ('priority', W.LONG), ('delta', W.LONG), ('flags', W.DWORD)]


snapshot = bind(K, 'CreateToolhelp32Snapshot', W.HANDLE, [W.DWORD, W.DWORD])
thread_first = bind(K, 'Thread32First', W.BOOL, [W.HANDLE, C.POINTER(ThreadEntry)])
thread_next = bind(K, 'Thread32Next', W.BOOL, [W.HANDLE, C.POINTER(ThreadEntry)])


def thread_ids(pid):
    h = snapshot(4, 0)
    if h == C.c_void_p(-1).value:
        return []
    result = []
    try:
        entry = ThreadEntry()
        entry.size = C.sizeof(entry)
        valid = thread_first(h, C.byref(entry))
        while valid:
            if entry.pid == pid:
                result.append(entry.tid)
            valid = thread_next(h, C.byref(entry))
    finally:
        close(h)
    return result


def cpu_ms(handle):
    ft = [W.FILETIME() for _ in range(4)]
    if not times(handle, *[C.byref(t) for t in ft]):
        return None
    return sum((t.dwHighDateTime << 32) | t.dwLowDateTime for t in ft[2:]) / 10000


def memory(process, address, size):
    buf = C.create_string_buffer(size)
    count = C.c_size_t()
    read(process, address, buf, size, C.byref(count))
    return buf.raw[:count.value]


def copy_thread(process, tid, nt_read=0):
    handle = open_thread(0x0002 | 0x0008 | 0x0040, False, tid)
    if not handle:
        return {'tid': tid, 'error': 'OpenThread', 'winerror': C.get_last_error()}
    raw = C.create_string_buffer(1232 + 15)
    aligned = (C.addressof(raw) + 15) & ~15
    C.c_uint32.from_address(aligned + 48).value = 0x10000B  # AMD64 CONTEXT_FULL
    held = False
    began = time.perf_counter()
    record = {'tid': tid}
    context_completed = None
    try:
        suspended = suspend(handle)
        record['suspend_call_ms'] = (time.perf_counter() - began) * 1000
        if suspended == 0xFFFFFFFF:
            record.update(error='SuspendThread', winerror=C.get_last_error())
            return record
        held = True
        context_began = time.perf_counter()
        context_ok = context(handle, aligned)
        record['get_context_ms'] = (time.perf_counter() - context_began) * 1000
        if not context_ok:
            record.update(error='GetThreadContext', winerror=C.get_last_error())
            return record
        context_completed = time.perf_counter()
        data = C.string_at(aligned, 1232)
        rsp, rbp, rip = [struct.unpack_from('<Q', data, i)[0] for i in (152, 160, 248)]
        copy_began = time.perf_counter()
        copied = memory(process, rsp, 65536)
        record['copy_stack_ms'] = (time.perf_counter() - copy_began) * 1000
        record.update(context=data, rsp=rsp, rbp=rbp, rip=rip, stack=copied)
        # x64 syscall stubs preserve the first argument in R10. Duplicate only
        # at the verified NtReadFile stub, then query the name after resuming.
        if nt_read and nt_read <= rip < nt_read + 32:
            candidate = struct.unpack_from('<Q', data, 200)[0]
            record.update(read_syscall=True, read_handle_candidate=hex(candidate))
            owned = W.HANDLE()
            if candidate and duplicate(process, candidate, current_process(), C.byref(owned), 0, False, 2):
                record['_file_handle'] = owned.value
            else:
                record['read_handle_duplicate_error'] = C.get_last_error() if candidate else 6
    finally:
        if held:
            if resume(handle) == 0xFFFFFFFF:
                raise OSError(C.get_last_error(), 'ResumeThread failed')
        ended = time.perf_counter()
        # This is request-to-resume, including time awaiting kernel context;
        # it is not evidence of that much additional game latency.
        record['suspended_ms'] = (ended - began) * 1000  # old readers
        record['suspend_request_to_resume_ms'] = record['suspended_ms']
        if context_completed is not None:
            record['context_complete_to_resume_ms'] = (ended - context_completed) * 1000
        close(handle)
    return record


READ_CALLBACK = C.WINFUNCTYPE(W.BOOL, W.HANDLE, U64, PTR, W.DWORD, C.POINTER(W.DWORD))


def unwind(process, record):
    owned = record.pop('_file_handle', None)
    if owned:
        try:
            path = C.create_unicode_buffer(32768)
            length = final_path(owned, path, len(path), 8)  # opened name, no normalization
            if 0 < length < len(path):
                record['read_file_path'] = path.value
            else:
                record['read_file_path_error'] = C.get_last_error()
        finally:
            close(owned)
    if 'context' not in record:
        return record
    data = record.pop('context')
    stack = record.pop('stack')
    origin = record['rsp']
    raw = C.create_string_buffer(1232 + 15)
    aligned = (C.addressof(raw) + 15) & ~15
    C.memmove(aligned, data, 1232)
    frame = C.create_string_buffer(512)
    for offset, value in [(0, record['rip']), (32, record['rbp']), (48, origin)]:
        struct.pack_into('<Q', frame, offset, value)
        struct.pack_into('<I', frame, offset + 12, 3)  # AddrModeFlat

    @READ_CALLBACK
    def reader(_handle, address, dest, size, done):
        if origin <= address < origin + len(stack):
            copied = stack[address-origin:address-origin+size]
        else:
            copied = memory(process, address, size)
        if copied:
            C.memmove(dest, copied, len(copied))
        done[0] = len(copied)
        return len(copied) == size

    addresses = [record['rip']]
    h = open_thread(0x0040, False, record['tid'])
    try:
        seen = set()
        for _ in range(63):
            if not stack_walk(0x8664, process, h, frame, aligned, reader, sym_table, sym_module, None):
                break
            address = struct.unpack_from('<Q', frame, 0)[0]
            pair = (address, struct.unpack_from('<Q', frame, 48)[0])
            if address < 65536 or pair in seen:
                break
            seen.add(pair)
            if address != addresses[-1]:
                addresses.append(address)
    finally:
        if h:
            close(h)
    result = []
    for address in addresses:
        base = sym_module(process, address)
        path = C.create_unicode_buffer(1024)
        if base:
            module_name(process, base, path, len(path))
        info = C.create_string_buffer(88 + 1024)
        struct.pack_into('<I', info, 0, 88)
        struct.pack_into('<I', info, 80, 1024)
        displacement = U64()
        ok = sym_addr(process, address, C.byref(displacement), info)
        name = info.raw[84:84+struct.unpack_from('<I', info, 76)[0]].decode('utf-8', 'replace') if ok else ''
        distant = ok and displacement.value > 4096
        result.append({'address': hex(address), 'module': Path(path.value).name,
                       'offset': hex(address-base) if base else '',
                       'symbol': '' if distant else name,
                       'nearest_export': name if distant else '',
                       'displacement': displacement.value if ok else None})
    record['frames'] = result
    record['stack_bytes_copied'] = len(stack)
    return record


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--tid', type=int, required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--ready-log', default='')
    parser.add_argument('--seconds', type=float, default=430)
    parser.add_argument('--stall-ms', type=float, default=200)
    args = parser.parse_args()
    destination = Path(args.out)
    if destination.exists():
        raise RuntimeError('Output already exists')
    process = open_process(0x100000 | 0x0400 | 0x0010 | 0x0040, False, args.pid)
    thread = open_thread(0x0040, False, args.tid)
    if not process or not thread:
        raise OSError(C.get_last_error(), 'Cannot open target')
    sym_options(4 | 0x200 | 0x80000 | 0x1000)
    if not sym_init(process, '', True):
        raise OSError(C.get_last_error(), 'SymInitializeW')
    nt_read = remote_read_address(process)
    captures = []
    began = time.monotonic()
    last_cpu = cpu_ms(thread)
    unchanged = began
    last_capture = 0.0
    ready = not args.ready_log
    print(f'WAIT_STACKS_READY pid={args.pid} tid={args.tid}', flush=True)
    try:
        while time.monotonic() - began < args.seconds and wait(process, 0) == 258:
            now = time.monotonic()
            if not ready:
                if Path(args.ready_log).exists():
                    log = Path(args.ready_log).read_text(encoding='utf-8', errors='replace')
                    ready = any(marker in log for marker in ('COMBAT_READY', 'STALL_STREAMING_READY', 'ENGINE_CACHE_READY'))
            current = cpu_ms(thread)
            if current is None or current != last_cpu or not ready:
                unchanged = now
            elif now - unchanged >= args.stall_ms / 1000 and now - last_capture >= 1.0:
                stamp = {'unix_ms': time.time() * 1000, 'cpu_ms': current,
                         'unchanged_cpu_ms': (now-unchanged)*1000, 'memory': memory_stats(process)}
                copies = [copy_thread(process, tid, nt_read) for tid in [args.tid] + [t for t in thread_ids(args.pid) if t != args.tid]]
                stamp['threads'] = [unwind(process, r) for r in copies]
                stamp['capture_ms'] = (time.monotonic()-now)*1000
                captures.append(stamp)
                destination.write_text(json.dumps({'pid': args.pid, 'main_tid': args.tid, 'captures': captures}, indent=2), encoding='utf-8')
                print(f'WAIT_CAPTURE count={len(captures)} threads={len(copies)}', flush=True)
                last_capture = time.monotonic()
            last_cpu = current
            time.sleep(.05)
    finally:
        sym_cleanup(process)
        close(thread)
        close(process)
        destination.write_text(json.dumps({'pid': args.pid, 'main_tid': args.tid, 'captures': captures}, indent=2), encoding='utf-8')
    print(f'WAIT_STACKS_DONE captures={len(captures)}', flush=True)


if __name__ == '__main__':
    main()
