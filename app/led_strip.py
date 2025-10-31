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
