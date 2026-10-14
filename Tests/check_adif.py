from pathlib import Path
import re,datetime
parsed=[]
for file in ('/tmp/qso73-contact-mac.adi','/tmp/qso73-contact-windows.adi'):
 text=Path(file).read_text(encoding='ascii');pos=text.index('<');records=[];record={};header=True
 while pos<len(text):
  if text[pos].isspace():pos+=1;continue
  marker=re.match(r'<(EOH|EOR)>',text[pos:],re.I)
  if marker:
   pos+=marker.end()
   if marker[1].upper()=='EOH':header=False;record={}
   else:records.append(record);record={}
   continue
  tag=re.match(r'<([A-Z0-9_]+):(\d+)>',text[pos:]);assert tag,(file,pos)
  length=int(tag[2]);pos+=tag.end();value=text[pos:pos+length];assert len(value)==length
  record[tag[1]]=value;pos+=length
 assert len(records)==1 and not header and not record
 c=records[0];assert c['CALL']=='K1ABC/P' and c['STATION_CALLSIGN']=='N4EAC' and c['MODE']=='PKT' and c['BAND']=='40m'
 assert c['COMMENT']=='A<B> & test'
 start=datetime.datetime.strptime(c['QSO_DATE']+c['TIME_ON'],'%Y%m%d%H%M%S');end=datetime.datetime.strptime(c['QSO_DATE_OFF']+c['TIME_OFF'],'%Y%m%d%H%M%S')
 assert (end-start).total_seconds()==15
 parsed.append(c)
assert parsed[0]==parsed[1]
print('PASS: independent ADIF field-length parser, portable calls, PKT/band and UTC rollover match both platforms')
