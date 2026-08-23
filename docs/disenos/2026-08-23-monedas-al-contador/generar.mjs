// Genera los tres artboards de la animación. Los tres pintan la MISMA pantalla
// (la tienda justo después de pagar el paquete Popular: 38 + 55 = 93 créditos);
// lo único que cambia es cómo vuelan las monedas.
import fs from 'node:fs';

// Punto de aterrizaje: el centro del contador del AppBar.
const META = { x: 315, y: 28 };
// De dónde sale cada moneda: las cinco de la pila de la tarjeta comprada.
const SALIDAS = [
  { x: 100, y: 268 },
  { x: 124, y: 252 },
  { x: 147, y: 268 },
  { x: 170, y: 252 },
  { x: 194, y: 268 },
];
// Hacia dónde estalla cada una en la variante C, antes de que se la traguen.
const ESTALLIDOS = [
  { x: -74, y: -46 },
  { x: -38, y: -74 },
  { x: 8, y: -86 },
  { x: 52, y: -70 },
  { x: 88, y: -34 },
];

const moneda = (attrs, extra = '') =>
  `      <div class="vuela" style="${attrs}">\n` +
  `${extra}` +
  `        <svg viewBox="0 0 28 28"><use href="#moneda" width="28" height="28"></use></svg>\n` +
  `      </div>`;

function monedasArco() {
  return SALIDAS.map((s, i) => {
    const c1 = `${s.x + 34},${s.y - 120}`;
    const c2 = `${META.x - 70},${META.y + 40}`;
    const path = `M${s.x},${s.y} C${c1} ${c2} ${META.x},${META.y}`;
    const delay = (0.35 + 0.12 * i).toFixed(2);
    return moneda(`offset-path: path('${path}'); animation-delay: ${delay}s`);
  }).join('\n');
}

function monedasCometa() {
  return SALIDAS.map((s, i) => {
    const delay = (0.35 + 0.07 * i).toFixed(2);
    const estela =
      `        <div class="estela" style="animation-delay: ${delay}s; ` +
      `transform: rotate(${(Math.atan2(META.y - s.y, META.x - s.x) * 180) / Math.PI + 180}deg)"></div>\n`;
    return moneda(
      `left: ${s.x}px; top: ${s.y}px; --dx: ${META.x - s.x}px; --dy: ${META.y - s.y}px; ` +
        `animation-delay: ${delay}s`,
      estela,
    );
  }).join('\n');
}

function monedasEnjambre() {
  return SALIDAS.map((s, i) => {
    const b = ESTALLIDOS[i];
    const delay = (0.35 + 0.04 * i).toFixed(2);
    return moneda(
      `left: ${s.x}px; top: ${s.y}px; --bx: ${b.x}px; --by: ${b.y}px; ` +
        `--dx: ${META.x - s.x}px; --dy: ${META.y - s.y}px; animation-delay: ${delay}s`,
    );
  }).join('\n');
}

// D · la mezcla que eligió el PO: estallido de C + tiro con estela de B, una
// moneda detrás de otra. Un solo elemento por moneda (la receta que se ve bien
// en B y C); el escalonado del tiro vive en los keyframes mez-c0..c4, no en un
// delay — un delay retrasaría también el estallido, que va a la vez.
function monedasMezcla() {
  return SALIDAS.map((s, i) => {
    const b = ESTALLIDOS[i];
    // El tiro sale de donde flota la moneda tras el estallido (7px de bote).
    const desde = { x: s.x + b.x, y: s.y + b.y - 7 };
    const dx = META.x - desde.x;
    const dy = META.y - desde.y;
    const angulo = (Math.atan2(dy, dx) * 180) / Math.PI + 180;
    // La hora del tiro de ESTA moneda: calma (0,35) + estallido (0,5) + su turno.
    const delayEstela = (0.85 + 0.09 * i).toFixed(2);
    return (
      `      <div class="vuela" style="left: ${s.x}px; top: ${s.y}px; ` +
      `--bx: ${b.x}px; --by: ${b.y}px; --dx: ${dx}px; --dy: ${dy}px; ` +
      `animation-name: mez-c${i}">\n` +
      `        <div class="estela" style="animation-delay: ${delayEstela}s; ` +
      `transform: rotate(${angulo.toFixed(1)}deg)"></div>\n` +
      `        <svg viewBox="0 0 28 28"><use href="#moneda" width="28" height="28"></use></svg>\n` +
      `      </div>`
    );
  }).join('\n');
}

