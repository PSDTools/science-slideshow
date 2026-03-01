<script module lang="ts">
	export interface WeatherData {
		imperial?: {
			temp?: number;
			windSpeed?: number;
			windGust?: number;
			windChill?: number;
			heatIndex?: number;
			precipRate?: number;
			pressure?: number;
			dewpt?: number;
			elev?: number;
		};
		humidity?: number;
		uv?: number;
		winddir?: number;
		stationID?: string;
		neighborhood?: string;
		country?: string;
		obsTimeLocal?: string;
		lat?: number;
		lon?: number;
	}

	export interface ArcConfig {
		xRight: number; // x% where body rises (right side = east)
		xLeft: number; // x% where body sets  (left side = west)
		yHorizon: number; // vh at horizon — use >100 to start/end off-screen
		yPeak: number; // vh at the top of the arc (noon / midnight)
		arcExp: number; // exponent shaping the arc (0.3 = flat, 1.5 = pointy)
	}

	export const ARC_DEFAULTS: ArcConfig = {
		xRight: 92,
		xLeft: 8,
		yHorizon: 115,
		yPeak: 32,
		arcExp: 0.65
	};
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import { getSunTimes } from '$lib/sunTimes';

	let {
		data = null,
		entering = false,
		timeOverride = null,
		arcConfig = ARC_DEFAULTS
	}: {
		data: WeatherData | null;
		entering?: boolean;
		timeOverride?: number | null;
		arcConfig?: ArcConfig;
	} = $props();

	// DOM refs
	let container: HTMLDivElement;
	let wxCanvas: HTMLCanvasElement;
	let treeCanvas: HTMLCanvasElement;

	// Canvas state
	let drops: { x: number; y: number; len: number; spd: number; op: number; ang: number }[] = [];
	let flakes: {
		x: number;
		y: number;
		r: number;
		spd: number;
		drift: number;
		op: number;
		off: number;
	}[] = [];
	let animId = 0;
	let snowT = 0;
	let lightningTimeout = 0;
	let shootTimeout = 0;
	let mounted = false;

	// helper: query within our container
	function el<T extends Element>(id: string): T | null {
		return container?.querySelector<T>(`#${id}`) ?? null;
	}

	function pad(n: number) {
		return String(n).padStart(2, '0');
	}

	function tickClock() {
		const d = new Date();
		let h = d.getHours();
		const ap = h >= 12 ? 'pm' : 'am';
		h = h % 12 || 12;
		const c = el('wx-clock');
		const dt = el('wx-date');
		if (c) c.textContent = `${h}:${pad(d.getMinutes())}:${pad(d.getSeconds())}\u202f${ap}`;
		const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
		const months = [
			'January',
			'February',
			'March',
			'April',
			'May',
			'June',
			'July',
			'August',
			'September',
			'October',
			'November',
			'December'
		];
		if (dt) dt.textContent = `${days[d.getDay()]}  ·  ${months[d.getMonth()]} ${d.getDate()}`; // Reposition sun and moon every tick so playback and real drift stay smooth
		positionCelestialBodies(_celestialData);
	}

	function windDir(deg: number) {
		return [
			'N',
			'NNE',
			'NE',
			'ENE',
			'E',
			'ESE',
			'SE',
			'SSE',
			'S',
			'SSW',
			'SW',
			'WSW',
			'W',
			'WNW',
			'NW',
			'NNW'
		][Math.round(deg / 22.5) % 16];
	}

	/* ── CELESTIAL BODY POSITIONING ── */

	// Latest weather data reference — kept updated so tickClock can reposition bodies
	let _celestialData: WeatherData | null = null;

	// Sky cross-fade: gradients that match each theme's --bg0/--bg1
	const BG_GRADIENTS: Record<string, string> = {
		night: 'linear-gradient(165deg,#111827 0%,#1a2540 100%)',
		day: 'linear-gradient(165deg,#1c4a7a 0%,#2a6aaa 100%)',
		rise: 'linear-gradient(165deg,#2a1008 0%,#6a2808 100%)',
		golden: 'linear-gradient(165deg,#251408 0%,#5a3010 100%)',
		sunset: 'linear-gradient(165deg,#1a0820 0%,#4a1230 100%)',
		rain: 'linear-gradient(165deg,#101820 0%,#182838 100%)',
		storm: 'linear-gradient(165deg,#0e0c1e 0%,#181430 100%)',
		snow: 'linear-gradient(165deg,#141c2c 0%,#1e2c44 100%)'
	};
	let _currentTheme = '';
	let _isPrecip = false;

	/**
	 * Lunar phase via Julian Day Number.
	 * Returns 0 = new moon, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
	 */
	function getMoonPhase(): number {
		const d = new Date();
		const a = Math.floor((14 - (d.getMonth() + 1)) / 12);
		const y = d.getFullYear() + 4800 - a;
		const m = d.getMonth() + 1 + 12 * a - 3;
		const jd =
			d.getDate() +
			Math.floor((153 * m + 2) / 5) +
			365 * y +
			Math.floor(y / 4) -
			Math.floor(y / 100) +
			Math.floor(y / 400) -
			32045 +
			(d.getHours() - 12) / 24 +
			d.getMinutes() / 1440;
		// Reference new moon: Jan 6, 2000 18:14 UTC → JD 2451550.1
		const age = (((jd - 2451550.1) % 29.53058867) + 29.53058867) % 29.53058867;
		return age / 29.53058867;
	}

	/**
	 * Map a 0–1 arc progress to screen position.
	 * Screen faces NORTH: east = right, west = left, south = low-center.
	 * The sun/moon arc is therefore a LOW arc: rises right, peaks center-low, sets left.
	 */
	function celestialScreenPos(t: number): { x: number; y: number } {
		const { xRight, xLeft, yHorizon, yPeak, arcExp } = arcConfig;
		const x = xRight - (xRight - xLeft) * t;
		const y = yHorizon - (yHorizon - yPeak) * Math.pow(Math.sin(Math.PI * t), arcExp);
		return { x, y };
	}

	/**
	 * Draw the moon's phase on a canvas inside moonEl.
	 * phase: 0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter
	 */
	function renderMoonPhase(moonEl: HTMLElement, phase: number) {
		// Canvas is larger than the visible disc so the glow can bleed out naturally
		const size = 180;
		const discR = 34; // moon disc radius in canvas px
		const cx = size / 2,
			cy = size / 2;

		let cv = moonEl.querySelector('canvas') as HTMLCanvasElement | null;
		if (!cv) {
			cv = document.createElement('canvas');
			cv.style.cssText = 'display:block;background:transparent;';
			moonEl.innerHTML = '';
			moonEl.appendChild(cv);
		}
		if (cv.width !== size) {
			cv.width = cv.height = size;
		}
		const ctx = cv.getContext('2d')!;
		ctx.clearRect(0, 0, size, size);

		if (phase <= 0.025 || phase >= 0.975) {
			// New moon — barely visible ring
			ctx.beginPath();
			ctx.arc(cx, cy, discR, 0, Math.PI * 2);
			ctx.strokeStyle = 'rgba(150,170,200,0.12)';
			ctx.lineWidth = 1.5;
			ctx.stroke();
			return;
		}

		// ── Lit face ──
		ctx.save();
		ctx.beginPath();
		ctx.arc(cx, cy, discR, 0, Math.PI * 2);
		ctx.clip();
		const waxing = phase < 0.5;
		const tx = Math.cos(phase * Math.PI * 2) * discR;
		// Slightly warm white for the lit surface
		ctx.fillStyle = 'rgba(232,240,255,0.96)';
		ctx.beginPath();
		if (waxing) {
			ctx.arc(cx, cy, discR, -Math.PI / 2, Math.PI / 2);
			ctx.ellipse(cx, cy, Math.abs(tx), discR, 0, Math.PI / 2, -Math.PI / 2, tx > 0);
		} else {
			ctx.arc(cx, cy, discR, -Math.PI / 2, Math.PI / 2, true);
			ctx.ellipse(cx, cy, Math.abs(tx), discR, 0, Math.PI / 2, -Math.PI / 2, tx < 0);
		}
		ctx.fill();
		ctx.restore();

		// ── Atmospheric limb softening (feathered edge on the lit disc) ──
		const limb = ctx.createRadialGradient(cx, cy, discR * 0.72, cx, cy, discR);
		limb.addColorStop(0, 'rgba(0,0,0,0)');
		limb.addColorStop(1, 'rgba(0,0,20,0.28)');
		ctx.save();
		ctx.beginPath();
		ctx.arc(cx, cy, discR, 0, Math.PI * 2);
		ctx.clip();
		ctx.fillStyle = limb;
		ctx.fillRect(0, 0, size, size);
		ctx.restore();

		// ── Glow layers ── drawn outside the clip so they bleed past the disc edge
		// Inner halo
		const g1 = ctx.createRadialGradient(cx, cy, discR * 0.8, cx, cy, discR * 1.7);
		g1.addColorStop(0, 'rgba(180,210,255,0.28)');
		g1.addColorStop(1, 'rgba(180,210,255,0)');
		ctx.fillStyle = g1;
		ctx.beginPath();
		ctx.arc(cx, cy, discR * 1.7, 0, Math.PI * 2);
		ctx.fill();

		// Outer diffuse glow
		const g2 = ctx.createRadialGradient(cx, cy, discR * 0.5, cx, cy, size * 0.48);
		g2.addColorStop(0, 'rgba(160,195,255,0.14)');
		g2.addColorStop(0.5, 'rgba(140,180,255,0.06)');
		g2.addColorStop(1, 'rgba(140,180,255,0)');
		ctx.fillStyle = g2;
		ctx.beginPath();
		ctx.arc(cx, cy, size * 0.48, 0, Math.PI * 2);
		ctx.fill();
	}

	/**
	 * Compute and apply screen positions for sun and moon based on real time.
	 * Sun: rises right (east), sets left (west), arcs low (north-facing screen).
	 * Moon: same arc geometry, timed by lunar phase offset from sunrise.
	 */
	function positionCelestialBodies(w: WeatherData | null) {
		const lat = w?.lat,
			lon = w?.lon;
		if (lat == null || lon == null) return;

		const now = new Date();
		const h = timeOverride ?? now.getHours() + now.getMinutes() / 60;
		const { sunrise, sunset } = getSunTimes(lat, lon);
		if (sunrise == null || sunset == null) return;

		const sunWrap = el<HTMLElement>('wx-sun-wrap');
		const moonEl = el<HTMLElement>('wx-moon');
		if (!sunWrap || !moonEl) return;

		const isPrecip = _isPrecip;

		// ── SUN ──
		const sunT = (h - sunrise) / (sunset - sunrise); // 0 at sunrise, 1 at sunset
		// Fade in/out over 4% of the day (~35 min) near each horizon
		const FADE = 0.04;
		const sunAlpha = isPrecip
			? 0
			: Math.max(0, Math.min(1, Math.min(sunT / FADE, (1 - sunT) / FADE)));

		if (sunAlpha > 0) {
			const pos = celestialScreenPos(Math.max(0, Math.min(1, sunT)));
			sunWrap.style.display = 'block';
			sunWrap.style.position = 'fixed';
			sunWrap.style.top = `${pos.y}vh`;
			sunWrap.style.left = `${pos.x}vw`;
			sunWrap.style.transform = 'translate(-50%,-50%)';
			sunWrap.style.opacity = String(sunAlpha);
		} else {
			sunWrap.style.opacity = '0';
			// Only hide from layout once fully faded (avoids pop)
			if (sunT < -FADE * 2 || sunT > 1 + FADE * 2) sunWrap.style.display = 'none';
		}

		// ── MOON ──
		// Moon spans the deep night — it must be gone before the sun's glow appears
		// at either end of the day.  We use the same margins as inferTheme():
		//   moonrise = sunset + 0.5h  (after the sunset theme clears — full dark)
		//   moonset  = sunrise - 0.33h (before the rise glow begins)
		// This guarantees the sun and moon never share the sky visually.
		if (isPrecip) {
			moonEl.style.display = 'none';
			return;
		}

		const phase = getMoonPhase();
		const moonrise = sunset + 0.5; // rises once night is fully dark
		const moonset = sunrise - 0.33; // sets before pre-dawn glow
		// Night duration between those two anchors (handles midnight wraparound)
		const moonDurHrs = (moonset - moonrise + 24) % 24;

		// Fractional arc position (handles midnight wraparound)
		let moonT: number | null = null;
		if (moonrise < moonset) {
			if (h >= moonrise && h < moonset) moonT = (h - moonrise) / moonDurHrs;
		} else {
			if (h >= moonrise) moonT = (h - moonrise) / moonDurHrs;
			else if (h < moonset) moonT = (h + 24 - moonrise) / moonDurHrs;
		}

		const moonAlpha =
			moonT != null ? Math.max(0, Math.min(1, Math.min(moonT / FADE, (1 - moonT) / FADE))) : 0;

		if (moonAlpha > 0 && moonT != null) {
			const pos = celestialScreenPos(Math.max(0, Math.min(1, moonT)));
			const base =
				`display:block;position:fixed;top:${pos.y}vh;left:${pos.x}vw;` +
				`transform:translate(-50%,-50%);width:180px;height:180px;` +
				`border-radius:0;background:none;box-shadow:none;`;
			// Only update cssText (and re-render phase) if display/position changed
			if (moonEl.style.display !== 'block') moonEl.style.cssText = base;
			else {
				moonEl.style.top = `${pos.y}vh`;
				moonEl.style.left = `${pos.x}vw`;
			}
			moonEl.style.opacity = String(moonAlpha);
			renderMoonPhase(moonEl, phase);
		} else {
			moonEl.style.opacity = '0';
			if (moonT == null || moonT < -FADE * 2 || moonT > 1 + FADE * 2) moonEl.style.display = 'none';
		}
	}

	function inferTheme(w: WeatherData | null) {
		const imp = (w && w.imperial) || {};
		const rate = imp.precipRate,
			temp = imp.temp,
			gust = imp.windGust;

		// Precipitation overrides everything
		if (rate != null && rate > 0) {
			if (temp != null && temp <= 33) return 'snow';
			if ((gust != null && gust > 20) || rate > 0.08) return 'storm';
			return 'rain';
		}

		// Fractional local hour (e.g. 14.5 = 2:30 PM)
		const now = new Date();
		const h = timeOverride ?? now.getHours() + now.getMinutes() / 60;

		// Use station coordinates if available, otherwise fall back to hardcoded thresholds
		const lat = w?.lat,
			lon = w?.lon;
		if (lat != null && lon != null) {
			const { sunrise, sunset } = getSunTimes(lat, lon);
			if (sunrise != null && sunset != null) {
				if (h >= sunrise - 0.33 && h < sunrise + 0.83) return 'rise'; // ~20 min before → 50 min after
				if (h >= sunrise + 0.83 && h < sunset - 1.5) return 'day';
				if (h >= sunset - 1.5 && h < sunset - 0.5) return 'golden'; // 90 min → 30 min before sunset
				if (h >= sunset - 0.5 && h < sunset + 0.5) return 'sunset'; // 30 min either side of sunset
				return 'night';
			}
		}

		// Fallback: fixed thresholds (no coordinates available)
		if (h >= 5 && h < 7) return 'rise';
		if (h >= 7 && h < 17) return 'day';
		if (h >= 17 && h < 19) return 'golden';
		if (h >= 19 && h < 21) return 'sunset';
		return 'night';
	}

	const LABELS: Record<string, string> = {
		rise: 'sunrise',
		day: 'clear',
		golden: 'golden hour',
		sunset: 'dusk',
		night: 'clear night',
		rain: 'rain',
		storm: 'thunderstorm',
		snow: 'snow'
	};

	/**
	 * Returns the time-of-day theme, always ignoring precipitation.
	 * Used as the sky/background theme so the day/night cycle runs during weather.
	 */
	function inferSkyTheme(w: WeatherData | null): string {
		const now = new Date();
		const h = timeOverride ?? now.getHours() + now.getMinutes() / 60;
		const lat = w?.lat,
			lon = w?.lon;
		if (lat != null && lon != null) {
			const { sunrise, sunset } = getSunTimes(lat, lon);
			if (sunrise != null && sunset != null) {
				if (h >= sunrise - 0.33 && h < sunrise + 0.83) return 'rise';
				if (h >= sunrise + 0.83 && h < sunset - 1.5) return 'day';
				if (h >= sunset - 1.5 && h < sunset - 0.5) return 'golden';
				if (h >= sunset - 0.5 && h < sunset + 0.5) return 'sunset';
				return 'night';
			}
		}
		if (h >= 5 && h < 7) return 'rise';
		if (h >= 7 && h < 17) return 'day';
		if (h >= 17 && h < 19) return 'golden';
		if (h >= 19 && h < 21) return 'sunset';
		return 'night';
	}

	/* ── TREELINE ── */
	function mulberry32(a: number) {
		return function () {
			a |= 0;
			a = (a + 0x6d2b79f5) | 0;
			let t = Math.imul(a ^ (a >>> 15), 1 | a);
			t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
			return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
		};
	}

	function buildTreeline(theme: string) {
		const tc = treeCanvas;
		if (!tc) return;
		const c = tc.getContext('2d')!;
		const W = (tc.width = window.innerWidth + 40);
		const H = (tc.height = Math.round(window.innerHeight * 0.44));
		const fills: Record<string, string> = {
			day: '#142a48',
			rise: '#1a0908',
			golden: '#180e06',
			sunset: '#120618',
			night: '#0e1322',
			rain: '#0e1520',
			storm: '#0a0918',
			snow: '#101828'
		};
		const hex = fills[theme] || '#0e1520';
		const r = parseInt(hex.slice(1, 3), 16),
			g = parseInt(hex.slice(3, 5), 16),
			b = parseInt(hex.slice(5, 7), 16);
		c.clearRect(0, 0, W, H);
		const gndY = H * 0.62;

		c.fillStyle = `rgb(${r},${g},${b})`;
		c.fillRect(0, gndY, W, H - gndY + 4);

		function drawTree(x: number, baseY: number, treeH: number, alpha: number) {
			const N = Math.round(6 + treeH / 20);
			const maxHW = treeH * 0.12;
			const tierH = treeH * 0.28;
			c.fillStyle = `rgba(${r},${g},${b},${alpha})`;
			for (let i = 0; i < N; i++) {
				const t = i / (N - 1);
				const apexY = baseY - treeH * (1 - t * 0.82);
				const tw = maxHW * Math.pow(t + 0.05, 0.52);
				c.beginPath();
				c.moveTo(x, apexY);
				c.lineTo(x - tw, apexY + tierH);
				c.lineTo(x + tw, apexY + tierH);
				c.closePath();
				c.fill();
			}
			const trW = Math.max(1.5, treeH * 0.016);
			c.fillStyle = `rgba(${r},${g},${b},${alpha})`;
			c.fillRect(x - trW / 2, baseY - treeH * 0.09, trW, treeH * 0.09 + 3);
		}

		let rng = mulberry32(42);
		let px = -30;
		while (px < W + 40) {
			const th = 50 + rng() * 60;
			drawTree(px, gndY, th, 0.6);
			px += th * 0.19 + rng() * 26 + 5;
		}
		rng = mulberry32(77);
		px = -20;
		while (px < W + 30) {
			const th = 88 + rng() * 120;
			drawTree(px, gndY, th, 1.0);
			px += th * 0.16 + rng() * 22 + 4;
		}

		const grad = c.createLinearGradient(0, gndY * 0.38, 0, gndY);
		grad.addColorStop(0, `rgba(${r},${g},${b},0)`);
		grad.addColorStop(1, `rgba(${r},${g},${b},0.28)`);
		c.fillStyle = grad;
		c.fillRect(0, gndY * 0.38, W, gndY * 0.62);
	}

	/* ── CANVAS: RAIN / SNOW ── */
	function resizeCanvas() {
		if (!wxCanvas) return;
		wxCanvas.width = window.innerWidth;
		wxCanvas.height = window.innerHeight;
	}

	function initRain(heavy: boolean) {
		const count = heavy ? 320 : 150,
			angle = heavy ? 18 : 7;
		drops = [];
		for (let i = 0; i < count; i++)
			drops.push({
				x: Math.random() * (wxCanvas.width + 200) - 100,
				y: Math.random() * wxCanvas.height,
				len: heavy ? 22 + Math.random() * 20 : 14 + Math.random() * 12,
				spd: heavy ? 18 + Math.random() * 14 : 11 + Math.random() * 8,
				op: 0.18 + Math.random() * 0.48,
				ang: ((angle + (Math.random() - 0.5) * 6) * Math.PI) / 180
			});
	}

	function drawRain(heavy: boolean) {
		const c = wxCanvas.getContext('2d')!;
		c.clearRect(0, 0, wxCanvas.width, wxCanvas.height);
		c.save();
		for (const d of drops) {
			c.beginPath();
			c.strokeStyle = heavy ? `rgba(160,200,245,${d.op})` : `rgba(120,175,225,${d.op})`;
			c.lineWidth = heavy ? 1.4 : 0.9;
			c.moveTo(d.x, d.y);
			c.lineTo(d.x + Math.sin(d.ang) * d.len, d.y + Math.cos(d.ang) * d.len);
			c.stroke();
			d.y += d.spd;
			d.x += Math.sin(d.ang) * d.spd;
			if (d.y > wxCanvas.height) {
				d.y = -d.len;
				d.x = Math.random() * (wxCanvas.width + 200) - 100;
			}
		}
		c.restore();
	}

	function initSnow() {
		flakes = [];
		for (let i = 0; i < 200; i++)
			flakes.push({
				x: Math.random() * wxCanvas.width,
				y: Math.random() * wxCanvas.height,
				r: 1.2 + Math.random() * 4.5,
				spd: 0.4 + Math.random() * 1.1,
				drift: (Math.random() - 0.5) * 0.5,
				op: 0.35 + Math.random() * 0.55,
				off: Math.random() * Math.PI * 2
			});
	}

	function drawSnow() {
		const c = wxCanvas.getContext('2d')!;
		c.clearRect(0, 0, wxCanvas.width, wxCanvas.height);
		snowT += 0.008;
		c.save();
		for (const f of flakes) {
			c.beginPath();
			c.arc(f.x, f.y, f.r, 0, Math.PI * 2);
			c.fillStyle = `rgba(215,235,252,${f.op})`;
			c.fill();
			f.y += f.spd;
			f.x += f.drift + Math.sin(snowT + f.off) * 0.5;
			if (f.y > wxCanvas.height + f.r) {
				f.y = -f.r;
				f.x = Math.random() * wxCanvas.width;
			}
			if (f.x > wxCanvas.width + f.r) f.x = -f.r;
			if (f.x < -f.r) f.x = wxCanvas.width + f.r;
		}
		c.restore();
	}

	function animLoop(type: string) {
		const heavy = type === 'storm';
		function step() {
			if (type === 'rain' || type === 'storm') drawRain(heavy);
			else if (type === 'snow') drawSnow();
			animId = requestAnimationFrame(step);
		}
		step();
	}

	/* ── PARTICLES ── */
	function clearParticles() {
		const p = el<HTMLDivElement>('wx-particles');
		if (!p) return;
		// remove everything except moon and sun-wrap
		Array.from(p.children).forEach((ch) => {
			const id = (ch as HTMLElement).id;
			if (id !== 'wx-moon' && id !== 'wx-sun-wrap') ch.remove();
		});
		el<HTMLDivElement>('wx-moon')!.style.display = 'none';
		el<HTMLDivElement>('wx-sun-wrap')!.style.display = 'none';
	}

	function buildStars() {
		const p = el<HTMLDivElement>('wx-particles')!;
		// Moon visibility/position is handled by positionCelestialBodies()
		for (let i = 0; i < 115; i++) {
			const s = document.createElement('div');
			s.className = 'wx-star';
			const sz = 0.5 + Math.random() * 2.4;
			s.style.cssText = `width:${sz}px;height:${sz}px;left:${Math.random() * 100}vw;top:${Math.random() * 72}vh;opacity:${0.12 + Math.random() * 0.88};animation-duration:${1.5 + Math.random() * 5}s;animation-delay:-${Math.random() * 7}s;`;
			p.appendChild(s);
		}
		clearTimeout(shootTimeout);
		function shootStar() {
			const s = document.createElement('div');
			s.className = 'wx-shoot';
			// Random direction: mostly downward-diagonal angles spread across a wide arc
			const baseAng = 20 + Math.random() * 55; // 20-75° from horizontal
			const flip = Math.random() > 0.5 ? 1 : -1; // left or right
			const ang = flip * baseAng;
			// Spawn anywhere in the upper 2/3 of screen
			s.style.cssText = `left:${Math.random() * 80 + 5}vw;top:${Math.random() * 55 + 3}vh;--ang:${ang}deg;`;
			p.appendChild(s);
			setTimeout(() => s.remove(), 1400);
			shootTimeout = setTimeout(shootStar, 7000 + Math.random() * 20000) as unknown as number;
		}
		shootTimeout = setTimeout(shootStar, 4000 + Math.random() * 9000) as unknown as number;
	}

	function buildFireflies() {
		const p = el<HTMLDivElement>('wx-particles')!;
		for (let i = 0; i < 22; i++) {
			const f = document.createElement('div');
			f.className = 'wx-ff';
			f.style.left = `${8 + Math.random() * 84}vw`;
			f.style.top = `${22 + Math.random() * 55}vh`;
			f.style.setProperty('--d', `${3.5 + Math.random() * 6.5}s`);
			f.style.setProperty('--p', `${2.2 + Math.random() * 4.2}s`);
			f.style.setProperty('--dx', `${Math.random() * 130 - 65}px`);
			f.style.setProperty('--dy', `${Math.random() * 90 - 45}px`);
			f.style.animationDelay = `${-(Math.random() * 9)}s`;
			p.appendChild(f);
		}
	}

	function buildMist(r: number, g: number, b: number) {
		const p = el<HTMLDivElement>('wx-particles')!;
		for (let i = 0; i < 6; i++) {
			const m = document.createElement('div');
			m.className = 'wx-mist';
			m.style.height = `${55 + Math.random() * 85}px`;
			m.style.bottom = `${i * 6.5 + Math.random() * 10}vh`;
			m.style.background = `rgba(${r},${g},${b},${0.024 + Math.random() * 0.036})`;
			m.style.animationDuration = `${8 + Math.random() * 12}s`;
			m.style.animationDelay = `${-(Math.random() * 10)}s`;
			p.appendChild(m);
		}
	}

	function buildLightning() {
		const svg = el<SVGSVGElement>('wx-lightning-svg')!;
		const flash = el<HTMLDivElement>('wx-lflash')!;
		svg.style.display = 'block';
		function strike() {
			svg.style.opacity = '1';
			let startX = 300 + Math.random() * 400,
				x = startX,
				y = 0;
			const pts: [number, number][] = [[x, y]];
			while (y < 490) {
				y += 28 + Math.random() * 44;
				x += (Math.random() - 0.48) * 92;
				pts.push([x, y]);
			}
			const d = 'M' + pts.map((p) => `${p[0]},${p[1]}`).join(' L');
			const bi = Math.floor(pts.length * 0.35 + Math.random() * pts.length * 0.3);
			let bx = pts[bi][0],
				by = pts[bi][1];
			let bd = `M${bx},${by}`;
			for (let i = 0; i < 4; i++) {
				bx += (Math.random() - 0.45) * 72;
				by += 24 + Math.random() * 40;
				bd += ` L${bx},${by}`;
			}
			Array.from(svg.querySelectorAll('.wx-bolt,.wx-bolt-thin')).forEach((e) => e.remove());
			const ns = 'http://www.w3.org/2000/svg';
			const b1 = document.createElementNS(ns, 'path');
			b1.setAttribute('d', d);
			b1.setAttribute('class', 'wx-bolt');
			const b2 = document.createElementNS(ns, 'path');
			b2.setAttribute('d', d);
			b2.setAttribute('class', 'wx-bolt-thin');
			const b3 = document.createElementNS(ns, 'path');
			b3.setAttribute('d', bd);
			b3.setAttribute('class', 'wx-bolt-thin');
			svg.appendChild(b1);
			svg.appendChild(b2);
			svg.appendChild(b3);
			const te = el<HTMLSpanElement>('wx-temp')!;
			function doFlash(br: boolean, last = false) {
				flash.style.opacity = br ? '0.62' : '0.26';
				if (te) te.style.color = '#f0ecff';
				setTimeout(
					() => {
						flash.style.opacity = '0';
						if (te) te.style.color = '';
						if (last) {
							svg.style.opacity = '0';
							svg.querySelectorAll('.wx-bolt,.wx-bolt-thin').forEach((e) => e.remove());
						}
					},
					br ? 72 : 45
				);
			}
			const hasSecond = Math.random() > 0.4;
			doFlash(true, !hasSecond);
			if (hasSecond) setTimeout(() => doFlash(false, true), 130);
			lightningTimeout = setTimeout(strike, 3500 + Math.random() * 9000) as unknown as number;
		}
		lightningTimeout = setTimeout(strike, 800 + Math.random() * 2200) as unknown as number;
	}

	/* ── APPLY THEME ── */
	// precipTheme: 'rain'|'storm'|'snow'|<skyTheme> — drives particles & condition label
	// skyTheme:    always time-based — drives sky gradient, atmos, treeline, celestial bodies
	function applyTheme(precipTheme: string, skyTheme: string, windSpeed = 0) {
		_isPrecip = ['rain', 'storm', 'snow'].includes(precipTheme);

		// Cross-fade the sky background using skyTheme
		const skyPrev = el<HTMLElement>('wx-sky-prev');
		if (skyPrev && _currentTheme && _currentTheme !== skyTheme && BG_GRADIENTS[_currentTheme]) {
			skyPrev.style.transition = 'none';
			skyPrev.style.background = BG_GRADIENTS[_currentTheme];
			skyPrev.style.opacity = '1';
			void skyPrev.offsetHeight;
			skyPrev.style.transition = 'opacity 3s ease';
			skyPrev.style.opacity = '0';
		}
		const themeChanged = _currentTheme !== '' && _currentTheme !== skyTheme;
		_currentTheme = skyTheme;

		const hasAlert = container.classList.contains('has-alert');
		// Sky class drives CSS vars / atmos. Add is-precip for any precip-specific CSS.
		container.className = `wx-root t-${skyTheme}${_isPrecip ? ' is-precip' : ''}${hasAlert ? ' has-alert' : ''}`;

		// Condition label: show precip name when raining, otherwise sky theme name
		const cond = el<HTMLDivElement>('wx-condition');
		if (cond) cond.textContent = LABELS[precipTheme] || LABELS[skyTheme] || '';

		// Treeline: always keyed off skyTheme so it matches the sky color
		if (themeChanged && treeCanvas) {
			treeCanvas.style.transition = 'filter 0.35s ease';
			treeCanvas.style.filter = 'brightness(0)';
			setTimeout(() => {
				buildTreeline(skyTheme);
				treeCanvas.style.transition = 'filter 0.5s ease';
				treeCanvas.style.filter = _isPrecip ? 'brightness(0.45)' : 'brightness(1)';
			}, 370);
		} else {
			buildTreeline(skyTheme);
			if (treeCanvas) {
				treeCanvas.style.transition = 'filter 2s ease';
				treeCanvas.style.filter = _isPrecip ? 'brightness(0.45)' : 'brightness(1)';
			}
		}
		cancelAnimationFrame(animId);
		clearTimeout(lightningTimeout);
		clearTimeout(shootTimeout);
		const ctx = wxCanvas?.getContext('2d');
		if (ctx) ctx.clearRect(0, 0, wxCanvas.width, wxCanvas.height);
		el<SVGSVGElement>('wx-lightning-svg')!.style.display = 'none';
		clearParticles();
		applyParticlesAndLighting(precipTheme, skyTheme, windSpeed);
		// Position sun and moon based on real time (after particles are set up)
		positionCelestialBodies(_celestialData);
	}

	/* ── WIND STREAKS ── */
	function buildWindStreaks(windSpeed: number) {
		const p = el<HTMLDivElement>('wx-particles')!;
		// Remove old streaks
		Array.from(p.querySelectorAll('.wx-wind-streak')).forEach((e) => e.remove());
		if (windSpeed < 5) return; // no visible streaks below 5 mph
		const count = Math.round(Math.min(windSpeed / 2.5, 22)); // 2-22 streaks
		const speedFactor = Math.min(windSpeed / 30, 1); // 0-1
		for (let i = 0; i < count; i++) {
			const w = document.createElement('div');
			w.className = 'wx-wind-streak';
			const len = 60 + Math.random() * 120 + speedFactor * 80;
			const dur = (1.8 - speedFactor * 1.1 + Math.random() * 0.9).toFixed(2);
			const ang = -(8 + Math.random() * 12); // slight downward-right angle
			w.style.cssText = [
				`top:${Math.random() * 90}vh`,
				`left:${-10 + Math.random() * 80}vw`,
				`width:${len}px`,
				`--ws-dur:${dur}s`,
				`--ws-ang:${ang}deg`,
				`opacity:${(0.06 + Math.random() * 0.18 * speedFactor).toFixed(3)}`,
				`animation-delay:-${(Math.random() * parseFloat(dur)).toFixed(2)}s`
			].join(';');
			p.appendChild(w);
		}
	}

	function applyParticlesAndLighting(precipTheme: string, skyTheme: string, windSpeed = 0) {
		if (precipTheme === 'rain') {
			initRain(false);
			animLoop('rain');
		} else if (precipTheme === 'storm') {
			initRain(true);
			animLoop('storm');
			buildLightning();
		} else if (precipTheme === 'snow') {
			initSnow();
			animLoop('snow');
		} else if (skyTheme === 'night') {
			buildStars();
			buildFireflies();
		} else if (skyTheme === 'rise') {
			buildMist(235, 142, 68);
		} else if (skyTheme === 'golden') {
			buildMist(215, 132, 48);
		} else if (skyTheme === 'sunset') {
			buildMist(195, 60, 30);
		}
		// Wind streaks appear on top of any theme (skip during precip where rain/snow are already moving)
		if (precipTheme !== 'rain' && precipTheme !== 'storm' && precipTheme !== 'snow') {
			buildWindStreaks(windSpeed);
		}
	}
	function fetchAlerts(lat: number, lon: number) {
		fetch(`https://api.weather.gov/alerts/active?point=${lat.toFixed(4)},${lon.toFixed(4)}`, {
			headers: { Accept: 'application/geo+json' }
		})
			.then((r) => r.json())
			.then((data: any) => {
				const bar = el<HTMLDivElement>('wx-alert-bar')!;
				const feats = (data && data.features) || [];
				const active = feats.filter((f: any) => f.properties && f.properties.status === 'Actual');
				if (!active.length) {
					bar.style.display = 'none';
					container.classList.remove('has-alert');
					return;
				}
				const ord: Record<string, number> = {
					Extreme: 0,
					Severe: 1,
					Moderate: 2,
					Minor: 3,
					Unknown: 4
				};
				active.sort(
					(a: any, b: any) => (ord[a.properties.severity] || 4) - (ord[b.properties.severity] || 4)
				);
				const p = active[0].properties;
				const sev = (p.severity || 'Unknown').toLowerCase();
				bar.className = `sev-${sev}`;
				const hl = (p.headline || '').replace(/^[^\u2013-]*[\u2013-]\s*/, '').substring(0, 150);
				const extra = active.length > 1 ? ` (+${active.length - 1} more)` : '';
				bar.innerHTML = `<span class="wx-alert-event">⚠ ${p.event || 'Weather Alert'}</span>${hl}${extra}`;
				bar.style.display = 'block';
				container.classList.add('has-alert');
			})
			.catch(() => {});
	}

	/* ── SEVERITY HELPERS ── */
	function humSev(h: number): string {
		if (h >= 90) return 'extreme';
		if (h >= 75) return 'high';
		if (h <= 30) return 'low';
		return 'mid';
	}
	function uvSev(u: number): string {
		if (u >= 8) return 'extreme';
		if (u >= 6) return 'high';
		if (u >= 3) return 'mid';
		return 'low';
	}
	function windSev(s: number): string {
		if (s >= 30) return 'extreme';
		if (s >= 20) return 'high';
		if (s >= 10) return 'mid';
		return 'low';
	}
	function tempSev(t: number): string {
		if (t >= 100) return 'extreme';
		if (t >= 86) return 'high';
		if (t <= 32) return 'low';
		return 'mid';
	}
	function setSev(id: string, sev: string) {
		const e = el(id);
		if (e) (e as HTMLElement).dataset.sev = sev;
	}

	/* ── RENDER DATA ── */
	function render(w: WeatherData) {
		const imp = w.imperial || {};
		const temp = imp.temp != null ? Math.round(imp.temp) : '--';
		const hi = imp.heatIndex != null ? Math.round(imp.heatIndex) : null;
		const wc = imp.windChill != null ? Math.round(imp.windChill) : null;
		const set = (id: string, v: string | number) => {
			const e = el(id);
			if (e) e.textContent = String(v);
		};
		set('wx-temp', temp);
		set('wx-d-hum', w.humidity != null ? w.humidity : '--');
		set('wx-d-wind', imp.windSpeed != null ? Math.round(imp.windSpeed) : '--');
		set('wx-d-gust', imp.windGust != null ? Math.round(imp.windGust) : '--');
		set('wx-d-pres', imp.pressure != null ? imp.pressure.toFixed(2) : '--');
		set('wx-d-dew', imp.dewpt != null ? Math.round(imp.dewpt) : '--');
		set('wx-d-uv', w.uv != null ? w.uv : '--');
		set('wx-d-precip', imp.precipRate != null ? imp.precipRate.toFixed(2) : '--');
		set('wx-m-station', w.stationID || '--');
		set('wx-m-hood', w.neighborhood || w.country || '');
		set('wx-m-elev', imp.elev != null ? `${Math.round(imp.elev)}\u202fft` : '--');
		set(
			'wx-m-updated',
			w.obsTimeLocal
				? `updated ${new Date(w.obsTimeLocal).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`
				: '--'
		);
		if (w.winddir != null) set('wx-d-wdir', windDir(w.winddir));
		let fl = '';
		if (typeof temp === 'number') {
			if (hi != null && temp > 75) fl = `feels like ${hi}\u00b0\u2003heat index`;
			else if (wc != null && temp < 50) fl = `feels like ${wc}\u00b0\u2003wind chill`;
		}
		const feelsEl = el('wx-feels');
		if (feelsEl) feelsEl.textContent = fl || '\u00a0';

		// ── Severity color indicators on the data strip ──
		if (w.humidity != null) setSev('wx-d-hum', humSev(w.humidity));
		if (imp.windSpeed != null) setSev('wx-d-wind', windSev(imp.windSpeed));
		if (imp.windGust != null) setSev('wx-d-gust', windSev(imp.windGust));
		if (w.uv != null) setSev('wx-d-uv', uvSev(w.uv));
		if (typeof temp === 'number') setSev('wx-temp', tempSev(temp));

		// ── Humidity haze ──
		const hazeAlpha = w.humidity != null ? Math.max(0, (w.humidity - 40) / 60) * 0.2 : 0;
		container.style.setProperty('--haze-alpha', hazeAlpha.toFixed(3));

		// ── UV → sun intensity boost ──
		const uvFactor = w.uv != null ? Math.min(w.uv / 11, 1) : 0;
		container.style.setProperty('--uv-factor', uvFactor.toFixed(3));

		// ── Wind → tree sway speed ──
		const windSpeed = imp.windSpeed ?? 0;
		const swayDur = Math.max(2.0, 9.0 - (windSpeed / 35) * 7).toFixed(1);
		const swayAmp = Math.min(windSpeed / 5, 8).toFixed(1);
		container.style.setProperty('--wind-sway-dur', `${swayDur}s`);
		container.style.setProperty('--wind-sway-amp', `${swayAmp}px`);

		_celestialData = w;
		const precipTheme = inferTheme(w);
		const skyTheme = inferSkyTheme(w);
		applyTheme(precipTheme, skyTheme, windSpeed);
		if (w.lat != null && w.lon != null) fetchAlerts(w.lat, w.lon);
	}

	/* ── LIFECYCLE ── */
	onMount(() => {
		mounted = true;
		tickClock();
		const clockInterval = setInterval(tickClock, 1000);
		resizeCanvas();
		const onResize = () => {
			resizeCanvas();
			const theme = Array.from(container.classList)
				.find((c) => c.startsWith('t-'))
				?.replace('t-', '');
			if (theme) buildTreeline(theme);
		};
		window.addEventListener('resize', onResize);
		if (data) render(data);
		return () => {
			clearInterval(clockInterval);
			window.removeEventListener('resize', onResize);
			cancelAnimationFrame(animId);
			clearTimeout(lightningTimeout);
			clearTimeout(shootTimeout);
		};
	});

	$effect(() => {
		const d = data;
		if (mounted && d) render(d);
	});
