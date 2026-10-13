#!/usr/bin/env python3
"""Read-only fake rigctld for owned/reused daemon lifecycle tests."""
import socket,sys,signal
port=int(sys.argv[sys.argv.index('-t')+1])
s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1);s.bind(('127.0.0.1',port));s.listen()
signal.signal(signal.SIGTERM,lambda *_:sys.exit(0))
while True:
 c,_=s.accept()
 with c:
  raw=c.recv(256)
  assert raw==b'f\n',raw
  c.sendall(b'7095000\n')
