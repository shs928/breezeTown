"""Reproducible painted ground textures used by the playable reference farm."""
from pathlib import Path
import random, math
from PIL import Image, ImageDraw, ImageFilter
OUT=Path(__file__).resolve().parents[2]/'game/resources/materials/terrain'
OUT.mkdir(parents=True,exist_ok=True)
for name,base in [('earth',(173,130,75)),('grass',(106,136,55)),('stone',(158,153,129))]:
    r=random.Random(902+len(name)); n=512
    im=Image.new('RGB',(n,n),base); d=ImageDraw.Draw(im)
    for i in range(17000):
        x=r.randrange(-12,n+12); y=r.randrange(-8,n+8); v=r.gauss(0,8)
        tint=tuple(max(0,min(255,int(c+v))) for c in base)
        length=r.randrange(2,22); width=r.randrange(1,6)
        d.ellipse((x,y,x+length,y+width), fill=tint)
    im=im.filter(ImageFilter.GaussianBlur(.75))
    d=ImageDraw.Draw(im)
    for i in range(3400):
        x=r.randrange(n);y=r.randrange(n);v=r.choice([-17,-9,8,14]); size=r.choice([1,1,2,3])
        d.ellipse((x,y,x+size,y+max(1,size//2)),fill=tuple(max(0,min(255,c+v)) for c in base))
    im.save(OUT/(name+'.png'))
print(OUT)
