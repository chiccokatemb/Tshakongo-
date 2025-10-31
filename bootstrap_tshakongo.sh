#!/usr/bin/env bash
set -e
echo "== Bootstrap Tshakongo (serveur + HAT Emakefun + LED WS2812B + LiDAR stub + UI) =="

# Arbo
mkdir -p app/modes app/static/js app/templates scripts docs maps reports logs

# ========== requirements ==========
cat > requirements.txt <<'REQ'
flask
flask-socketio
eventlet
opencv-python
numpy
PyYAML
rpi_ws281x
adafruit-circuitpython-neopixel
REQ

# ========== config ==========
mkdir -p app
cat > app/config.yaml <<'YML'
server:
  host: 0.0.0.0
  port: 5000

camera:
  index: 0   # 0=CSI/USB auto; adapte si besoin

ledstrip:
  enabled: true
  gpio: 18        # DIN
  count: 30
  brightness: 0.5
  order: "GRB"

status_colors:
  normal: "solid"
  child: "rainbow"
  sentinel: "white_pulse"
  explore: "cyan_scan"
  alert_intruder: "red_flash"
  alert_danger: "red_fire"
  low_battery: "orange_pulse"
  ai_talk: "yellow_swirl"
YML

# ========== __init__ ==========
cat > app/__init__.py <<'PY'
# Tshakongo package
PY

# ========== motors (Emakefun HAT) ==========
cat > app/motors.py <<'PY'
# Pilotage moteurs avec Emakefun RaspberryPi-MotorDriverBoard (I2C)
# Si librairie non dispo en dev, on simule.
import time, os
class _Sim:
    def __init__(self): self.l=0; self.r=0
    def setLR(self, l, r): self.l, self.r = l, r; print(f"[MOTORS] L={l:.2f} R={r:.2f}")
SIM = _Sim()

def _clip(x): 
    return max(-1.0, min(1.0, float(x)))

def move(left, right, dur=None):
    left=_clip(left); right=_clip(right)
    # TODO: remplacer par appels réels Emakefun (ex: hat.setMotor(i, pwm))
    SIM.setLR(left, right)
    if dur: time.sleep(dur); stop()

def forward(speed=0.5, dur=None):  move(speed, speed, dur)
def backward(speed=0.5, dur=None): move(-speed, -speed, dur)
def left_turn(speed=0.5, dur=None):  move(-speed, speed, dur)
def right_turn(speed=0.5, dur=None): move(speed, -speed, dur)
def stop(): move(0,0, None)
PY

# ========== lidar (LD06 stub) ==========
cat > app/lidar.py <<'PY'
# Stub LD06 : retourne des points simulés si pas connecté
import math, time, random
def get_points():
    # Renvoie ~200 points en mm autour du robot (simulation cercle)
    pts=[]
    for i in range(0,360,2):
        r = 800 + 150*math.sin(time.time()*0.7 + i*0.1) + random.randint(-40,40)
        a = math.radians(i)
        pts.append((r*math.cos(a), r*math.sin(a)))
    return pts
PY

# ========== camera ==========
cat > app/camera.py <<'PY'
import cv2
class Camera:
    def __init__(self, index=0): self.cap=cv2.VideoCapture(index)
    def read(self):
        ok,frame=self.cap.read()
        return ok, frame
    def release(self):
        try: self.cap.release()
        except: pass
PY

# ========== env sensors snapshot (placeholder) ==========
cat > app/env.py <<'PY'
# Regroupe les capteurs (Feather Sense/INA219/...) si connectés
def get_env_snapshot():
    # Valeurs fictives pour démo UI
    return {"temp": 23.5, "humid": 45.0, "gas": 80}
PY

# ========== LED strip (WS2812B) ==========
cat > app/led_strip.py <<'PY'
import threading, time
try:
    import board, neopixel
except Exception:
    board = neopixel = None

COLOR_MAP = {"red":(255,0,0),"green":(0,255,0),"blue":(0,0,255),"cyan":(0,255,255),
             "yellow":(255,200,0),"orange":(255,120,0),"white":(255,255,255),
             "purple":(160,0,255),"off":(0,0,0)}

