# Tshakongo — Notice d'utilisation (Résumé)
- Accès UI : `http://<IP>:5000/` → page **Modes**
- Boutons : Sentinelle / Cartographie / Explorateur / LED Effets
- Cartographie : démarre, le robot scanne; stop = carte sauvegardée dans `/maps/`
- Explorateur : compte personnes (connues/inconnues), capteurs (gaz/T°/H°), photos danger dans `logs/`, rapport JSON `reports/`
- LED WS2812B (GPIO18, alim 5V UBEC, GND commun, R=330Ω en série DIN, C=1000µF 5V↔GND)
- États : Normal→bleu, Enfant→arc-en-ciel, Sentinelle→blanc pulsé, Alerte inconnue→rouge flash, Danger→feu, Batterie faible→orange pulsé.
