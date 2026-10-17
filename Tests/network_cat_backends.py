"""Exercise real Hamlib network backends against local simulated radios only."""
import contextlib, re, shutil, socket, subprocess, threading, time
from xmlrpc.server import SimpleXMLRPCServer, SimpleXMLRPCRequestHandler
class Handler(SimpleXMLRPCRequestHandler):
    protocol_version = "HTTP/1.1"
class FLRigServer(SimpleXMLRPCServer):
    def _marshaled_dispatch(self, data, dispatch_method=None, path=None):
        # Hamlib includes FLRig's nonstandard clientid processing instruction.
        # FLRig accepts it; Python's strict XML parser needs it removed.
        data = re.sub(rb'<\?clientid=.*?\?>', b'', data)
        return super()._marshaled_dispatch(data, dispatch_method, path)

def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]

@contextlib.contextmanager
def daemon(model, endpoint=None):
    port = free_port()
    args = [shutil.which('rigctld'), '-m', str(model), '-T', '127.0.0.1', '-t', str(port), '-P', 'RIG']
    if endpoint:
        args += ['-r', endpoint]
    with subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=open("/tmp/qso73-network-backend.log", "w")) as p:
        try:
            yield port, p
        finally:
            p.terminate()
            try: p.wait(timeout=3)
            except subprocess.TimeoutExpired: p.kill(); p.wait()

def read_frequency(port, child):
    for _ in range(12):
        assert child.poll() is None, 'rigctld exited during network startup'
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=.5) as c:
                c.sendall(b'f\n')
                data = b''
                while b'\n' not in data:
                    chunk = c.recv(512)
                    if not chunk: break
                    data += chunk
                if float(data.split(b'\n')[0]) == 7105000: return
        except (OSError, ValueError): pass
        time.sleep(.1)
    raise AssertionError('Network backend did not return the simulated frequency; see /tmp/qso73-network-backend.log')

class FakeFLRig:
    def __init__(self): self.methods = set()
    def _dispatch(self, method, args):
        self.methods.add(method)
        if method == 'main.get_version': return '1.4.8'
        if method == 'rig.get_xcvr': return 'QSO73 OFFLINE TEST'
        if method in ('rig.get_vfoA', 'rig.get_vfoB', 'rig.get_vfo'): return 7105000.0
        if method in ('rig.get_mode', 'rig.get_modeA', 'rig.get_modeB'): return 'USB'
        if method == 'rig.get_modes': return ['USB', 'LSB', 'CW']
        if method == 'rig.get_AB': return 'A'
        if method in ('rig.get_bwA', 'rig.get_bwB', 'rig.get_bw'): return '3000'
        if method == 'rig.get_bws': return ['3000']
        if method == 'rig.get_agc_labels': return ['OFF', 'FAST', 'SLOW']
        return 0

if __name__ == '__main__':
    if not shutil.which('rigctld'): raise SystemExit('Hamlib rigctld required for loopback backend tests')
    # Configurable FLRig XML-RPC port must be different from the local rigctld port.
    server = FLRigServer(('127.0.0.1', 0), logRequests=False, allow_none=True, requestHandler=Handler)
    fake = FakeFLRig(); server.register_instance(fake)
    thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
    try:
        with daemon(4, f'127.0.0.1:{server.server_address[1]}') as (port, child):
            read_frequency(port, child)
        assert 'rig.get_vfoA' in fake.methods or 'rig.get_vfo' in fake.methods
    finally:
        server.shutdown(); server.server_close(); thread.join(timeout=2)
    # Network rigctl wraps a separate simulated upstream daemon.
    with daemon(1) as (upstream, dummy):
        time.sleep(.25)
        with socket.create_connection(('127.0.0.1', upstream), timeout=2) as c:
            c.sendall(b'F 7105000\n'); assert c.recv(128).startswith(b'RPRT 0')
        with daemon(2, f'127.0.0.1:{upstream}') as (port, child):
            read_frequency(port, child)
        assert dummy.poll() is None, 'Upstream daemon must remain running'
    print('PASS: actual Hamlib FLRig XML-RPC and NET rigctl backends read simulated radios on custom loopback ports')
