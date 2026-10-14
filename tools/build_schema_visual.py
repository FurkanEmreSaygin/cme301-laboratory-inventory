from pathlib import Path
from html import escape
import math
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / 'output' / 'schema-review'
OUT.mkdir(parents=True, exist_ok=True)
W, H, SCALE = 1580, 1300, 2
im = Image.new('RGB', (W*SCALE, H*SCALE), '#F5F7FB')
d = ImageDraw.Draw(im)
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', '<rect width="100%" height="100%" fill="#F5F7FB"/>']
FONT = Path('C:/Windows/Fonts')

def text(x, y, s, size=20, color='#17263C', bold=False, mono=False):
    file = 'consola.ttf' if mono else ('segoeuib.ttf' if bold else 'segoeui.ttf')
    font = ImageFont.truetype(str(FONT/file), size*SCALE)
    d.text((x*SCALE, y*SCALE), s, fill=color, font=font)
    family = 'Consolas, monospace' if mono else 'Segoe UI, Arial, sans-serif'
    svg.append(f'<text x="{x}" y="{y+size}" fill="{color}" font-family="{family}" font-size="{size}" font-weight="{700 if bold else 400}">{escape(s)}</text>')

def rect(x,y,w,h,fill,stroke=None,r=0):
    box = (x*SCALE,y*SCALE,(x+w)*SCALE,(y+h)*SCALE)
    d.rounded_rectangle(box,radius=r*SCALE,fill=fill,outline=stroke,width=2 if stroke else 1)
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+'/>')

def line(points,color='#6B7D94',width=2,dashed=False):
    if dashed:
        for a,b in zip(points,points[1:]):
            length=math.dist(a,b)
            if not length: continue
            for start in range(0,int(length),11):
                end=min(start+6,length)
                p=(a[0]+(b[0]-a[0])*start/length,a[1]+(b[1]-a[1])*start/length)
                q=(a[0]+(b[0]-a[0])*end/length,a[1]+(b[1]-a[1])*end/length)
                d.line([(p[0]*SCALE,p[1]*SCALE),(q[0]*SCALE,q[1]*SCALE)],fill=color,width=width*SCALE)
    else:
        d.line([(x*SCALE,y*SCALE) for x,y in points],fill=color,width=width*SCALE)
    svg.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in points)+f'" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"'+(' stroke-dasharray="6 5"' if dashed else '')+'/>')

def circle(x,y,r=5,color='#6B7D94'):
    d.ellipse(((x-r)*SCALE,(y-r)*SCALE,(x+r)*SCALE,(y+r)*SCALE),fill='#F5F7FB',outline=color,width=2*SCALE)
    svg.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#F5F7FB" stroke="{color}" stroke-width="2"/>')

def cardinal(end,neighbor,kind,color):
    length=math.dist(end,neighbor)
    ux,uy=(neighbor[0]-end[0])/length,(neighbor[1]-end[1])/length
    vx,vy=-uy,ux
    def p(t,o=0): return (end[0]+ux*t+vx*o,end[1]+uy*t+vy*o)
    if kind in ('one','optional'):
        line([p(7,-7),p(7,7)],color)
        if kind=='one': line([p(16,-7),p(16,7)],color)
        else: circle(*p(20),color=color)
    else:
        for offset in (-8,0,8): line([p(16),p(3,offset)],color)
        circle(*p(26),color=color)

def edge(points,optional=False,ident=False,color='#6B7D94',label=None,lpos=None):
    line(points,color,2,not ident)
    cardinal(points[0],points[1],'optional' if optional else 'one',color)
    cardinal(points[-1],points[-2],'many',color)
    if label:
        x,y=lpos
        rect(x-6,y-3,len(label)*9+12,27,'#F5F7FB',r=4)
        text(x,y,label,16,color)

text(60,36,'CME301  /  DATABASE DESIGN',17,'#63728A',True)
text(60,70,'Laboratuvar envanter sistemi',40,bold=True)
text(60,132,'Mevcut SQL şeması • Ana stok modeli • 9 / 16 tablo',21,'#63728A')

