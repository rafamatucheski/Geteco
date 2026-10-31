"""Recebe uma sessão local de depuração do Godot; agrega todo quadro de script/nativo e guarda perfis lentos.

Usa o protocolo Variant com prefixo de tamanho do Godot (core/debugger/remote_debugger_peer.cpp)
e servers/debugger/servers_debugger.cpp. Este receptor não envia comandos ao depurador.
Ligue o profiler pela cena de diagnóstico; ele nunca pausa nem edita o jogo.
"""
import argparse
import collections
import json
import pathlib
import socket
import struct
import time


class VariantReader:
    def __init__(self, data):
        self.data = data
        self.offset = 0

    def read(self, fmt):
        value = struct.unpack_from('<' + fmt, self.data, self.offset)
        self.offset += struct.calcsize('<' + fmt)
        return value[0] if len(value) == 1 else list(value)

    def string(self):
        length = self.read('I')
        start = self.offset
        self.offset += (length + 3) & ~3
        return self.data[start:start + length].decode('utf-8', errors='replace')

    def variant(self):
        header = self.read('I')
        kind = header & 0xFFFF
        wide = bool(header & 0x10000)
        if kind == 0:
            return None
        if kind == 1:
            return bool(self.read('I'))
        if kind == 2:
            return self.read('q' if wide else 'i')
        if kind == 3:
            return self.read('d' if wide else 'f')
        if kind in (4, 21):
            return self.string()
        if kind in (27, 28):
            if header & ~0xFFFF:
                raise ValueError('Typed collection not supported')
            count = self.read('I') & 0x7FFFFFFF
            if count > 2000000:
                raise ValueError('Collection too large')
            if kind == 28:
                return [self.variant() for _ in range(count)]
            result = []
            for _ in range(count):
                result.append([self.variant(), self.variant()])
            return {'dictionary_pairs': result}
        if kind == 29:
            length = self.read('I')
            start = self.offset
            self.offset += (length + 3) & ~3
            return {'bytes_hex': self.data[start:start + length].hex()}
        if kind in (30, 31, 32, 33):
            count = self.read('I')
            fmt = {30: 'i', 31: 'q', 32: 'f', 33: 'd'}[kind]
            return [self.read(fmt) for _ in range(count)]
        if kind == 34:
            return [self.string() for _ in range(self.read('I'))]
        raise ValueError(f'Unsupported Variant type {kind}')


def frame_profile(data, signatures):
    if not isinstance(data, list) or len(data) < 8:
        raise ValueError('Invalid server profile')
    frame, frame_time, process_time, physics_time, physics_frame_time, script_time = data[:6]
    cursor = 7
    servers = {}
    for _ in range(int(data[6])):
        name, size = data[cursor:cursor + 2]
        cursor += 2
        servers[name] = dict(zip(data[cursor:cursor + size:2], data[cursor + 1:cursor + size:2]))
        cursor += size
    size = int(data[cursor])
    cursor += 1
    if size % 5 or cursor + size != len(data):
        raise ValueError('Invalid script function data')
    functions = []
    for i in range(cursor, cursor + size, 5):
        signature, calls, own, total, native = data[i:i + 5]
        functions.append({'signature_id': signature, 'signature': signatures.get(str(signature), '?'),
                          'calls': calls, 'self_ms': own * 1000, 'total_ms': total * 1000,
                          'native_ms': native * 1000})
    return {'frame': frame, 'frame_ms': frame_time * 1000, 'process_ms': process_time * 1000,
            'physics_ms': physics_time * 1000, 'physics_frame_ms': physics_frame_time * 1000,
            'script_ms': script_time * 1000, 'servers': servers, 'functions': functions}


class FrameAggregate:
    """Tempos próprios disjuntos por quadro; resumos cumulativos finais nunca entram aqui."""

    def __init__(self, function_cap=2048):
        self.function_cap = function_cap
        self.functions = {}
        self.frames = []
        self.seen_frames = set()
        self.issues = []
        self.previous_frame = None

    def add(self, profile):
        frame = int(profile['frame'])
        if frame in self.seen_frames:
            self.issues.append({'kind': 'duplicate_frame', 'frame': frame})
            return
        if self.previous_frame is not None and frame != self.previous_frame + 1:
            self.issues.append({'kind': 'frame_discontinuity', 'previous': self.previous_frame, 'frame': frame})
        self.seen_frames.add(frame)
        self.previous_frame = frame
        rows = profile['functions']
        totals = {'script_self_ms': 0.0, 'native_self_ms': 0.0, 'unknown_self_ms': 0.0}
        for function in rows:
            signature = function['signature']
            kind = 'unknown' if signature == '?' else ('native' if '::0::' in signature else 'script')
            key = signature if signature != '?' else '?id=' + str(function['signature_id'])
            if kind == 'unknown':
                self.issues.append({'kind': 'unknown_signature', 'frame': frame, 'signature_id': function['signature_id']})
            row = self.functions.setdefault(key, {'signature': signature, 'kind': kind,
                'calls': 0, 'self_ms': 0.0, 'inclusive_ms': 0.0,
                'max_frame_self_ms': 0.0, 'frames_present': 0})
            row['calls'] += int(function['calls'])
            row['self_ms'] += function['self_ms']
            row['inclusive_ms'] += function['total_ms']
            row['max_frame_self_ms'] = max(row['max_frame_self_ms'], function['self_ms'])
            row['frames_present'] += 1
            totals[kind + '_self_ms'] += function['self_ms']
        self.frames.append({'frame': frame, 'function_count': len(rows),
            'cap_reached': len(rows) >= self.function_cap,
            'frame_ms': profile['frame_ms'], 'process_ms': profile['process_ms'],
            'physics_ms': profile['physics_ms'], 'reported_self_ms': profile['script_ms'],
            **totals})

    def snapshot(self):
        functions = sorted(self.functions.values(), key=lambda row: -row['self_ms'])
        capped = sum(row['cap_reached'] for row in self.frames)
        return {'scope': 'Accumulates every received servers:profile_frame exactly once; excludes servers:profile_total. Self is wall time, not thread CPU. Script self can include property setters and inline native operations; native rows are separately timed calls. Never add inclusive_ms or native_ms/internal_time to self totals. Native calls are collated by method by Godot: the attached script path is not reliable caller attribution. Profile overhead, omitted functions, nested callbacks and focus validity prevent treating this as a complete exclusive CPU partition or clean FPS benchmark.',
            'configured_function_cap': self.function_cap, 'frames_received': len(self.frames),
            'capped_frames': capped, 'issues': self.issues,
            'coverage_ok': bool(self.frames) and not self.issues and capped == 0,
            'script_self_ms': sum(row['self_ms'] for row in functions if row['kind'] == 'script'),
            'native_self_ms': sum(row['self_ms'] for row in functions if row['kind'] == 'native'),
            'unknown_self_ms': sum(row['self_ms'] for row in functions if row['kind'] == 'unknown'),
            'frames': self.frames, 'functions': functions}


