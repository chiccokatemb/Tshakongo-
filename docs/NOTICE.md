# Tshakongo — Notice rapide
- UI : `http://<IP>:5000/`
- Modes : Sentinelle / Cartographie / Explorateur
- Cartographie : démarre → scan → Stop & Sauver → fichier dans `/maps/`
- Explorateur : compte connus/inconnus (stub), vérifie capteurs (stub), enregistre alertes `logs/`, rapport JSON `reports/`
- LED : bande WS2812B sur DIN=GPIO18 (R=330Ω en série), alim 5V UBEC, GND commun, C=1000µF entre 5V et GND
