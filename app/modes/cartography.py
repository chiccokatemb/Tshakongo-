import os, json, time, math, threading
from datetime import datetime
from app.lidar import get_points
from app.motors import forward, left_turn, stop

MAP_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "maps")
os.makedirs(MAP_DIR, exist_ok=True)

class Cartographer:
    def __init__(self, oled_set_mode=lambda m:None, socketio=None):
        self.active=False; self.pose=[0.0,0.0,0.0]; self.cloud=[]; self._t=None
        self.oled_set_mode=oled_set_mode; self.socketio=socketio

    def start(self):
        if self.active: return
        self.active=True; self.oled_set_mode("Cartographie")
        self._t=threading.Thread(target=self._loop,daemon=True); self._t.start()

    def stop(self):
        self.active=False; stop(); self.oled_set_mode("Idle")
        ts=datetime.now().strftime("%Y%m%d_%H%M%S")
        path=os.path.join(MAP_DIR,f"map_{ts}.json")
        with open(path,"w") as f: json.dump({"pose":self.pose,"points":self.cloud},f)
        return path

    def _emit(self,chan,payload):
        try:
            if self.socketio: self.socketio.emit(chan,payload)
        except: pass

    def _loop(self):
        try:
            last=0
            while self.active:
                pts=get_points()  # [(x_mm, y_mm)]
                th=self.pose[2]; c,s=math.cos(th),math.sin(th)
                for lx,ly in pts:
                    wx=self.pose[0]+(lx*c-ly*s); wy=self.pose[1]+(lx*s+ly*c)
                    self.cloud.append([wx,wy])
                forward(0.25); time.sleep(0.30); stop()
                self.pose[0]+=30.0*math.cos(self.pose[2]); self.pose[1]+=30.0*math.sin(self.pose[2])
                left_turn(0.35); time.sleep(0.15); stop(); self.pose[2]+=math.radians(10)
                now=time.time()
                if now-last>0.5:
                    last=now; self._emit("map_points",{"points":self.cloud[-1200:]})
        finally:
            stop()
