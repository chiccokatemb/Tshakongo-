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