</script>

<svelte:head>
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="" />
	<link
		href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@900&family=Outfit:wght@200;300;400&display=swap"
		rel="stylesheet"
	/>
</svelte:head>

<div id="wx-root" class="wx-root" class:entering bind:this={container}>
	<!-- sky cross-fade layer: holds the previous theme's gradient while fading out -->
	<div id="wx-sky-prev"></div>
	<div id="atmos"></div>
	<div id="wx-haze"></div>
	<canvas id="wx-canvas" bind:this={wxCanvas}></canvas>
	<canvas id="tree-canvas" bind:this={treeCanvas}></canvas>

	<div id="wx-particles">
		<div id="wx-moon"></div>
		<div id="wx-sun-wrap">
			<div id="wx-sun-halo"></div>
			<div id="wx-sun-corona"></div>
			<div id="wx-sun-core"></div>
		</div>
	</div>

	<svg id="wx-lightning-svg" viewBox="0 0 1000 600" preserveAspectRatio="xMidYMid slice">
		<defs>
			<filter id="wx-glow-f" x="-50%" y="-50%" width="200%" height="200%">
				<feGaussianBlur stdDeviation="3" result="b" />
				<feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge>
			</filter>
		</defs>
	</svg>
	<div id="wx-lflash"></div>
	<div id="wx-alert-bar"></div>

	<div id="wx-clock-wrap">
		<div id="wx-clock">--:--</div>
		<div id="wx-date">---</div>
	</div>

	<main>
		<div id="wx-condition">&nbsp;</div>
		<div class="wx-temp-hero">
			<span id="wx-temp">--</span><span class="wx-deg">°</span>
		</div>
		<div id="wx-feels">&nbsp;</div>
	</main>

	<div id="wx-data-strip">
		<div class="wx-datum">
			<span class="wx-d-label">Humidity</span><span class="wx-d-val"
				><span id="wx-d-hum">--</span><span class="wx-d-unit">%</span></span
			>
		</div>
		<div class="wx-datum">
			<span class="wx-d-label">Wind</span><span class="wx-d-val"
				><span id="wx-d-wind">--</span><span class="wx-d-unit"> mph</span>
				<span id="wx-d-wdir" style="font-size:0.7em;opacity:0.6"></span></span
			>
		</div>
		<div class="wx-datum">
			<span class="wx-d-label">Gust</span><span class="wx-d-val"
				><span id="wx-d-gust">--</span><span class="wx-d-unit"> mph</span></span
			>
		</div>
		<div class="wx-datum">
			<span class="wx-d-label">Pressure</span><span class="wx-d-val"
				><span id="wx-d-pres">--</span><span class="wx-d-unit"> &#8243;</span></span
			>
		</div>
		<div class="wx-datum">
			<span class="wx-d-label">Dew Point</span><span class="wx-d-val"
				><span id="wx-d-dew">--</span><span class="wx-d-unit">°</span></span
			>
		</div>
		<div class="wx-datum">
			<span class="wx-d-label">UV</span><span class="wx-d-val"><span id="wx-d-uv">--</span></span>
		</div>
		<div class="wx-datum">
			<span class="wx-d-label">Precip</span><span class="wx-d-val"
				><span id="wx-d-precip">--</span><span class="wx-d-unit"> in/hr</span></span
			>
		</div>
	</div>

	<div id="wx-meta">
		<span id="wx-m-station">--</span><span>·</span>
		<span id="wx-m-hood"></span><span>·</span>
		<span id="wx-m-elev">--</span><span>·</span>
		<span id="wx-m-updated">--</span>
	</div>
