import socket,subprocess,pathlib
root=pathlib.Path(__file__).resolve().parent.parent
s=socket.socket();s.bind(('127.0.0.1',0));port=s.getsockname()[1];s.close()
subprocess.run([str(root/'build/rig-controller-tests'),str(port),str(root/'Tests/fake_rigctld.py')],check=True,timeout=20)
