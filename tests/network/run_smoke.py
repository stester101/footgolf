"""Run two Godot peers against an already running localhost relay."""
import pathlib
import subprocess
import tempfile
import time
import json

with tempfile.TemporaryDirectory(prefix="footgolf-net-") as tmp:
    path = pathlib.Path(tmp)
    code = path / 'code'
    processes = []
    try:
        host_log = (path / 'host.log').open('w')
        base = ['godot', '--headless', '--path', '.', '-s', 'res://tests/network/peer_smoke.gd', '--', f'--code-path={code}']
        host = subprocess.Popen(base + ['--host'], stdout=host_log, stderr=subprocess.STDOUT)
        processes.append(host)
        until = time.monotonic() + 15
        while not code.exists() and host.poll() is None and time.monotonic() < until:
            time.sleep(.1)
        if not code.exists():
            raise RuntimeError('Host did not create a room')
        guest_log = (path / 'guest.log').open('w')
        guest = subprocess.Popen(base, stdout=guest_log, stderr=subprocess.STDOUT)
        processes.append(guest)
        for process in processes:
            process.wait(timeout=40)
        snapshots = []
        for name in ['host', 'guest']:
            text = (path / f'{name}.log').read_text()
            assert 'SCRIPT ERROR' not in text and 'NETWORK FAIL' not in text, text
            line = next(line for line in text.splitlines() if line.startswith('NETWORK PASS'))
            snapshots.append(json.loads(line[line.index('{'):]))
            print(f'{name}: PASS — round finished after host and guest reconnected')
        for key in ['slots', 'pool', 'turn', 'state', 'counter', 'history']:
            assert snapshots[0][key] == snapshots[1][key], f'{key} diverged'
        assert all(p.returncode == 0 for p in processes)
        print('PASS — host/client positions, scores, history and shared pool match exactly')
    except Exception:
        for log in path.glob('*.log'):
            print(log.name, log.read_text()[-8000:])
        raise
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
