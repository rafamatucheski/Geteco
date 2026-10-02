"""Owned local pipe: verify NtReadFile HANDLE capture and eventual resumption."""
import ctypes as C
from ctypes import wintypes as W
import os
import threading
import time

kernel = C.WinDLL('kernel32', use_last_error=True)
def api(name, result, arguments):
    call = getattr(kernel, name)
    call.restype, call.argtypes = result, arguments
    return call
create_pipe = api('CreateNamedPipeW', W.HANDLE, [W.LPCWSTR, W.DWORD, W.DWORD, W.DWORD, W.DWORD, W.DWORD, W.DWORD, C.c_void_p])
connect = api('ConnectNamedPipe', W.BOOL, [W.HANDLE, C.c_void_p])
create_file = api('CreateFileW', W.HANDLE, [W.LPCWSTR, W.DWORD, W.DWORD, C.c_void_p, W.DWORD, W.DWORD, W.HANDLE])
read_file = api('ReadFile', W.BOOL, [W.HANDLE, C.c_void_p, W.DWORD, C.POINTER(W.DWORD), C.c_void_p])
write_file = api('WriteFile', W.BOOL, [W.HANDLE, C.c_void_p, W.DWORD, C.POINTER(W.DWORD), C.c_void_p])
close = api('CloseHandle', W.BOOL, [W.HANDLE])
name = rf'\\.\pipe\geteco-owned-read-fixture-{os.getpid()}'
server = create_pipe(name, 1, 0, 1, 4096, 4096, 1000, None)
assert server != C.c_void_p(-1).value
def writer():
    time.sleep(.2)
    client = create_file(name, 0x40000000, 0, None, 3, 0, None)
    assert client != C.c_void_p(-1).value
    try:
        time.sleep(2)
        count = W.DWORD()
        assert write_file(client, C.create_string_buffer(b'x'), 1, C.byref(count), None)
    finally:
        close(client)
thread = threading.Thread(target=writer)
thread.start()
assert connect(server, None) or C.get_last_error() == 535
print(f'READ_READY pid={os.getpid()} tid={threading.get_native_id()} handle={hex(server)}', flush=True)
buffer, count = C.create_string_buffer(1), W.DWORD()
try:
    assert read_file(server, buffer, 1, C.byref(count), None)
    assert count.value == 1 and buffer.raw == b'x'
finally:
    close(server)
thread.join()
print('READ_FIXTURE_RESUMED bytes=1', flush=True)
