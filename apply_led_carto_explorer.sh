#!/usr/bin/env bash
set -e
echo "== Tshakongo: ajout LED WS2812B + modes Cartographie & Explorateur =="

mkdir -p app/modes static/js templates docs scripts

# 1) led_strip.py
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
        self._th = None; self._stop = threading.Event()
        self.set_effect("off")

    def shutdown(self):
        if not self.enabled: return
        self.set_effect("off"); self._pixels.fill((0,0,0)); self._pixels.show()

    def _run_effect(self, target):
        if not self.enabled: return
        self._stop.set()
        if self._th and self._th.is_alive(): self._th.join(timeout=0.5)
        self._stop.clear()
        self._th = threading.Thread(target=target, daemon=True); self._th.start()

    def set_effect(self, name, color=None):
        if not self.enabled: return
        name = (name or "off").lower()
        if name == "off":          return self._run_effect(self._fx_off)
        if name == "solid":        return self._run_effect(lambda: self._fx_solid(color or COLOR_MAP["blue"]))
        if name == "white_pulse":  return self._run_effect(lambda: self._fx_pulse(COLOR_MAP["white"]))
        if name == "red_flash":    return self._run_effect(lambda: self._fx_flash(COLOR_MAP["red"],0.12))
        if name == "red_fire":     return self._run_effect(self._fx_fire)
        if name == "orange_pulse": return self._run_effect(lambda: self._fx_pulse(COLOR_MAP["orange"]))
        if name == "cyan_scan":    return self._run_effect(lambda: self._fx_scanner(COLOR_MAP["cyan"]))
        if name == "yellow_swirl": return self._run_effect(self._fx_swirl)
        if name == "rainbow":      return self._run_effect(self._fx_rainbow)
        return self._run_effect(lambda: self._fx_solid(COLOR_MAP.get(name,COLOR_MAP["blue"])))

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
    def _fx_scanner(self,c):
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

# 2) cartography.py
cat > app/modes/cartography.py <<'PY'
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
PY

# 3) explorer.py
cat > app/modes/explorer.py <<'PY'
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
PY

# 4) map_live.js
cat > static/js/map_live.js <<'JS'
export function drawMap(canvas, points) {
  const ctx = canvas.getContext('2d'), W=canvas.width, H=canvas.height;
  ctx.fillStyle='#0b0f1a'; ctx.fillRect(0,0,W,H);
  ctx.save(); ctx.translate(W/2,H/2); ctx.scale(1,-1);
  ctx.fillStyle='#66e';
  for (const p of points||[]) {
    const x=p[0]/10, y=p[1]/10;
    if (Math.abs(x)>200||Math.abs(y)>200) continue;
    ctx.fillRect(Math.floor(x),Math.floor(y),2,2);
  }
  ctx.restore(); ctx.fillStyle='#0f0'; ctx.fillRect(W/2-3,H/2-3,6,6);
}
JS

# 5) modes.html
cat > templates/modes.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Modes — Tshakongo</title>
<h2>Modes du robot</h2>
<div style="display:flex;gap:8px;flex-wrap:wrap">
  <button onclick="post('/api/mode/sentinel/start')">🛡 Sentinelle</button>
  <button onclick="post('/api/mode/sentinel/stop')">⏹ Sentinelle OFF</button>
  <button onclick="post('/api/mode/cartography/start')">🗺 Cartographie</button>
  <button onclick="post('/api/mode/cartography/stop')">💾 Sauver & OFF</button>
  <button onclick="post('/api/mode/explorer/start')">🧭 Explorateur</button>
  <button onclick="post('/api/mode/explorer/stop')">⏹ Explorateur OFF</button>
</div>
<h3>Carte (aperçu)</h3>
<canvas id="map" width="420" height="420" style="border:1px solid #333"></canvas>
<h3>Lumières</h3>
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

# 6) Notice
cat > docs/NOTICE.md <<'MD'
# Tshakongo — Notice d'utilisation (Résumé)
- Accès UI : `http://<IP>:5000/` → page **Modes**
- Boutons : Sentinelle / Cartographie / Explorateur / LED Effets
- Cartographie : démarre, le robot scanne; stop = carte sauvegardée dans `/maps/`
- Explorateur : compte personnes (connues/inconnues), capteurs (gaz/T°/H°), photos danger dans `logs/`, rapport JSON `reports/`
- LED WS2812B (GPIO18, alim 5V UBEC, GND commun, R=330Ω en série DIN, C=1000µF 5V↔GND)
- États : Normal→bleu, Enfant→arc-en-ciel, Sentinelle→blanc pulsé, Alerte inconnue→rouge flash, Danger→feu, Batterie faible→orange pulsé.
MD

# 7) requirements
grep -q 'rpi_ws281x' requirements.txt 2>/dev/null || echo 'rpi_ws281x' >> requirements.txt
grep -q 'adafruit-circuitpython-neopixel' requirements.txt 2>/dev/null || echo 'adafruit-circuitpython-neopixel' >> requirements.txt

# 8) config
cat >> app/config.yaml <<'YML'
ledstrip:
  enabled: true
  gpio: 18
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

# 9) patch server.py (ajouts non destructifs)
if ! grep -q "from app.led_strip import LedStrip" app/server.py; then
  sed -i '1i from app.led_strip import LedStrip' app/server.py
fi
if ! grep -q "from app.modes.cartography import Cartographer" app/server.py; then
  sed -i '1i from app.modes.cartography import Cartographer' app/server.py
fi
if ! grep -q "from app.modes.explorer import Explorer" app/server.py; then
  sed -i '1i from app.modes.explorer import Explorer' app/server.py
fi

# Instanciations (si absentes) — on ajoute à la fin du fichier
cat >> app/server.py <<'PY'

# ==== Tshakongo auto-append (modes & LED) ====
try:
    LED
except NameError:
    LED = LedStrip(CFG)

def _led_effect(name): 
    try: LED.set_effect(name)
    except: pass

try:
    carto
except NameError:
    carto = Cartographer(oled_set_mode=set_mode, socketio=socketio)
try:
    explorer
except NameError:
    explorer = Explorer(camera=cam, detect_fn=lambda f: detect(f),
                        sensor_fn=get_env_snapshot, oled_set_mode=set_mode, socketio=socketio)

@app.get("/modes")
def modes_page():
    return render_template("modes.html")

@app.post("/api/mode/cartography/start")
def api_carto_start():
    set_mode("Cartographie"); _led_effect("cyan_scan"); carto.start(); return jsonify(ok=True)

@app.post("/api/mode/cartography/stop")
def api_carto_stop():
    p = carto.stop(); set_mode("Idle"); _led_effect("off"); return jsonify(ok=True,map=p)

@app.post("/api/mode/explorer/start")
def api_ex_start():
    set_mode("Explorateur"); _led_effect("cyan_scan"); explorer.start(25); return jsonify(ok=True)

@app.post("/api/mode/explorer/stop")
def api_ex_stop():
    explorer.stop(); set_mode("Idle"); _led_effect("off"); return jsonify(ok=True)

@app.post("/api/led/effect/<name>")
def api_led_effect(name):
    _led_effect(name); return jsonify(ok=True, effect=name)
# ==== /auto-append ====
PY

echo "OK. Pour commit & push :"
echo "  git add . && git commit -m 'LED WS2812B + modes Cartographie/Explorateur + UI + Notice' && git push"
