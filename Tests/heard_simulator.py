"""Heard query integration using loopback only. Never opens real radio ports."""
import json,socket,struct,subprocess,threading,time
listeners=[]
for _ in range(2):
 s=socket.socket();s.bind(('127.0.0.1',0));s.listen();listeners.append(s)
ready=threading.Event();failures=[];done=threading.Event()
def control_frame(obj):
 b=json.dumps(obj,separators=(',',':')).encode();return struct.pack('!I',len(b))+b
def exact(s,n):
 b=b''
 while len(b)<n:
  c=s.recv(n-len(b))
  if not c:raise EOFError()
  b+=c
 return b
def control():
 try:
  with listeners[0].accept()[0] as s:
   s.settimeout(55)
   while not done.is_set():
    obj=json.loads(exact(s,struct.unpack('!I',exact(s,4))[0]))
    if obj['cmd']=='get_config':r={'ok':True,'callsign':'TEST1','modulation':'RDM-600','payload_size':512,'fragmentation_enabled':True}
    elif obj['cmd']=='get_status':r={'ok':True,'channel_state':'idle','audio_connected':True,'tx_queue':0}
    elif obj['cmd']=='rx_frame_history':
     now=time.time();r={'ok':True,'frames':[{'seq':2,'time':now,'callsign':'TEST3','callsign_source':'ax25','snr':-8.5,'size':64},{'seq':1,'time':now-3601,'callsign':'STALE1','callsign_source':'ax25','snr':-7,'size':64}]};ready.set()
    else:raise AssertionError(obj)
    s.sendall(control_frame(r))
 except EOFError:pass
 except Exception as e:failures.append(repr(e))
def address(call,last):return bytes([ord(c)<<1 for c in call.ljust(6)])+bytes([0x60|last])
def packet(source,to,text):
 data=address(to,0)+address(source,1)+b'\x03\xf0'+text.encode();return b'\xc0\x00'+data.replace(b'\xdb',b'\xdb\xdd').replace(b'\xc0',b'\xdb\xdc')+b'\xc0'
def kiss():
 try:
  with listeners[1].accept()[0] as s:
   s.settimeout(55);assert ready.wait(5)
   time.sleep(.1)
   requests=[('TEST2',None),('TEST5','TEST3'),('TEST6','STALE1')]
   ids={}
   for i,(source,q) in enumerate(requests,1):
    id=f'01234567-89AB-CDEF-0123-{i:012d}';ids[id]=(source,q)
    obj={'v':1,'k':'request','id':id,'w':60}
    if q:obj['q']=q
    s.sendall(packet(source,'QST','~Q73H:'+json.dumps(obj,separators=(',',':'))))
   buf=b'';received=set()
   while len(received)<3:
    buf+=s.recv(8192)
    while b'\xc0' in buf:
     frame,buf=buf.split(b'\xc0',1)
     if not frame:continue
     frame=frame.replace(b'\xdb\xdc',b'\xc0').replace(b'\xdb\xdd',b'\xdb')
     assert frame[0]==0;payload=frame[1:]
     text=payload[16:].decode();assert text.startswith('~Q73H:');r=json.loads(text[6:])
     source,q=ids[r['id']];destination=''.join(chr(c>>1) for c in payload[:6]).strip();assert destination==source and r['k']=='reply' and r.get('q')==q
     assert len(text.encode())<=200 and len(r['h'])<=3
     if q=='TEST3':assert r['h'][0][0]=='TEST3' and r['h'][0][2]==-85
     if q=='STALE1':assert r['h']==[]
     received.add(r['id'])
   time.sleep(.3);done.set()
 except Exception as e:failures.append(repr(e));print("Heard fixture error:",repr(e),flush=True);done.set()
threads=[threading.Thread(target=control,daemon=True),threading.Thread(target=kiss,daemon=True)]
for t in threads:t.start()
p=subprocess.run(['build/heard-network-tests',str(listeners[0].getsockname()[1]),str(listeners[1].getsockname()[1])],timeout=55)
done.set()
for t in threads:t.join(timeout=2)
for s in listeners:s.close()
assert p.returncode==0 and not failures,failures
