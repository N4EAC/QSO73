"""Loopback-only native UDP service check. No PSK Reporter uploads."""
import socket
import struct
import subprocess
sock=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
sock.bind(('127.0.0.1',0));sock.settimeout(10)
p=subprocess.Popen(['build/psk-transport-tests',str(sock.getsockname()[1])])
try:
 data,_=sock.recvfrom(2048)
 assert len(data)<1400 and struct.unpack_from('!H',data)[0]==10
 assert struct.unpack_from('!H',data,2)[0]==len(data)
 assert b'TEST1' in data and b'AA00AA' in data and b'TEST2' in data and b'PKT' in data
 assert p.wait(timeout=10)==0
 print('PASS: received complete IPFIX datagram on loopback UDP socket')
finally:
 sock.close()
 if p.poll() is None:p.kill()
