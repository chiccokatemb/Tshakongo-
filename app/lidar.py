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