def receive(port, destination, seconds, function_cap=2048):
    report = {'port': port, 'passive_receiver': True, 'signatures': {}, 'slow_frames': [],
              'errors': [], 'messages': {}, 'profile_frames': 0, 'summaries': [], 'target_frames': []}
    aggregate = FrameAggregate(function_cap)
    counts = collections.Counter()
    deadline = time.monotonic() + seconds
    next_progress = 0
    with destination.open('x', encoding='utf-8') as output:
        try:
            with socket.socket() as server:
                server.bind(('127.0.0.1', port))
                server.listen(1)
                server.settimeout(40)
                print(f'PROFILE_LISTENING port={port}', flush=True)
                connection, address = server.accept()
                report['connected_unix'] = time.time()
                with connection:
                    connection.settimeout(1)
                    buffer = bytearray()
                    while time.monotonic() < deadline:
                        try:
                            chunk = connection.recv(65536)
                        except socket.timeout:
                            continue
                        if not chunk:
                            break
                        buffer.extend(chunk)
                        while len(buffer) >= 4:
                            size = struct.unpack_from('<I', buffer)[0]
                            if size > 8 * 1024 * 1024:
                                raise ValueError('Debug packet exceeds 8 MiB')
                            if len(buffer) < size + 4:
                                break
                            payload = bytes(buffer[4:size + 4])
                            del buffer[:size + 4]
                            try:
                                reader = VariantReader(payload)
                                message = reader.variant()
                                if reader.offset != len(payload) or not isinstance(message, list):
                                    raise ValueError('Invalid packet boundary')
                                # O Godot 4.7 inclui o ID da thread que envia entre
                                # o rótulo e a carga; versões antigas usavam dois campos.
                                if len(message) == 3 and isinstance(message[1], int):
                                    label, thread_id, data = message
                                elif len(message) == 2:
                                    label, data = message
                                else:
                                    raise ValueError('Invalid debugger envelope')
                                counts[label] += 1
                                if label == 'servers:function_signature':
                                    report['signatures'][str(data[1])] = data[0]
                                elif label in ('servers:profile_frame', 'servers:profile_total'):
                                    profile = frame_profile(data, report['signatures'])
                                    if label.endswith('total'):
                                        report['summaries'].append(profile)
                                    else:
                                        report['profile_frames'] += 1
                                        aggregate.add(profile)
                                        if any(function['total_ms'] >= 10 and any(
                                                key in function['signature'] for key in ('::_stall_damage', '::wreck', '::_stall_wreck'))
                                               for function in profile['functions']):
                                            if len(report['target_frames']) < 500:
                                                report['target_frames'].append(profile)
                                        if profile['frame_ms'] >= 66.7 or profile['script_ms'] >= 50:
                                            if len(report['slow_frames']) < 5000:
                                                report['slow_frames'].append(profile)
                                        if time.monotonic() >= next_progress:
                                            next_progress = time.monotonic() + 15
                                            last = report['slow_frames'][-1] if report['slow_frames'] else {}
                                            print('PROFILE_PROGRESS ' + json.dumps({
                                                'frames': report['profile_frames'], 'errors': len(report['errors']),
                                                'slow': len(report['slow_frames']), 'last_slow_ms': last.get('frame_ms'),
                                                'last_top_function': last.get('functions', [{}])[0].get('signature')}), flush=True)
                                elif label == 'error' and len(report['errors']) < 40:
                                    report['errors'].append({'engine_error': data})
                            except (ValueError, TypeError, IndexError, struct.error) as error:
                                if len(report['errors']) < 40:
                                    report['errors'].append({'decode_error': str(error), 'packet_prefix_hex': payload[:96].hex()})
        except (OSError, ValueError) as error:
            report['receiver_error'] = str(error)
        finally:
            report['messages'] = dict(counts)
            report['frame_aggregate'] = aggregate.snapshot()
            json.dump(report, output, ensure_ascii=False, indent=2)
    print(f"PROFILE_DONE frames={report['profile_frames']} slow={len(report['slow_frames'])}", flush=True)
    return 0 if report['profile_frames'] > 0 else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=6017)
    parser.add_argument('--out', type=pathlib.Path, required=True)
    parser.add_argument('--seconds', type=int, default=440)
    parser.add_argument('--function-cap', type=int, default=2048, help='Must match the runner --native-profile-cap')
    args = parser.parse_args()
    if args.function_cap < 1: parser.error('function cap must be positive')
    raise SystemExit(receive(args.port, args.out, args.seconds, args.function_cap))