// La tarjeta que se acaba de comprar, tal cual está hoy en la app.
const tarjeta = `
    <div style="position: absolute; left: 8px; top: 16px; width: 279px; height: 372px;
                background: radial-gradient(circle at 50% 26%, #FFF7E2 0%, #FFFFFF 60%);
                border-radius: 22px; box-shadow: 0 12px 30px rgba(30, 8, 80, .34);
                display: flex; flex-direction: column; align-items: center;
                padding: 18px 18px 18px;">
      <div style="background: #7147F2; color: #FCFCFC; font-size: 12.5px; font-weight: 700;
                  padding: 6px 14px; border-radius: 999px;">Popular</div>

      <svg width="176" height="100" viewBox="0 0 150 90" style="margin-top: 6px">
        <ellipse cx="75" cy="80" rx="44" ry="7" fill="#3E3560" opacity=".10"></ellipse>
        <use href="#moneda" x="17" y="44" width="34" height="34"></use>
        <use href="#moneda" x="55" y="44" width="34" height="34"></use>
        <use href="#moneda" x="93" y="44" width="34" height="34"></use>
        <use href="#moneda" x="36" y="18" width="34" height="34"></use>
        <use href="#moneda" x="74" y="18" width="34" height="34"></use>
      </svg>

      <div style="display: flex; align-items: flex-end; gap: 8px">
        <span style="font-size: 44px; font-weight: 800; color: #3E3560; line-height: 1">55</span>
        <span style="font-size: 16px; font-weight: 700; color: #3E3560;
                     padding-bottom: 5px">créditos</span>
      </div>
      <div style="font-size: 13px; color: #847D8F; margin-top: 8px; text-align: center">
        Hasta 55 clientes desbloqueados
      </div>

      <div style="flex-grow: 1"></div>

      <div style="font-size: 22px; font-weight: 700; color: #3E3560">US$58.83</div>
      <div style="margin-top: 14px; width: 100%; height: 48px; border-radius: 24px;
                  background: #7147F2; color: #FCFCFC; font-size: 15.5px; font-weight: 700;
                  display: flex; align-items: center; justify-content: center;
                  box-shadow: 0 6px 14px rgba(60, 21, 144, .28);">Comprar</div>

      <div style="position: absolute; right: -8px; top: 20px;
                  background: linear-gradient(180deg, #FFD75E 0%, #F2B705 100%);
                  color: #5C3A00; font-size: 13px; font-weight: 800;
                  padding: 7px 12px; border-radius: 8px 4px 4px 8px;
                  box-shadow: 0 4px 10px rgba(30, 8, 80, .30);">Ahorras 9%</div>
    </div>`;

// El aviso que la app YA pinta hoy al acreditar. Va con el número final: si
// dijera un saldo distinto al del contador, el proveedor no sabría cuál creer.
const snackbar = `
    <div style="position: absolute; left: 16px; right: 16px; bottom: 108px;
                background: #322B45; color: #F3F0F8; border-radius: 12px;
                padding: 14px 16px; font-size: 14px;
                box-shadow: 0 8px 20px rgba(30, 8, 80, .40);">
      Listo. Tienes 93 créditos.
    </div>`;

const cuerpo = (clase, monedas, extras = '') => `<div class="frame ${clase}">
__BAND__
  <div class="shop" style="background:
       radial-gradient(120% 60% at 50% 0%, rgba(255,255,255,.16) 0%, rgba(255,255,255,0) 60%),
       linear-gradient(180deg, #7A4CF5 0%, #5A2ED8 58%, #47189E 100%);">
${tarjeta}

    <div style="position: absolute; left: 303px; top: 16px; width: 279px; height: 372px;
                background: #FFFFFF; border-radius: 22px;
                box-shadow: 0 12px 30px rgba(30, 8, 80, .34);"></div>
${snackbar}
  </div>
__NAV__

  <!-- Las monedas vuelan POR ENCIMA de todo, del carrusel al contador. -->
${monedas}
</div>
${extras}`;

// El sonido que trajo el PO (ting ting ting de monedas), incrustado. Va en un
// botón FUERA del teléfono: el bucle no puede sonar solo (el navegador exige
// un toque) y un tintineo cada 4,4 s sería un castigo. El botón reinicia la
// animación y suelta los tings cuando las monedas empiezan a aterrizar.
const tingB64 = fs.readFileSync('ting.mp3').toString('base64');
const controles = `
<audio id="ting" preload="auto" src="data:audio/mpeg;base64,${tingB64}"></audio>
<div style="width: 360px; display: flex; justify-content: center; padding: 14px 0 10px">
  <div onClick="{{ reproducir }}"
       style="display: flex; align-items: center; gap: 8px; height: 44px;
              padding: 0 20px; border-radius: 22px; background: #7147F2;
              color: #FCFCFC; font-size: 13.5px; font-weight: 700;
              box-shadow: 0 6px 16px rgba(60, 21, 144, .35); cursor: pointer;
              user-select: none;">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
      <path d="M8 5v14l11-7z"></path>
    </svg>
    Ver con sonido
  </div>
</div>
`;

fs.writeFileSync('bodyMezcla.part', cuerpo('mezcla', monedasMezcla(), controles));
fs.writeFileSync('bodyArco.part', cuerpo('arco', monedasArco()));
fs.writeFileSync('bodyCometa.part', cuerpo('cometa', monedasCometa()));
fs.writeFileSync('bodyEnjambre.part', cuerpo('enjambre', monedasEnjambre()));
console.log('cuatro cuerpos escritos');