</div>

<style>
	/* ── CSS VARS & THEMES ── */
	:global(.wx-root) {
		--bg0: #0f1a2a;
		--bg1: #172338;
		--text: #ddeeff;
		--sub: rgba(200, 220, 255, 0.45);
		--temp-col: #e8f4ff;
		--glow-col: rgba(120, 190, 255, 0.28);
		--accent: rgba(140, 200, 255, 0.7);
	}
	:global(.wx-root.t-night) {
		--bg0: #111827;
		--bg1: #1a2540;
		--text: #d4e4f8;
		--sub: rgba(180, 205, 240, 0.42);
		--temp-col: #c8dcf4;
		--glow-col: rgba(90, 120, 200, 0.32);
		--accent: rgba(120, 165, 235, 0.7);
	}
	:global(.wx-root.t-day) {
		--bg0: #1c4a7a;
		--bg1: #2a6aaa;
		--text: #ffffff;
		--sub: rgba(255, 255, 255, 0.55);
		--temp-col: #ffffff;
		--glow-col: rgba(255, 240, 160, 0.4);
		--accent: rgba(255, 242, 120, 0.8);
	}
	:global(.wx-root.t-rise) {
		--bg0: #2a1008;
		--bg1: #6a2808;
		--text: #fce8d0;
		--sub: rgba(245, 195, 130, 0.48);
		--temp-col: #fdd8a0;
		--glow-col: rgba(245, 140, 50, 0.45);
		--accent: rgba(255, 170, 70, 0.8);
	}
	:global(.wx-root.t-golden) {
		--bg0: #251408;
		--bg1: #5a3010;
		--text: #f8e0b0;
		--sub: rgba(240, 185, 100, 0.46);
		--temp-col: #f8d080;
		--glow-col: rgba(235, 155, 45, 0.48);
		--accent: rgba(255, 195, 60, 0.8);
	}
	:global(.wx-root.t-sunset) {
		--bg0: #1a0820;
		--bg1: #4a1230;
		--text: #f4cce0;
		--sub: rgba(235, 165, 185, 0.42);
		--temp-col: #f4c0c8;
		--glow-col: rgba(215, 80, 100, 0.38);
		--accent: rgba(255, 120, 140, 0.75);
	}
	:global(.wx-root.t-rain) {
		--bg0: #101820;
		--bg1: #182838;
		--text: #bcd0e8;
		--sub: rgba(160, 195, 230, 0.42);
		--temp-col: #a8c8e8;
		--glow-col: rgba(70, 130, 195, 0.3);
		--accent: rgba(100, 165, 225, 0.7);
	}
	:global(.wx-root.t-storm) {
		--bg0: #0e0c1e;
		--bg1: #181430;
		--text: #c8c0e8;
		--sub: rgba(185, 175, 225, 0.4);
		--temp-col: #c4bcec;
		--glow-col: rgba(120, 90, 220, 0.35);
		--accent: rgba(165, 140, 255, 0.78);
	}
	:global(.wx-root.t-snow) {
		--bg0: #141c2c;
		--bg1: #1e2c44;
		--text: #d8e8f8;
		--sub: rgba(200, 220, 245, 0.45);
		--temp-col: #e4eff8;
		--glow-col: rgba(160, 200, 245, 0.3);
		--accent: rgba(190, 220, 255, 0.75);
	}

	:global(#wx-sky-prev) {
		position: fixed;
		inset: 0;
		z-index: 0;
		pointer-events: none;
		opacity: 0;
	}

	:global(.wx-root) {
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		font-family: 'Outfit', system-ui, sans-serif;
		background: linear-gradient(165deg, var(--bg0) 0%, var(--bg1) 100%);
		color: var(--text);
		position: relative;
	}

	/* ── ATMOS ── */
	:global(#atmos) {
		position: fixed;
		inset: 0;
		pointer-events: none;
		z-index: 1;
		transition:
			opacity 2s,
			background 2s;
	}
	:global(.wx-root.t-night #atmos) {
		background:
			radial-gradient(ellipse 80% 50% at 75% 8%, rgba(55, 82, 190, 0.18) 0%, transparent 60%),
			radial-gradient(ellipse 100% 45% at 50% 0%, rgba(12, 22, 80, 0.25) 0%, transparent 55%);
	}
	:global(.wx-root.t-day #atmos) {
		background:
			radial-gradient(ellipse 120% 60% at 50% 0%, rgba(120, 190, 255, 0.3) 0%, transparent 65%),
			radial-gradient(ellipse 80% 40% at 85% 20%, rgba(255, 240, 140, 0.18) 0%, transparent 50%);
	}
	:global(.wx-root.t-rise #atmos) {
		background:
			radial-gradient(ellipse 140% 60% at 22% 110%, rgba(230, 95, 30, 0.55) 0%, transparent 52%),
			radial-gradient(ellipse 90% 58% at 72% 108%, rgba(165, 40, 70, 0.28) 0%, transparent 50%);
	}
	:global(.wx-root.t-golden #atmos) {
		background:
			radial-gradient(ellipse 140% 62% at 80% 112%, rgba(215, 115, 25, 0.52) 0%, transparent 52%),
			radial-gradient(ellipse 70% 58% at 12% 110%, rgba(130, 45, 18, 0.24) 0%, transparent 50%);
	}
	:global(.wx-root.t-sunset #atmos) {
		background:
			radial-gradient(ellipse 125% 64% at 55% 114%, rgba(195, 50, 18, 0.58) 0%, transparent 52%),
			radial-gradient(ellipse 78% 68% at 5% 112%, rgba(110, 18, 90, 0.35) 0%, transparent 50%);
	}
	:global(.wx-root.t-rain #atmos) {
		background: radial-gradient(
			ellipse 100% 65% at 50% 0%,
			rgba(22, 50, 95, 0.28) 0%,
			transparent 65%
		);
	}
	:global(.wx-root.t-storm #atmos) {
		background:
			radial-gradient(ellipse 100% 70% at 50% 0%, rgba(38, 18, 108, 0.4) 0%, transparent 65%),
			radial-gradient(ellipse 80% 58% at 12% 100%, rgba(18, 5, 75, 0.25) 0%, transparent 55%);
	}
	:global(.wx-root.t-snow #atmos) {
		background: radial-gradient(
			ellipse 100% 58% at 50% 0%,
			rgba(120, 165, 230, 0.14) 0%,
			transparent 60%
		);
	}
	/* Darken the sky during any precipitation — overlaid on top of the time-of-day atmos */
	:global(.wx-root.is-precip #atmos) {
		background: rgba(0, 0, 0, 0.45);
	}

	/* ── CANVAS ── */
	:global(#wx-canvas) {
		position: fixed;
		inset: 0;
		pointer-events: none;
		z-index: 2;
	}
	:global(#tree-canvas) {
		position: fixed;
		bottom: -2px;
		left: -20px;
		width: calc(100% + 40px);
		pointer-events: none;
		z-index: 5;
	}
	:global(.wx-root.is-precip #tree-canvas) {
		filter: brightness(0.45);
		transition: filter 2s ease;
	}
	:global(#wx-particles) {
		position: fixed;
		inset: 0;
		pointer-events: none;
		z-index: 3;
		overflow: hidden;
	}

	/* ── STARS ── */
	:global(.wx-star) {
		position: absolute;
		border-radius: 50%;
		background: #d8eaff;
		animation: wx-star-pulse ease-in-out infinite;
	}
	@keyframes wx-star-pulse {
		0%,
		100% {
			opacity: 1;
			transform: scale(1);
		}
		50% {
			opacity: 0.05;
			transform: scale(0.2);
		}
	}
	:global(.wx-shoot) {
		position: absolute;
		width: 160px;
		height: 1.5px;
		background: linear-gradient(90deg, rgba(255, 255, 255, 0.9), transparent);
		transform-origin: left center;
		animation: wx-shoot-fly 1.4s ease-out forwards;
	}
	@keyframes wx-shoot-fly {
		0% {
			opacity: 0;
			transform: rotate(var(--ang, 30deg)) scaleX(0);
		}
		15% {
			opacity: 1;
		}
		100% {
			opacity: 0;
			transform: rotate(var(--ang, 30deg)) scaleX(1) translateX(35vw);
		}
	}

	/* ── WIND STREAKS ── */
	:global(.wx-wind-streak) {
		position: absolute;
		height: 1px;
		border-radius: 1px;
		background: linear-gradient(
			90deg,
			transparent 0%,
			rgba(200, 225, 255, 0.75) 40%,
			transparent 100%
		);
		pointer-events: none;
		transform-origin: left center;
		transform: rotate(var(--ws-ang, 0deg));
		animation: wx-wind-blow var(--ws-dur, 2s) linear infinite;
	}
	@keyframes wx-wind-blow {
		0% {
			transform: rotate(var(--ws-ang, 0deg)) translateX(-20vw);
			opacity: 0;
		}
		10% {
			opacity: 1;
		}
		80% {
			opacity: 0.9;
		}
		100% {
			transform: rotate(var(--ws-ang, 0deg)) translateX(110vw);
			opacity: 0;
		}
	}

	/* ── HUMIDITY HAZE ── */
	:global(#wx-haze) {
		position: fixed;
		inset: 0;
		z-index: 4;
		pointer-events: none;
		background: rgba(200, 220, 240, var(--haze-alpha, 0));
		transition: background 3s ease;
		backdrop-filter: blur(calc(var(--haze-alpha, 0) * 3px));
	}

	/* ── UV SUN BOOST ── */
	:global(#wx-sun-core) {
		scale: calc(1 + var(--uv-factor, 0) * 0.35);
	}
	:global(#wx-sun-halo) {
		scale: calc(1 + var(--uv-factor, 0) * 0.55);
		opacity: calc(0.6 + var(--uv-factor, 0) * 0.4);
	}

	/* ── WIND TREE SWAY ── */
	:global(#tree-canvas) {
		animation: wx-tree-sway var(--wind-sway-dur, 99s) ease-in-out infinite;
	}
	@keyframes wx-tree-sway {
		0%,
		100% {
			transform: translateX(0);
		}
		50% {
			transform: translateX(var(--wind-sway-amp, 0px));
		}
	}

	/* ── DATA STRIP SEVERITY COLORS ── */
	:global([data-sev='low']) {
		color: #82c4f8 !important;
	}
	:global([data-sev='mid']) {
		color: var(--text);
	}
	:global([data-sev='high']) {
		color: #f8c060 !important;
		text-shadow: 0 0 14px rgba(240, 150, 30, 0.55);
	}
	:global([data-sev='extreme']) {
		color: #f87070 !important;
		text-shadow: 0 0 16px rgba(240, 60, 40, 0.65);
		animation: wx-sev-pulse 2s ease-in-out infinite;
	}
	@keyframes wx-sev-pulse {
		0%,
		100% {
			opacity: 1;
		}
		50% {
			opacity: 0.65;
		}
	}

	/* ── MOON ── */
	/* Moon and sun are positioned and sized entirely via JS (positionCelestialBodies) */
	:global(#wx-moon) {
		display: none;
		pointer-events: none;
		transition: opacity 2s ease;
	}
	:global(#wx-sun-wrap) {
		position: absolute;
		display: none;
		pointer-events: none;
		transition: opacity 2s ease;
	}

	/* ── FIREFLIES ── */
	:global(.wx-ff) {
		position: absolute;
		width: 3px;
		height: 3px;
		border-radius: 50%;
		background: rgba(165, 220, 70, 0.75);
		animation:
			wx-ff-drift var(--d, 4.5s) ease-in-out infinite alternate,
			wx-ff-pulse var(--p, 3s) ease-in-out infinite;
	}
	@keyframes wx-ff-drift {
		from {
			transform: translate(0, 0);
		}
		to {
			transform: translate(var(--dx, 40px), var(--dy, 28px));
		}
	}
	@keyframes wx-ff-pulse {
		0%,
		18%,
		82%,
		100% {
			opacity: 0;
		}
		42%,
		58% {
			opacity: 1;
		}
	}

	/* ── SUN ── */
	:global(#wx-sun-core) {
		width: clamp(60px, 11vw, 105px);
		height: clamp(60px, 11vw, 105px);
		border-radius: 50%;
		background: radial-gradient(circle, #fff8c0 0%, #ffd840 45%, rgba(255, 180, 0, 0) 72%);
		filter: blur(2px);
		position: relative;
		z-index: 2;
		animation: wx-sun-breathe 4s ease-in-out infinite;
	}
	@keyframes wx-sun-breathe {
		0%,
		100% {
			transform: scale(1);
			filter: blur(2px) brightness(1);
		}
		50% {
			transform: scale(1.07);
			filter: blur(3px) brightness(1.1);
		}
	}
	:global(#wx-sun-corona) {
		position: absolute;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: clamp(110px, 22vw, 200px);
		height: clamp(110px, 22vw, 200px);
		border-radius: 50%;
		background: conic-gradient(
			rgba(255, 225, 80, 0.22) 0deg,
			rgba(255, 225, 80, 0.04) 10deg,
			rgba(255, 225, 80, 0.22) 20deg,
			rgba(255, 225, 80, 0.04) 30deg,
			rgba(255, 225, 80, 0.22) 40deg,
			rgba(255, 225, 80, 0.04) 50deg,
			rgba(255, 225, 80, 0.22) 60deg,
			rgba(255, 225, 80, 0.04) 70deg,
			rgba(255, 225, 80, 0.22) 80deg,
			rgba(255, 225, 80, 0.04) 90deg,
			rgba(255, 225, 80, 0.22) 100deg,
			rgba(255, 225, 80, 0.04) 110deg,
			rgba(255, 225, 80, 0.22) 120deg,
			rgba(255, 225, 80, 0.04) 130deg,
			rgba(255, 225, 80, 0.22) 140deg,
			rgba(255, 225, 80, 0.04) 150deg,
			rgba(255, 225, 80, 0.22) 160deg,
			rgba(255, 225, 80, 0.04) 170deg,
			rgba(255, 225, 80, 0.22) 180deg,
			rgba(255, 225, 80, 0.04) 190deg,
			rgba(255, 225, 80, 0.22) 200deg,
			rgba(255, 225, 80, 0.04) 210deg,
			rgba(255, 225, 80, 0.22) 220deg,
			rgba(255, 225, 80, 0.04) 230deg,
			rgba(255, 225, 80, 0.22) 240deg,
			rgba(255, 225, 80, 0.04) 250deg,
			rgba(255, 225, 80, 0.22) 260deg,
			rgba(255, 225, 80, 0.04) 270deg,
			rgba(255, 225, 80, 0.22) 280deg,
			rgba(255, 225, 80, 0.04) 290deg,
			rgba(255, 225, 80, 0.22) 300deg,
			rgba(255, 225, 80, 0.04) 310deg,
			rgba(255, 225, 80, 0.22) 320deg,
			rgba(255, 225, 80, 0.04) 330deg,
			rgba(255, 225, 80, 0.22) 340deg,
			rgba(255, 225, 80, 0.04) 350deg,
			rgba(255, 225, 80, 0.22) 360deg
		);
		filter: blur(8px);
		animation: wx-ray-spin 16s linear infinite;
		z-index: 1;
	}
	@keyframes wx-ray-spin {
		to {
			transform: translate(-50%, -50%) rotate(360deg);
		}
	}
	:global(#wx-sun-halo) {
		position: absolute;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: clamp(200px, 38vw, 360px);
		height: clamp(200px, 38vw, 360px);
		border-radius: 50%;
		background: radial-gradient(
			circle,
			rgba(255, 230, 80, 0.22) 0%,
			rgba(255, 200, 40, 0.08) 45%,
			transparent 70%
		);
		filter: blur(20px);
		animation: wx-sun-breathe 4s ease-in-out infinite;
		z-index: 0;
	}

	/* ── MIST ── */
	:global(.wx-mist) {
		position: absolute;
		left: -15%;
		width: 130%;
		border-radius: 50%;
		filter: blur(32px);
		animation: wx-mist-flow ease-in-out infinite alternate;
	}
	@keyframes wx-mist-flow {
		from {
			transform: translateX(0);
		}
		to {
			transform: translateX(30px);
		}
	}

	/* ── LIGHTNING ── */
	:global(#wx-lightning-svg) {
		position: fixed;
		inset: 0;
		pointer-events: none;
		z-index: 20;
		display: none;
	}
	:global(.wx-bolt) {
		stroke: rgba(220, 210, 255, 0.92);
		stroke-width: 2;
		fill: none;
		filter: url(#wx-glow-f);
	}
	:global(.wx-bolt-thin) {
		stroke: rgba(255, 255, 255, 0.45);
		stroke-width: 0.8;
		fill: none;
	}
	:global(#wx-lflash) {
		position: fixed;
		inset: 0;
		background: rgba(210, 200, 255, 0.85);
		opacity: 0;
		pointer-events: none;
		z-index: 19;
		transition: opacity 0.03s;
	}

	/* ── ALERT BAR ── */
	:global(#wx-alert-bar) {
		position: fixed;
		top: 0;
		left: 0;
		right: 0;
		z-index: 30;
		display: none;
		padding: 10px clamp(16px, 3vw, 48px);
		background: rgba(210, 110, 10, 0.8);
		backdrop-filter: blur(12px);
		font-family: 'Outfit', sans-serif;
		font-weight: 400;
		font-size: clamp(11px, 1.5vw, 15px);
		letter-spacing: 0.06em;
		color: #fff;
		text-align: center;
		border-bottom: 1px solid rgba(255, 255, 255, 0.18);
		text-shadow: 0 1px 5px rgba(0, 0, 0, 0.45);
	}
	:global(#wx-alert-bar.sev-extreme) {
		background: rgba(195, 18, 18, 0.86);
	}
	:global(#wx-alert-bar.sev-severe) {
		background: rgba(205, 55, 8, 0.82);
	}
	:global(#wx-alert-bar.sev-moderate) {
		background: rgba(200, 125, 8, 0.8);
	}
	:global(#wx-alert-bar.sev-minor) {
		background: rgba(22, 110, 200, 0.74);
	}
	:global(.wx-alert-event) {
		font-weight: 600;
		margin-right: 7px;
	}

	/* ── CLOCK ── */
	:global(#wx-clock-wrap) {
		position: fixed;
		top: clamp(16px, 3vh, 30px);
		right: clamp(20px, 3.5vw, 40px);
		z-index: 11;
		text-align: right;
		pointer-events: none;
		transition: top 0.4s ease;
	}
	:global(.wx-root.has-alert #wx-clock-wrap) {
		top: calc(clamp(16px, 3vh, 30px) + 52px);
	}
	:global(#wx-clock) {
		font-family: 'Outfit', sans-serif;
		font-weight: 200;
		font-size: clamp(22px, 4vw, 38px);
		color: var(--text);
		letter-spacing: 0.05em;
		opacity: 0.55;
	}
	:global(#wx-date) {
		font-family: 'Outfit', sans-serif;
		font-weight: 300;
		font-size: clamp(8px, 1.1vw, 11px);
		color: var(--sub);
		letter-spacing: 0.22em;
		text-transform: uppercase;
		opacity: 0.35;
		margin-top: 2px;
	}

	/* ── MAIN TEMP ── */
	:global(.wx-root main) {
		position: fixed;
		inset: 0;
		z-index: 10;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		pointer-events: none;
		padding: 0 4vw 18vh;
	}
	:global(#wx-condition) {
		font-family: 'Outfit', sans-serif;
		font-weight: 300;
		font-size: clamp(11px, 2.2vw, 20px);
		letter-spacing: 0.45em;
		text-transform: uppercase;
		color: var(--accent);
		opacity: 0.88;
		margin-bottom: clamp(6px, 1.2vh, 16px);
		min-height: 1.3em;
		transition: color 1s;
	}
	:global(.wx-temp-hero) {
		line-height: 1;
		display: flex;
		align-items: flex-start;
	}
	:global(#wx-temp) {
		font-family: 'Big Shoulders Display', sans-serif;
		font-weight: 900;
		font-size: clamp(130px, 32vw, 290px);
		color: var(--temp-col);
		line-height: 0.88;
		letter-spacing: -0.02em;
		text-shadow:
			0 0 clamp(30px, 6vw, 80px) var(--glow-col),
			0 0 clamp(80px, 16vw, 200px) var(--glow-col);
		transition:
			color 1s,
			text-shadow 1s;
		position: relative;
		z-index: 1;
	}
	:global(.wx-deg) {
		font-family: 'Big Shoulders Display', sans-serif;
		font-weight: 900;
		font-size: clamp(40px, 8vw, 80px);
		color: var(--temp-col);
		opacity: 0.5;
		padding-top: clamp(16px, 3vw, 38px);
		padding-left: 4px;
		line-height: 1;
		transition: color 1s;
	}
	:global(#wx-feels) {
		font-family: 'Outfit', sans-serif;
		font-weight: 300;
		font-size: clamp(11px, 1.8vw, 17px);
		color: var(--sub);
		letter-spacing: 0.12em;
		margin-top: clamp(8px, 1.2vh, 16px);
		min-height: 1.4em;
		transition: color 1s;
	}

	/* ── DATA STRIP ── */
	:global(#wx-data-strip) {
		position: fixed;
		bottom: clamp(22px, 5.5vh, 52px);
		left: 0;
		right: 0;
		z-index: 11;
		display: flex;
		justify-content: center;
		align-items: flex-end;
		flex-wrap: wrap;
		padding: 0 5vw;
		pointer-events: none;
	}
	:global(.wx-datum) {
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 0 clamp(12px, 2.2vw, 28px);
		position: relative;
	}
	:global(.wx-datum + .wx-datum::before) {
		content: '';
		position: absolute;
		left: 0;
		top: 20%;
		height: 60%;
		width: 1px;
		background: rgba(255, 255, 255, 0.1);
	}
	:global(.wx-d-label) {
		font-family: 'Outfit', sans-serif;
		font-weight: 300;
		font-size: clamp(8px, 1.1vw, 12px);
		letter-spacing: 0.28em;
		text-transform: uppercase;
		color: var(--sub);
		opacity: 0.6;
		margin-bottom: 4px;
	}
	:global(.wx-d-val) {
		font-family: 'Outfit', sans-serif;
		font-weight: 400;
		font-size: clamp(18px, 2.6vw, 28px);
		color: var(--text);
		letter-spacing: 0.04em;
	}
	:global(.wx-d-unit) {
		font-size: 0.62em;
		opacity: 0.55;
		font-weight: 300;
		margin-left: 1px;
	}

	/* ── META ── */
	:global(#wx-meta) {
		position: fixed;
		bottom: clamp(5px, 1vh, 10px);
		left: 0;
		right: 0;
		z-index: 11;
		display: flex;
		justify-content: center;
		gap: 12px;
		pointer-events: none;
		font-family: 'Outfit', sans-serif;
		font-weight: 300;
		font-size: clamp(7px, 0.9vw, 9px);
		letter-spacing: 0.2em;
		text-transform: uppercase;
		color: var(--sub);
		opacity: 0.35;
	}

	/* ── ENTRANCE ANIMATIONS ── */
	@keyframes wx-slide-up {
		from {
			transform: translateY(32px);
		}
		to {
			transform: translateY(0);
		}
	}
	@keyframes wx-slide-down {
		from {
			transform: translateY(-22px);
		}
		to {
			transform: translateY(0);
		}
	}
	@keyframes wx-cond-enter {
		from {
			opacity: 0;
		}
		to {
			opacity: 0.88;
		}
	}

	:global(.wx-root.entering .wx-temp-hero) {
		animation: wx-slide-up 0.9s 0.12s cubic-bezier(0.22, 0.61, 0.36, 1) both;
	}
	:global(.wx-root.entering #wx-clock-wrap) {
		animation: wx-slide-down 0.7s 0.32s cubic-bezier(0.22, 0.61, 0.36, 1) both;
	}
	:global(.wx-root.entering #wx-data-strip) {
		animation: wx-slide-up 0.75s 0.55s cubic-bezier(0.22, 0.61, 0.36, 1) both;
	}
	:global(.wx-root.entering #tree-canvas) {
		animation: wx-slide-up 1s 0.2s cubic-bezier(0.22, 0.61, 0.36, 1) both;
	}
	:global(.wx-root.entering #wx-condition) {
		animation: wx-cond-enter 0.6s 0.18s ease-out both;
	}
</style>
