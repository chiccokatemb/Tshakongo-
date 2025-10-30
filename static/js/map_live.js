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
