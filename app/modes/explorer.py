import os, time, cv2, json, threading
from datetime import datetime
from app.motors import forward, left_turn, stop

REPORT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "reports")
SNAP_DIR   = os.path.join(os.path.dirname(__file__), "..", "..", "logs")
os.makedirs(REPORT_DIR, exist_ok=True); os.makedirs(SNAP_DIR, exist_ok=True)

class Explorer:
    def __init__(self, camera, detect_fn, sensor_fn, oled_set_mode=lambda m:None, socketio=None):
        self.cam=camera; self.detect=detect_fn; self.sensor=sensor_fn
        self.oled_set_mode=oled_set_mode; self.socketio=socketio
        self.active=False; self._t=None

    def start(self, duration_s=25):
        if self.active: return
        self.active=True; self.oled_set_mode("Explorateur")
        self._t=threading.Thread(target=self._run, args=(duration_s,), daemon=True); self._t.start()

    def stop(self):
        self.active=False; self.oled_set_mode("Idle"); stop()

    def _emit(self,ch,d):
        try:
            if self.socketio: self.socketio.emit(ch,d)
        except: pass

    def _run(self, duration_s):
        start=time.time(); known=set(); unknown=0; pets=set(); snaps=[]
        try:
            while self.active and time.time()-start<duration_s:
                ok,frame=self.cam.read(); 
                if not ok: time.sleep(0.02); continue
                dets=self.detect(frame); env=self.sensor() or {}
                for d in dets:
                    c=d.get("cls")
                    if c=="unknown_face": unknown+=1
                    elif c in ("Yoshi","Michka"): pets.add(c)
                    elif c and c!="person": known.add(c)
                danger=False
                if env.get("gas") and env["gas"]>=200: danger=True
                if env.get("temp") is not None and (env["temp"]<5 or env["temp"]>40): danger=True
                if env.get("humid") is not None and env["humid"]>=80: danger=True
                if danger:
                    p=os.path.join(SNAP_DIR,f"danger_{int(time.time())}.jpg")
                    cv2.imwrite(p,frame); snaps.append(p)
                forward(0.25); time.sleep(0.5); stop()
                left_turn(0.35); time.sleep(0.2); stop()
                self._emit("explorer_tick",{"known":sorted(list(known)),"unknown_count":unknown,"pets":sorted(list(pets)),"env":env})
            rep={"ts":datetime.now().isoformat(),"known":sorted(list(known)),"unknown_count":unknown,"pets":sorted(list(pets))}
            rp=os.path.join(REPORT_DIR,f"explore_{int(time.time())}.json")
            with open(rp,"w") as f: json.dump(rep,f,indent=2)
            self._emit("explorer_done",{**rep,"snapshots":snaps})
        finally:
            stop(); self.active=False; self.oled_set_mode("Idle")
