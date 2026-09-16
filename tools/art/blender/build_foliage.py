"""Offline authored foliage library. Blender 4.5: -b -t 4 --python this_file.
Pine boughs are overlapping curved leaf lobes; broadleaf crowns have rounded,
individually coloured clusters. Exported GLBs are the actual runtime assets.
"""
import bpy, math, random
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'game/resources/models'
SOURCE=ROOT/'art/3d/source'
OUT.mkdir(parents=True,exist_ok=True);SOURCE.mkdir(parents=True,exist_ok=True)

def linear(c):
    return c/12.92 if c<.04045 else ((c+.055)/1.055)**2.4

def material(name,color):
    m=bpy.data.materials.new(name);m.diffuse_color=(*[linear(v/255) for v in color],1)
    m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=m.diffuse_color;p.inputs['Roughness'].default_value=.93
    return m

# Godot (x,y,z) -> Blender (x,-z,y), GLB's Y-up conversion restores the game axes.
def v(p):return Vector((p[0],-p[2],p[1]))
def tube(name,a,b,r1,r2,mat):
    a,b=v(a),v(b);d=b-a
    bpy.ops.mesh.primitive_cone_add(vertices=9,radius1=r1,radius2=r2,depth=d.length,location=(a+b)*.5)
    o=bpy.context.object;o.name=name;o.rotation_mode='QUATERNION';o.rotation_quaternion=d.to_track_quat('Z','Y');o.data.materials.append(mat)
    for p in o.data.polygons:p.use_smooth=True
    return o

def blob(name,pos,scale,mat,seed=0,detail=2):
    rr=random.Random(seed)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=detail,radius=1,location=v(pos))
    o=bpy.context.object;o.name=name
    for p in o.data.vertices:
        n=p.co.normalized(); wave=1+.075*math.sin(n.x*7+n.y*3)+.045*math.cos(n.z*9+n.y*5)
        p.co.x*=scale[0]*wave;p.co.y*=scale[2]*wave;p.co.z*=scale[1]*wave
    o.data.materials.append(mat)
    for p in o.data.polygons:p.use_smooth=True
    return o

def lobe(name,start,end,width,mat):
    # A plump tapered downward frond with a rounded shoulder, not a cone skirt.
    a,b=v(start),v(end);axis=b-a
    side=axis.cross(Vector((0,0,1))).normalized()
    up=side.cross(axis).normalized()
    verts=[]; faces=[]
    rings=6; sides=8
    for j in range(rings):
        t=j/(rings-1);radius=width*(math.sin(math.pi*t)**.64)*(.95-.24*t)+.008
        center=a+axis*t+Vector((0,0,math.sin(math.pi*t)*width*.25))
        for k in range(sides):
            ang=k*2*math.pi/sides
            verts.append(center+side*math.cos(ang)*radius+up*math.sin(ang)*radius*.62)
    for j in range(rings-1):
        for k in range(sides):faces.append((j*sides+k,j*sides+(k+1)%sides,(j+1)*sides+(k+1)%sides,(j+1)*sides+k))
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.materials.append(mat);mesh.update()
    o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
    for p in mesh.polygons:p.use_smooth=True
    return o

def save(species,variant):
    # Merge by material offline; retain separate trunk/crown objects for runtime sway.
    for group in ('Crown','Trunk'):
        objs=[o for o in bpy.context.scene.objects if o.type=='MESH' and (o.name.startswith('Leaf') if group=='Crown' else not o.name.startswith('Leaf'))]
        if not objs:continue
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:o.select_set(True)
        bpy.context.view_layer.objects.active=objs[0];bpy.ops.object.join();bpy.context.object.name=group
        bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    name=f'foliage_{species}_{variant}'
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
    print('ASSET_EXPORTED',name)

for species in ('pine','oak','apple'):
  for variant in range(2):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    random.seed(961+variant*97)
    wood=material('WarmBark',(105,77,46))
    if species=='pine':
        colors=[(43,91,56),(52,108,60),(63,121,66),(75,135,70),(94,146,75),(111,155,79)]
        greens=[material('PineLeaf'+str(i),c) for i,c in enumerate(colors)]
        tube('Trunk',(0,0,0),(.06,6.4,.02),.27,.025,wood)
        for tier in range(7):
            height=1.05+tier*.73;reach=2.25-tier*.255
            count=8 if tier<4 else 7
            for branch in range(count):
                angle=branch*math.tau/count+tier*1.31+variant*.8+random.uniform(-.1,.1)
                direction=Vector((math.cos(angle),0,math.sin(angle)))
                start=Vector((.03,height+.45,0));tip=direction*reach+Vector((0,height+random.uniform(-.1,.12),0))
                tube('Branch',start,tip,.055,.018,wood)
                # Staggered broad fronds overlap along each woody bough.
                for layer in range(4):
                    along=.17+layer*.19
                    origin=start.lerp(tip,along)+Vector((0,.36-layer*.045,0))
                    for side_sign in (-1,1):
                        sideways=Vector((-direction.z,0,direction.x))*side_sign
                        end=origin+direction*(.48+reach*.11)+sideways*(.39-layer*.053)+Vector((0,-.34,0))
                        lobe('LeafBough',origin,end,.24+(6-tier)*.014,greens[min(5,tier//2+random.randrange(3))])
                lobe('LeafTip',start.lerp(tip,.67)+Vector((0,.25,0)),tip+direction*.23+Vector((0,-.17,0)),.29,greens[min(5,tier//2+2)])
        for i in range(4):
            a=i*math.tau/4
            lobe('LeafCrown',(0,5.65,0),(.36*math.cos(a),6.75,.36*math.sin(a)),.28,greens[5])
    else:
        colors=[(69,106,42),(86,125,43),(104,142,47),(123,157,55),(140,167,65),(156,176,73)]
        greens=[material('Broadleaf'+str(i),c) for i,c in enumerate(colors)]
        tube('Trunk',(0,0,0),(.1,3.8,0),.3,.06,wood)
        for root in range(6):
            a=root*math.tau/6;tube('Root',(0,.35,0),(.72*math.cos(a),.04,.72*math.sin(a)),.15,.018,wood)
        for branch in range(12):
            a=branch*2.399;h=2.4+(branch%4)*.47;radius=1.35-(branch%4)*.15
            center=Vector((math.cos(a)*radius,h,math.sin(a)*radius))
            tube('Branch',(.04,1.4+branch%3*.3,0),center,.12,.035,wood)
            for cluster in range(9):
                angle=cluster*2.399+branch
                p=center+Vector((math.cos(angle)*random.uniform(.23,.62),random.uniform(-.12,.5),math.sin(angle)*random.uniform(.23,.62)))
                blob('LeafCluster',p,(random.uniform(.38,.58),random.uniform(.32,.46),random.uniform(.36,.57)),greens[min(5,branch%4+random.randrange(3))],branch*19+cluster)
        for cluster in range(8):
            a=cluster*2.399;blob('LeafTop',(.48*math.cos(a),4.48+random.uniform(-.1,.25),.48*math.sin(a)),(.55,.43,.5),greens[4+cluster%2],cluster)
        if species=='apple':
            fruit=material('AppleVermilion',(188,72,42))
            for i in range(22):
                a=i*2.399;blob('LeafFruit',(math.cos(a)*1.7,2.6+random.random()*1.2,math.sin(a)*1.7),(.105,.12,.105),fruit,i,1)
    save(species,variant)
