import cv2, numpy as np, sys, os
label=sys.argv[1]; view=sys.argv[2]
cases=['01-idle','02-walk-a','03-walk-b','04-run','05-aim','06-aim-recoil','07-aim-walk','08-reload','09-fists-guard']
tiles=[]
for c in cases:
    f=cv2.imread('%s/%s-%s.png'%(label,c,view))
    f=f[100:820,150:750] if view!='iso' else f[80:860,120:780]
    f=cv2.resize(f,(300,int(300*f.shape[0]/f.shape[1])))
    cv2.putText(f,c,(6,18),cv2.FONT_HERSHEY_SIMPLEX,.5,(255,255,255),1,cv2.LINE_AA)
    tiles.append(f)
h=max(t.shape[0] for t in tiles)
tiles=[cv2.copyMakeBorder(t,0,h-t.shape[0],0,0,cv2.BORDER_CONSTANT) for t in tiles]
rows=[np.hstack(tiles[i:i+3]) for i in range(0,9,3)]
cv2.imwrite('%s_%s_sheet.jpg'%(label,view),np.vstack(rows))
