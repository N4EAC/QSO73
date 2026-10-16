from pathlib import Path
import re, html
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, KeepTogether
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import letter

root=Path(__file__).resolve().parents[1]
output=root/'output/pdf/QSO73-User-Manual.pdf'
output.parent.mkdir(parents=True,exist_ok=True)
styles=getSampleStyleSheet()
navy=colors.HexColor('#14354A'); teal=colors.HexColor('#087F8C')
styles.add(ParagraphStyle(name='BodyManual',fontName='Helvetica',fontSize=10,leading=13.4,spaceAfter=7,textColor=colors.HexColor('#243746')))
styles.add(ParagraphStyle(name='SectionManual',fontName='Helvetica-Bold',fontSize=23,leading=28,spaceAfter=16,textColor=navy,keepWithNext=True))
styles.add(ParagraphStyle(name='SubManual',fontName='Helvetica-Bold',fontSize=12,leading=16,spaceBefore=8,spaceAfter=7,textColor=teal,keepWithNext=True))
styles.add(ParagraphStyle(name='TableManual',fontName='Helvetica',fontSize=9.1,leading=11.8,textColor=navy))
styles.add(ParagraphStyle(name='TableHeadManual',fontName='Helvetica-Bold',fontSize=9.1,leading=11.8,textColor=colors.white))
styles.add(ParagraphStyle(name='TitleManual',fontName='Helvetica-Bold',fontSize=34,leading=40,spaceAfter=18,textColor=navy))

def inline(s):
    s=html.escape(s,quote=False)
    s=re.sub(r'\*\*(.+?)\*\*',r'<b>\1</b>',s)
    s=re.sub(r'`([^`]+)`',r'<font name="Courier" size="9">\1</font>',s)
    if s.startswith('Engine source: '):
        s='<b>Engine source:</b> <a color="#087F8C" href="'+s.split(': ',1)[1]+'">Bundled modem73 2.4.2 source</a>'
    if s.startswith('Upstream operating guidance: '):
        s='<b>Operating guidance:</b> <a color="#087F8C" href="'+s.split(': ',1)[1]+'">modem73 quickstart</a>'
    return s

def para(s,sty='BodyManual'):
    style=styles[sty]
    if number in (2,10,15) and sty=='BodyManual': style=ParagraphStyle(name='compact',parent=style,fontSize=9.7,leading=12.4,spaceAfter=5)
    if number == 10 and sty=='BodyManual': style=ParagraphStyle(name='activity-compact',parent=style,fontSize=9.2,leading=11.4,spaceAfter=3)
    return Paragraph(inline(s),style)
story=[]
sections=(root/'USER_MANUAL.md').read_text().split('<!-- page -->')
for number,section in enumerate(sections):
    if number: story.append(PageBreak())
    lines=section.strip().splitlines(); i=0
    while i<len(lines):
        line=lines[i].strip()
        if not line: i+=1; continue
        if line.startswith('|'):
            rows=[]
            while i<len(lines) and lines[i].strip().startswith('|'):
                cells=[s.strip() for s in lines[i].strip().strip('|').split('|')]
                if not all(re.fullmatch(r'[-: ]+',s) for s in cells): rows.append(cells)
                i+=1
            count=len(rows[0]); widths=[516/count]*count
            if number==0: widths=[44,472]
            elif number==2 and count==2: widths=[145,371]
            elif number==4: widths=[106,78,332]
            elif number==5 and count==3: widths=[110,95,311]
            elif number==9 and count==3: widths=[130,292,94]
            elif number==10 and count==2: widths=[147,369]
            table=Table([[para(cell,'TableHeadManual' if r==0 else 'TableManual') for cell in row] for r,row in enumerate(rows)],colWidths=widths,repeatRows=1,hAlign='LEFT')
            table.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),navy),('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.HexColor('#EDF5F6'),colors.white]),('VALIGN',(0,0),(-1,-1),'TOP'),('LEFTPADDING',(0,0),(-1,-1),8),('RIGHTPADDING',(0,0),(-1,-1),8),('TOPPADDING',(0,0),(-1,-1),1.5 if number==0 else 3 if number==10 else 4),('BOTTOMPADDING',(0,0),(-1,-1),1.5 if number==0 else 3 if number==10 else 4),('LINEBELOW',(0,-1),(-1,-1),0.5,colors.HexColor('#C8DADF'))]))
            story += [table,Spacer(1,9)]
            continue
        if line.startswith('# '):
            story.append(para(line[2:],'TitleManual' if number==0 else 'SectionManual'))
        elif line.startswith('## '): story.append(para(line[3:],'SubManual'))
        elif line.startswith('### '): story.append(para(line[4:],'SubManual'))
        elif re.match(r'^\d+\. ',line):
            item=re.match(r'^(\d+)\. (.*)',line)
            story.append(Paragraph(inline(item[2]),ParagraphStyle(name='step',parent=styles['BodyManual'],fontSize=9.5 if number==15 else 10,leading=12 if number==15 else 13.4,spaceAfter=5 if number==15 else 7,leftIndent=18,firstLineIndent=0,bulletIndent=0),bulletText=item[1]+'.'))
        elif line.startswith('- '):
            story.append(Paragraph(inline(line[2:]),ParagraphStyle(name='bullet',parent=styles['BodyManual'],leftIndent=13,bulletIndent=0),bulletText='-'))
        else:
            block=[line]
            while i+1<len(lines) and lines[i+1].strip() and not lines[i+1].strip().startswith(('#','|','- ')) and not re.match(r'^\d+\. ',lines[i+1].strip()):
                i+=1; block.append(lines[i].strip())
            story.append(para(' '.join(block)))
        i+=1

def decoration(canvas,doc):
    canvas.saveState()
    w,h=letter
    canvas.setStrokeColor(teal);canvas.setLineWidth(2);canvas.line(48,h-37,w-48,h-37)
    canvas.setFont('Helvetica-Bold',8);canvas.setFillColor(navy)
    canvas.drawString(48,h-28,'QSO73  /  USER MANUAL')
    canvas.setFont('Helvetica',8);canvas.setFillColor(colors.HexColor('#627581'))
    canvas.drawRightString(w-48,h-28,'Version 1.1.0')
    canvas.setStrokeColor(colors.HexColor('#D4E1E5'));canvas.setLineWidth(.5);canvas.line(48,40,w-48,40)
    canvas.drawString(48,27,'October 15, 2026  |  macOS / Windows')
    canvas.drawRightString(w-48,27,str(doc.page))
    canvas.restoreState()

doc=SimpleDocTemplate(str(output),pagesize=letter,leftMargin=48,rightMargin=48,topMargin=56,bottomMargin=53,title='QSO73 User Manual - Version 1.1.0',author='QSO73',subject='Radio setup, channels, direct chat and modem mode selection')
doc.build(story,onFirstPage=decoration,onLaterPages=decoration)
print(output)