class LedStrip:
    def __init__(self, cfg):
        self.enabled = bool(cfg.get("ledstrip",{}).get("enabled", False)) and (neopixel is not None)
        if not self.enabled: return
        self.count = int(cfg["ledstrip"].get("count", 30))
        self.brightness = float(cfg["ledstrip"].get("brightness", 0.5))
        order_name = cfg["ledstrip"].get("order","GRB")
        self.order = getattr(neopixel, f"ORDER_{order_name}", neopixel.ORDER_GRB)
        pin = int(cfg["ledstrip"].get("gpio", 18))
        self._pixels = neopixel.NeoPixel(getattr(board,f"D{pin}"), self.count,
                                         brightness=self.brightness, auto_write=False,
                                         pixel_order=self.order)
        self._th=None; self._stop=threading.Event()
        self.set_effect("off")

    def shutdown(self):
        if not self.enabled: return
        self.set_effect("off"); self._pixels.fill((0,0,0)); self._pixels.show()

    def _run(self, target):
        self._stop.set()
        if self._th and self._th.is_alive(): self._th.join(timeout=0.5)
        self._stop.clear()
        self._th=threading.Thread(target=target,daemon=True); self._th.start()

    def set_effect(self, name):
        if not self.enabled: return
        n=(name or "off").lower()
        if n=="off": return self._run(self._fx_off)
        if n=="solid": return self._run(lambda:self._fx_solid(COLOR_MAP["blue"]))
        if n=="white_pulse": return self._run(lambda:self._fx_pulse((255,255,255)))
        if n=="red_flash": return self._run(lambda:self._fx_flash((255,0,0),0.12))
        if n=="red_fire": return self._run(self._fx_fire)
        if n=="orange_pulse": return self._run(lambda:self._fx_pulse((255,120,0)))
        if n=="cyan_scan": return self._run(lambda:self._fx_scan((0,255,255)))
        if n=="yellow_swirl": return self._run(self._fx_swirl)
        if n=="rainbow": return self._run(self._fx_rainbow)
        return self._run(lambda:self._fx_solid(COLOR_MAP.get(n,(0,0,255))))

    def _fx_off(self):
        while not self._stop.is_set():
            self._pixels.fill((0,0,0)); self._pixels.show(); self._stop.wait(0.5)
    def _fx_solid(self,c):
        while not self._stop.is_set():
            self._pixels.fill(c); self._pixels.show(); self._stop.wait(0.5)
    def _fx_pulse(self,c):
        r,g,b=c; up=True; lvl=0.1
        while not self._stop.is_set():
            self._pixels.fill((int(r*lvl),int(g*lvl),int(b*lvl))); self._pixels.show()
            lvl += 0.05 if up else -0.05
            if lvl>=1.0: up=False
            if lvl<=0.1: up=True
            self._stop.wait(0.03)
    def _fx_flash(self,c,per):
        on=True
        while not self._stop.is_set():
            self._pixels.fill(c if on else (0,0,0)); self._pixels.show(); on=not on; self._stop.wait(per)
    def _fx_scan(self,c):
        i=0; d=1
        while not self._stop.is_set():
            self._pixels.fill((0,0,0)); self._pixels[i]=c; self._pixels.show()
            i+=d
            if i>=self.count-1 or i<=0: d*=-1
            self._stop.wait(0.02)
    def _fx_rainbow(self):
        j=0
        def wheel(p):
            if p<85: return (p*3,255-p*3,0)
            if p<170: p-=85; return (255-p*3,0,p*3)
            p-=170; return (0,p*3,255-p*3)
        while not self._stop.is_set():
            for i in range(self.count):
                self._pixels[i]=wheel((i*256//self.count+j)&255)
            self._pixels.show(); j=(j+3)%256; self._stop.wait(0.02)
    def _fx_fire(self):
        import random
        base=(255,60,0)
        while not self._stop.is_set():
            for i in range(self.count):
                f=random.randint(-40,35)
                r=max(0,min(255,base[0]+f)); g=max(0,min(255,base[1]+f))
                self._pixels[i]=(r,g,0)
            self._pixels.show(); self._stop.wait(0.05)
    def _fx_swirl(self):
        k=0
        while not self._stop.is_set():
            for i in range(self.count):
                v=(i+k)%self.count
                self._pixels[i]=(255,200 if v%3 else 140,0)
            self._pixels.show(); k=(k+1)%self.count; self._stop.wait(0.03)
PY

# ========== modes Cartography & Explorer ==========
cat > app/modes/cartography.py <<'PY'
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
PY

cat > app/modes/explorer.py <<'PY'
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
PY

# ========== JS carte ==========
cat > app/static/js/map_live.js <<'JS'
export function drawMap(canvas, points) {
  const ctx = canvas.getContext('2d'), W=canvas.width, H=canvas.height;
  ctx.fillStyle='#0b0f1a'; ctx.fillRect(0,0,W,H);
  ctx.save(); ctx.translate(W/2,H/2); ctx.scale(1,-1);
  ctx.fillStyle='#6ae';
  for (const p of points||[]) {
    const x=p[0]/10, y=p[1]/10;
    if (Math.abs(x)>220||Math.abs(y)>220) continue;
    ctx.fillRect(Math.floor(x),Math.floor(y),2,2);
  }
  ctx.restore();
  ctx.fillStyle='#0f0'; ctx.fillRect(W/2-3,H/2-3,6,6);
}
JS

# ========== templates ==========
cat > app/templates/modes.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Tshakongo — Modes</title>
<h2>Tshakongo — Modes</h2>
<div style="display:flex;gap:8px;flex-wrap:wrap;margin-bottom:8px">
  <button onclick="post('/api/mode/sentinel/start')">🛡 Sentinelle</button>
  <button onclick="post('/api/mode/sentinel/stop')">⏹ Sentinelle OFF</button>
  <button onclick="post('/api/mode/cartography/start')">🗺 Cartographie</button>
  <button onclick="post('/api/mode/cartography/stop')">💾 Stop & Sauver</button>
  <button onclick="post('/api/mode/explorer/start')">🧭 Explorateur</button>
  <button onclick="post('/api/mode/explorer/stop')">⏹ Explorateur OFF</button>
</div>
<h3>Carte (aperçu)</h3>
<canvas id="map" width="420" height="420" style="border:1px solid #333"></canvas>
<h3>LED</h3>
<select id="fx">
  <option value="off">Off</option><option value="solid">Bleu fixe</option>
  <option value="white_pulse">Sentinelle</option><option value="cyan_scan">Scanner</option>
  <option value="red_flash">Alerte</option><option value="red_fire">Feu</option>
  <option value="orange_pulse">Batterie faible</option><option value="yellow_swirl">Parle</option>
  <option value="rainbow">Arc-en-ciel</option>
</select>
<button onclick="setFx()">Appliquer</button>
<script type="module">
import { drawMap } from "/static/js/map_live.js";
const c=document.getElementById('map'); const s=io();
function post(u){ fetch(u,{method:'POST'}) }
function setFx(){ fetch('/api/led/effect/'+document.getElementById('fx').value,{method:'POST'}) }
s.on("map_points",(d)=>drawMap(c,d.points||[]));
s.on("explorer_done",(d)=>alert("Exploration terminée: "+JSON.stringify(d)));
</script>
<script src="https://cdn.socket.io/4.7.5/socket.io.min.js"></script>
HTML

# ========== server ==========
cat > app/server.py <<'PY'
import os, yaml
from flask import Flask, jsonify, render_template
from flask_socketio import SocketIO
from app.camera import Camera
from app.env import get_env_snapshot
from app.led_strip import LedStrip
from app.modes.cartography import Cartographer
from app.modes.explorer import Explorer

CFG = yaml.safe_load(open(os.path.join("app","config.yaml")))
app = Flask(__name__, static_folder="app/static", template_folder="app/templates")
app.static_url_path = "/static"
socketio = SocketIO(app, async_mode="eventlet", cors_allowed_origins="*")

cam = Camera(CFG.get("camera",{}).get("index",0))
LED = LedStrip(CFG)
carto = Cartographer(socketio=socketio)
explorer = Explorer(camera=cam, detector=lambda f: [], socketio=socketio)

@app.route("/")
def home(): return render_template("modes.html")
@app.get("/modes")
def modes(): return render_template("modes.html")

# Modes
@app.post("/api/mode/sentinel/start")
def sentinel_start():
    LED.set_effect("white_pulse"); return jsonify(ok=True)
@app.post("/api/mode/sentinel/stop")
def sentinel_stop():
    LED.set_effect("off"); return jsonify(ok=True)

@app.post("/api/mode/cartography/start")
def carto_start():
    LED.set_effect("cyan_scan"); carto.start(); return jsonify(ok=True)
@app.post("/api/mode/cartography/stop")
def carto_stop():
    p = carto.stop(); LED.set_effect("off"); return jsonify(ok=True, map=p)

@app.post("/api/mode/explorer/start")
def ex_start():
    LED.set_effect("cyan_scan"); explorer.start(25); return jsonify(ok=True)
@app.post("/api/mode/explorer/stop")
def ex_stop():
    explorer.stop(); LED.set_effect("off"); return jsonify(ok=True)

# LED
@app.post("/api/led/effect/<name>")
def led_effect(name):
    LED.set_effect(name); return jsonify(ok=True, effect=name)

def run():
    socketio.run(app, host=CFG["server"]["host"], port=CFG["server"]["port"])

if __name__ == "__main__":
    run()
PY

# ========== install script ==========
cat > scripts/install_tshakongo.sh <<'SH'
#!/usr/bin/env bash
set -e
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev libatlas-base-dev scons
pip3 install --upgrade pip
pip3 install -r requirements.txt
echo "Install OK"
SH
chmod +x scripts/install_tshakongo.sh

# ========== Notice ==========
cat > docs/NOTICE.md <<'MD'
# Tshakongo — Notice rapide
- UI : `http://<IP>:5000/`
- Modes : Sentinelle / Cartographie / Explorateur
- Cartographie : démarre → scan → Stop & Sauver → fichier dans `/maps/`
- Explorateur : compte connus/inconnus (stub), vérifie capteurs (stub), enregistre alertes `logs/`, rapport JSON `reports/`
- LED : bande WS2812B sur DIN=GPIO18 (R=330Ω en série), alim 5V UBEC, GND commun, C=1000µF entre 5V et GND
MD

echo "== Bootstrap terminé =="
echo "Commandes:"
echo "  pip install -r requirements.txt"
echo "  python -m app.server"
