"""Trace review overlay and vegetation mask from the user-supplied scale map."""
from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFilter
ROOT=Path(__file__).resolve().parents[2]
data=json.loads((ROOT/'game/resources/maps/first_map_blueprint.json').read_text())
im=Image.open(ROOT/'docs/art/reference/first-map-scale.png').convert('RGB')
mask=Image.new('L',im.size)
p=im.load();m=mask.load()
for y in range(im.height):
    for x in range(im.width):
        r,g,b=p[x,y]
        m[x,y]=255 if g>r*1.12 and g>b*1.15 and (r+g+b)/3<127 and g>40 else 0
mask=mask.filter(ImageFilter.GaussianBlur(5))
d=ImageDraw.Draw(mask)
for region in data['regions']:
    if region['id'] in ['player_farm','npc_farm','town','homes','harbor','lake']:
        x,y,w,h=region['rect'];d.rectangle((x,y,x+w,y+h),fill=0)
mask.resize((328,300),Image.Resampling.LANCZOS).save(ROOT/'game/resources/maps/forest_mask.png')
preview=im.convert('RGBA');overlay=Image.new('RGBA',im.size);d=ImageDraw.Draw(overlay)
for water in data['waters']:d.line(water['points'],fill=(39,206,241,220),width=4)
for lake in data['lakes']:d.line(lake['polygon']+[lake['polygon'][0]],fill=(39,206,241,220),width=4)
d.line(data['coast'],fill=(255,245,171,240),width=4)
for road in data['roads']:d.line(road['points'],fill=(250,213,73,220),width=3)
for building in data['buildings']:
    x,y=building['at'];d.ellipse((x-5,y-5,x+5,y+5),fill=(238,77,69,250),outline='white',width=1)
for bridge in data['bridges']:
    x,y,w,h=bridge['rect'];d.rectangle((x,y,x+w,y+h),outline=(249,119,224,255),width=3)
preview=Image.alpha_composite(preview,overlay)
preview.save(ROOT/'docs/maps/first-map-trace.png')
print('TRACE_CREATED',data['image_size'][0]*400/202,data['image_size'][1]*400/202)
