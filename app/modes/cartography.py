import os, json, time, math, threading
from datetime import datetime
from app.lidar import get_points
from app.motors import forward, left_turn, stop
MAP_DIR = os.path.join("maps"); os.makedirs(MAP_DIR, exist_ok=True)
class Cartographer:
    def __init__(self, socketio=None): self.active=False; self.pose=[0,0,0]; self.cloud=[]; self.io=socketio
    def start(self):
        if self.active: return
        self.active=True; threading.Thread(target=self._loop,daemon=True).start()
    def stop(self):
        self.active=False; stop()
        p=os.path.join(MAP_DIR, f"map_{int(time.time())}.json")
        with open(p,"w") as f: json.dump({"pose":self.pose,"points":self.cloud},f)
        return p
    def _emit(self,ev,p): 
        try: self.io and self.io.emit(ev,p)
        except: pass
    def _loop(self):
        last=0
        while self.active:
            pts=get_points()
            th=self.pose[2]; c,s=math.cos(th),math.sin(th)
            for lx,ly in pts:
                wx=self.pose[0]+(lx*c-ly*s); wy=self.pose[1]+(lx*s+ly*c)
                self.cloud.append([wx,wy])
            forward(0.25,0.25); left_turn(0.35,0.15); stop(); self.pose[2]+=math.radians(10)
            if time.time()-last>0.5: last=time.time(); self._emit("map_points",{"points":self.cloud[-1500:]})
