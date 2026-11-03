from pathlib import Path
import numpy as np,trimesh,json,hashlib
import argparse
parser=argparse.ArgumentParser(description='Remove only degenerate and same-normal duplicate faces; requires numpy and trimesh.')
parser.add_argument('source',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args()
src=args.source;dst=args.output
if src.resolve()==dst.resolve(): raise SystemExit('Use a separate output file; source is preserved.')
dst.parent.mkdir(parents=True,exist_ok=True)
s=trimesh.load(src,force='scene',process=False);result=trimesh.Scene();rows=[]
for name,m in s.geometry.items():
 v=m.vertices;f=m.faces.copy();norm=m.vertex_normals.copy();cross=np.cross(v[f[:,1]]-v[f[:,0]],v[f[:,2]]-v[f[:,0]]);areas2=np.linalg.norm(cross,axis=1);keep=areas2>=1e-10
 removed_degenerate=int((~keep).sum());dup=0;seen={}
 for i in np.where(keep)[0]:
  tri=f[i];points=np.round(v[tri],7);order=np.lexsort(points.T[::-1]);key=points[order].tobytes()
  # Delete only same position + same shading normal duplicates, preserving intentionally opposite surfaces.
  normals=norm[tri][order]
  if key in seen and np.all(np.sum(normals*seen[key],axis=1)>.999):keep[i]=False;dup+=1
  else:seen[key]=normals
 new=trimesh.Trimesh(vertices=v.copy(),faces=f[keep],vertex_normals=norm,visual=m.visual.copy(),process=False)
 # No smoothing, simplification, weld, pivot, transform or material change.
 result.add_geometry(new,node_name=name,geom_name=name)
 rows.append({'name':name,'faces_before':len(f),'faces_after':int(keep.sum()),'removed_degenerate':removed_degenerate,'removed_duplicate':dup})
dst.write_bytes(result.export(file_type='glb'))
loaded=trimesh.load(dst,force='scene',process=False)
assert set(loaded.geometry)==set(s.geometry)
assert np.allclose(loaded.bounds,s.bounds,rtol=0,atol=1e-6)
assert all(np.isfinite(m.vertices).all() and np.isfinite(m.vertex_normals).all() and m.faces.max()<len(m.vertices) for m in loaded.geometry.values())
report={'source':str(src),'candidate':str(dst),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'meshes':len(rows),'vertices_before':sum(len(m.vertices) for m in s.geometry.values()),'vertices_after':sum(len(m.vertices) for m in loaded.geometry.values()),'faces_before':sum(r['faces_before'] for r in rows),'faces_after':sum(r['faces_after'] for r in rows),'removed_degenerate':sum(r['removed_degenerate'] for r in rows),'removed_duplicate':sum(r['removed_duplicate'] for r in rows),'bounds_before':s.bounds.tolist(),'bounds_after':loaded.bounds.tolist(),'rows':rows}
dst.with_suffix('.cleanup.json').write_text(json.dumps(report,indent=2));print({k:v for k,v in report.items() if k!='rows'})
