from pathlib import Path
import numpy as np
from PIL import Image
import struct,json,hashlib,time
import argparse
project_root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description='Build the shared studio GGX cubemap (requires numpy and Pillow).')
parser.add_argument('--source',type=Path,default=project_root/'godot/assets/studio-source.png')
parser.add_argument('--output',type=Path,default=project_root/'godot/assets')
args=parser.parse_args()
SOURCE=args.source
OUT=args.output;OUT.mkdir(parents=True,exist_ok=True)
SIZE=256;SAMPLES=64
start=time.monotonic()
source=np.asarray(Image.open(SOURCE).convert('RGB'),dtype=np.float64)/255.0

def srgb_to_linear(x):return np.where(x<0.04045,x/12.92,((x+.055)/1.055)**2.4)
def linear_to_srgb(x):return np.where(x<.0031308,12.92*x,1.055*np.maximum(x,0)**(1/2.4)-.055)
def bilinear(img,uv):
 h,w=img.shape[:2];xy=uv*np.array([w,h])-0.5
 x0=np.floor(xy[...,0]).astype(np.int32);y0=np.floor(xy[...,1]).astype(np.int32)
 fx=(xy[...,0]-x0)[...,None];fy=(xy[...,1]-y0)[...,None]
 x1=np.clip(x0+1,0,w-1);y1=np.clip(y0+1,0,h-1);x0=np.clip(x0,0,w-1);y0=np.clip(y0,0,h-1)
 return (img[y0,x0]*(1-fx)+img[y0,x1]*fx)*(1-fy)+(img[y1,x0]*(1-fx)+img[y1,x1]*fx)*fy

def directions(face,size):
 p=(np.arange(size,dtype=np.float64)+.5)/size*2-1
 px,py=np.meshgrid(p,p);one=np.ones_like(px)
 values=[(one,-py,-px),(-one,-py,px),(px,one,py),(px,-one,-py),(px,-py,one),(-px,-py,-one)]
 d=np.stack(values[face],axis=-1);return d/np.linalg.norm(d,axis=-1,keepdims=True)
def sample_panorama(d):
 u=np.arctan2(d[...,0],d[...,2]);u=np.where(u<0,u+2*np.pi,u)/(2*np.pi)
 v=np.arccos(np.clip(d[...,1],-1,1))/np.pi
 return bilinear(source,np.stack([u,v],axis=-1))
base=[np.rint(np.clip(sample_panorama(directions(i,SIZE)),0,1)*255).astype(np.uint8).astype(np.float64)/255 for i in range(6)]

def sample_cube(d):
 flat=d.reshape(-1,3);absd=np.abs(flat);axis=np.argmax(absd,axis=1);major=absd[np.arange(len(flat)),axis]
 face=axis*2+(flat[np.arange(len(flat)),axis]<0).astype(np.int32)
 px=np.empty(len(flat));py=np.empty(len(flat))
 # GL +X,-X,+Y,-Y,+Z,-Z faces, matching reference native face [1,0,3,2,5,4].
 vals=[(-flat[:,2],-flat[:,1]),(flat[:,2],-flat[:,1]),(flat[:,0],flat[:,2]),(flat[:,0],-flat[:,2]),(flat[:,0],-flat[:,1]),(-flat[:,0],-flat[:,1])]
 result=np.empty_like(flat)
 for f in range(6):
  mask=face==f
  if not np.any(mask):continue
  px=vals[f][0][mask]/major[mask];py=vals[f][1][mask]/major[mask]
  result[mask]=bilinear(base[f],np.stack([(px+1)*.5,(py+1)*.5],axis=-1))
 return result.reshape(d.shape)

rad=[]
for i in range(SAMPLES):
 reverse=int(f'{i:032b}'[::-1],2)/2**32
 rad.append(np.floor(np.clip(reverse*255,0,255))/255)
rad=np.asarray(rad,dtype=np.float64)
faces=[[] for _ in range(6)];maxerror=0
for face in range(6):
 for level in range(9):
  size=max(1,SIZE>>level)
  if level==0:encoded=base[face]
  else:
   n=directions(face,size).reshape(-1,3);rough=min(1,level/5);a=rough*rough
   up=np.zeros_like(n);up[:,2]=1
   mask=np.abs(n[:,2])>=.999;up[mask]=np.array([1,0,0])
   tx=np.cross(up,n);tx/=np.linalg.norm(tx,axis=-1,keepdims=True);ty=np.cross(n,tx)
   total=np.zeros_like(n);weight=np.zeros((len(n),1))
   for i in range(SAMPLES):
    phi=2*np.pi*i/SAMPLES;cos=np.sqrt((1-rad[i])/(1+(a*a-1)*rad[i]));sin=np.sqrt(1-cos*cos)
    h=tx*(sin*np.cos(phi))+ty*(sin*np.sin(phi))+n*cos
    l=2*np.sum(n*h,axis=-1,keepdims=True)*h-n
    ndotl=np.clip(np.sum(n*l,axis=-1,keepdims=True),0,1)
    total+=srgb_to_linear(sample_cube(l))*ndotl;weight+=ndotl
   encoded=linear_to_srgb(total/np.maximum(weight,1e-12)).reshape(size,size,3)
  rgba=np.concatenate([np.rint(np.clip(encoded,0,1)*255).astype(np.uint8),np.full((size,size,1),255,dtype=np.uint8)],axis=-1)
  faces[face].append(rgba.tobytes())
 print('filtered face',face,'elapsed',round(time.monotonic()-start,2),flush=True)
face_bytes=sum(len(x) for x in faces[0]);out=OUT/'studio-radiance.bin'
with out.open('wb') as f:
 f.write(struct.pack('<8sIIII',b'QIBL0001',SIZE,9,6,face_bytes))
 for levels in faces:f.write(b''.join(levels))
(OUT/'studio-source.png').write_bytes(SOURCE.read_bytes())
metadata_path=OUT/'studio-radiance.json'
previous=json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
metadata={**previous,'source_file':'studio-source.png','source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'source_url':'https://rescar.2t.hk/vendor/app-resources/shared_misc_textures/New_Studio.png','source_dimensions':[source.shape[1],source.shape[0]],'cube_size':SIZE,'face_order':['+X','-X','+Y','-Y','+Z','-Z'],'mip_count':9,'format':'RGBA8','encoding':'sRGB values in ordinary UNORM texture','integration_space':'linear','samples_per_pixel':64,'radical_inverse':'UNORM8 quantized reference cache','roughness_per_mip':'min(1, level / 5)','diffuse_lod':4,'specular_lod':'roughness * 6','radiance_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'seconds':round(time.monotonic()-start,2),'reference':'Tesla Desk/src/features/three/teslaAppEnvironmentMap.js (Godot 3.2.2 GLES2 GGX filter)'}
(OUT/'studio-radiance.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2))
print('radiance',out.stat().st_size,'source mean RGB',source.mean(axis=(0,1)),'total seconds',round(time.monotonic()-start,2))
