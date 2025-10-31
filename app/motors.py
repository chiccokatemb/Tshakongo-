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