# All drawn edges correspond to existing foreign keys between the nine shown tables.
edge([(370,315),(430,315)],ident=True,color='#338B80')
edge([(800,315),(740,315)],ident=True,color='#338B80')
edge([(1170,315),(1110,315)])
edge([(955,440),(955,620)],label='bir ürün, birden çok lot',lpos=(980,550))
edge([(215,440),(215,520),(875,520),(875,620)],optional=True,label='tedarik eder · opsiyonel',lpos=(360,482))
edge([(370,720),(430,720)],color='#8370A8')
edge([(800,720),(740,720)])
edge([(1110,720),(1170,720)],ident=True,color='#338B80')
edge([(1325,1010),(1325,840)],ident=True,color='#338B80',label='konum bazında miktar',lpos=(1347,920))
edge([(1170,1100),(1050,1100),(1050,940),(530,940),(530,840)],label='kaynak / işlem konumu',lpos=(650,948))
edge([(1170,1060),(1090,1060),(1090,900),(600,900),(600,840)],optional=True,color='#889AB2',label='hedef · yalnızca TRANSFER',lpos=(650,871))
edge([(1480,1070),(1530,1070),(1530,1160),(1480,1160)],optional=True)
text(1495,1190,'parent_id',15,'#63728A',mono=True)

def card(x,y,name,fields,accent,h=220):
    rect(x+3,y+5,310,h,'#E4E9F0',r=12)
    rect(x,y,310,h,'#FFFFFF','#D8E0EA',12)
    rect(x+1,y+1,308,48,accent,r=11)
    rect(x+1,y+30,308,20,accent)
    text(x+18,y+9,name,23,'#FFFFFF',True)
    for i,(tag,field) in enumerate(fields):
        yy=y+61+i*23
        if tag: text(x+16,yy,tag,13,accent,True)
        text(x+83,yy-3,field,18,mono=True)

blue='#345F97'; teal='#287D74'; purple='#796094'
card(60,220,'SUPPLIER',[('PK','supplier_id'),('','name'),('','lead_time_days')],teal)
card(430,220,'ITEM_SUPPLIER',[('PK/FK','item_id'),('PK/FK','supplier_id'),('','unit_price'),('','currency')],teal)
card(800,220,'ITEM',[('PK','item_id'),('FK','category_id'),('','catalog_no'),('','item_type'),('','unit'),('','min_stock')],blue)
card(1170,220,'CATEGORY',[('PK','category_id'),('','name')],blue)
card(60,620,'APP_USER',[('PK','user_id'),('FK','role_id'),('','username')],purple)
card(430,620,'STOCK_TRANSACTION',[('PK','txn_id'),('FK','lot_id'),('FK','location_id'),('FK','to_location_id'),('FK','user_id'),('','txn_type'),('','quantity')],blue)
card(800,620,'LOT',[('PK','lot_id'),('FK','item_id'),('FK','supplier_id'),('','lot_no'),('','expiry_date')],blue)
card(1170,620,'STOCK',[('PK/FK','lot_id'),('PK/FK','location_id'),('','quantity')],teal)
card(1170,1010,'LOCATION',[('PK','location_id'),('FK','parent_id'),('','name'),('','location_type')],blue,h=180)

text(60,1020,'SUNUMDAKİ ANA FİKİR',16,'#63728A',True)
text(60,1052,'Ürün → Lot → Konumdaki stok',29,bold=True)
text(60,1098,'STOCK mevcut miktarı; STOCK_TRANSACTION hareket geçmişini tutar.',19,'#63728A')
text(60,1130,'Alanlar sadeleştirilmiştir. Destek tabloları tam ER kaynağında yer alır.',18,'#63728A')
line([(60,1205),(1480,1205)],'#D8E0EA',1)
text(60,1230,'||  bir     o|  sıfır veya bir     o<  sıfır veya çok',17,'#63728A',mono=True)
text(810,1230,'Düz çizgi: FK, bileşik PK’nin parçası • Kesikli: diğer FK',16,'#63728A')

svg.append('</svg>')
(OUT/'ana-stok-modeli.svg').write_text('\n'.join(svg),encoding='utf-8')
im.save(OUT/'ana-stok-modeli.png')
print(OUT/'ana-stok-modeli.svg')
print(OUT/'ana-stok-modeli.png')
