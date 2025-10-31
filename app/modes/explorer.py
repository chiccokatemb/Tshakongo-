import os, time, cv2, json, threading
from datetime import datetime
from app.motors import forward, left_turn, stop
from app.env import get_env_snapshot
REPORT_DIR="reports"; SNAP_DIR="logs"; os.makedirs(REPORT_DIR,exist_ok=True); os.makedirs(SNAP_DIR,exist_ok=True)
class Explorer:
    def __init__(self, camera, detector=lambda f: [], socketio=None):
        self.cam=camera; self.detector=detector; self.io=socketio; self.active=False
    def start(self, t=25):
        if self.active: return
        self.active=True; threading.Thread(target=self._run, args=(t,), daemon=True).start()
    def stop(self): self.active=False; stop()
    def _emit(self,ev,p): 
        try: self.io and self.io.emit(ev,p)
        except: pass
    def _run(self, dur):
        start=time.time(); unknown=0; known=set(); pets=set(); snaps=[]
        try:
            while self.active and time.time()-start<dur:
                ok,frame=self.cam.read()
                if not ok: time.sleep(0.03); continue
                dets=self.detector(frame); env=get_env_snapshot()
                for d in dets:
                    c=d.get("cls")
                    if c=="unknown_face": unknown+=1
                    elif c in ("Yoshi","Michka"): pets.add(c)
                    elif c and c!="person": known.add(c)
                danger = (env.get("gas",0)>=200) or (env.get("temp",25)<5 or env.get("temp",25)>40) or (env.get("humid",40)>=80)
                if danger:
                    p=os.path.join(SNAP_DIR,f"danger_{int(time.time())}.jpg"); cv2.imwrite(p,frame); snaps.append(p)
                forward(0.25,0.5); left_turn(0.35,0.2); stop()
                self._emit("explorer_tick",{"known":sorted(list(known)),"unknown_count":unknown,"pets":sorted(list(pets)),"env":env})
            rep={"ts":datetime.now().isoformat(),"known":sorted(list(known)),"unknown_count":unknown,"pets":sorted(list(pets))}
            rp=os.path.join(REPORT_DIR,f"explore_{int(time.time())}.json"); open(rp,"w").write(json.dumps(rep,indent=2))
            self._emit("explorer_done",{**rep,"snapshots":snaps})
        finally:
            stop(); self.active=False
