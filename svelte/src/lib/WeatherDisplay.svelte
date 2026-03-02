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

	// Canvas state — rain & snow
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
	let mounted = false;

	// Canvas-based particle state (replaces DOM particles for GPU efficiency)
	let cStars: { x: number; y: number; sz: number; baseOp: number; phase: number; speed: number }[] = [];
	let cFireflies: { x: number; y: number; dx: number; dy: number; driftDur: number; pulseDur: number; phase: number }[] = [];
	let cMist: { y: number; h: number; r: number; g: number; b: number; op: number; speed: number; offset: number }[] = [];
	let cWindStreaks: { x: number; y: number; len: number; speed: number; ang: number; op: number }[] = [];
	let cShootStar = { active: false, x: 0, y: 0, ang: 0, progress: 0, speed: 0 };

	// Unified animation loop state
	let lastFrameTime = 0;
	let lastCelestialTime = 0;
	let nextShootTime = 0;
	let currentAnimType = '';

	// Moon phase cache — avoid re-rendering 7-9 gradient ops every tick
	let lastRenderedPhase = -1;
	let moonPhaseCv: HTMLCanvasElement | null = null;

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
		if (c) c.textContent = `${h}:${pad(d.getMinutes())}\u202f${ap}`;
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
		if (dt) dt.textContent = `${days[d.getDay()]}  ·  ${months[d.getMonth()]} ${d.getDate()}`;
		// Celestial repositioning moved to unified animation loop (every 30s)
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
		// Cache: only re-render when phase changes meaningfully (~1 hour)
		if (Math.abs(phase - lastRenderedPhase) < 0.002 && moonPhaseCv) {
			if (!moonEl.contains(moonPhaseCv)) {
				moonEl.innerHTML = '';
				moonEl.appendChild(moonPhaseCv);
			}
			return;
		}
		lastRenderedPhase = phase;

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
		moonPhaseCv = cv;
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

	/* ── CANVAS ── */
	function resizeCanvas() {
		if (!wxCanvas) return;
		wxCanvas.width = window.innerWidth;
		wxCanvas.height = window.innerHeight;
	}

	function initRain(heavy: boolean) {
		const count = heavy ? 120 : 60,
			angle = heavy ? 18 : 7;
		drops = [];
		for (let i = 0; i < count; i++)
			drops.push({
				x: Math.random() * (wxCanvas.width + 200) - 100,
				y: Math.random() * wxCanvas.height,
				len: heavy ? 22 + Math.random() * 20 : 14 + Math.random() * 12,
				spd: heavy ? 9 + Math.random() * 7 : 5 + Math.random() * 4,
				op: 0.18 + Math.random() * 0.48,
				ang: ((angle + (Math.random() - 0.5) * 6) * Math.PI) / 180
			});
	}

	function drawRain(ctx: CanvasRenderingContext2D, heavy: boolean) {
		// Batch into 4 opacity buckets — one stroke() per bucket
		const buckets: (typeof drops)[] = [[], [], [], []];
		for (const d of drops) {
			buckets[Math.min(3, (d.op * 4) | 0)].push(d);
		}
		const rgb = heavy ? '160,200,245' : '120,175,225';
		ctx.lineWidth = heavy ? 1.4 : 0.9;
		for (let bi = 0; bi < 4; bi++) {
			if (!buckets[bi].length) continue;
			ctx.strokeStyle = `rgba(${rgb},${((bi + 0.5) / 4).toFixed(2)})`;
			ctx.beginPath();
			for (const d of buckets[bi]) {
				ctx.moveTo(d.x, d.y);
				ctx.lineTo(d.x + Math.sin(d.ang) * d.len, d.y + Math.cos(d.ang) * d.len);
				d.y += d.spd;
				d.x += Math.sin(d.ang) * d.spd;
				if (d.y > wxCanvas.height) {
					d.y = -d.len;
					d.x = Math.random() * (wxCanvas.width + 200) - 100;
				}
			}
			ctx.stroke();
		}
	}

	function initSnow() {
		flakes = [];
		for (let i = 0; i < 60; i++)
			flakes.push({
				x: Math.random() * wxCanvas.width,
				y: Math.random() * wxCanvas.height,
				r: 1.2 + Math.random() * 4.5,
				spd: 0.2 + Math.random() * 0.5,
				drift: (Math.random() - 0.5) * 0.3,
				op: 0.35 + Math.random() * 0.55,
				off: Math.random() * Math.PI * 2
			});
	}

	function drawSnow(ctx: CanvasRenderingContext2D) {
		snowT += 0.008;
		// Batch into 4 opacity buckets
		const buckets: (typeof flakes)[] = [[], [], [], []];
		for (const f of flakes) {
			buckets[Math.min(3, ((f.op - 0.35) / 0.55 * 4) | 0)].push(f);
		}
		for (let bi = 0; bi < 4; bi++) {
			if (!buckets[bi].length) continue;
			ctx.fillStyle = `rgba(215,235,252,${(0.35 + (bi + 0.5) / 4 * 0.55).toFixed(2)})`;
			ctx.beginPath();
			for (const f of buckets[bi]) {
				ctx.moveTo(f.x + f.r, f.y);
				ctx.arc(f.x, f.y, f.r, 0, Math.PI * 2);
				f.y += f.spd;
				f.x += f.drift + Math.sin(snowT + f.off) * 0.5;
				if (f.y > wxCanvas.height + f.r) { f.y = -f.r; f.x = Math.random() * wxCanvas.width; }
				if (f.x > wxCanvas.width + f.r) f.x = -f.r;
				if (f.x < -f.r) f.x = wxCanvas.width + f.r;
			}
			ctx.fill();
		}
	}

	/* ── CANVAS PARTICLE DRAWING (replaces ~40 DOM elements) ── */
	function drawStarsCanvas(ctx: CanvasRenderingContext2D, now: number) {
		for (const s of cStars) {
			const op = s.baseOp * (0.5 + 0.5 * Math.sin(now * s.speed * 0.001 + s.phase));
			if (op < 0.02) continue;
			ctx.fillStyle = `rgba(216,234,255,${op.toFixed(2)})`;
			ctx.fillRect(s.x, s.y, s.sz, s.sz);
		}
	}

	function drawFirefliesCanvas(ctx: CanvasRenderingContext2D, now: number) {
		const t = now * 0.001;
		for (const f of cFireflies) {
			const dx = Math.sin(t / f.driftDur + f.phase) * f.dx;
			const dy = Math.cos(t / f.driftDur + f.phase) * f.dy;
			const pulse = Math.sin(t * Math.PI / f.pulseDur + f.phase);
			const op = pulse > 0.3 ? (pulse - 0.3) / 0.7 : 0;
			if (op < 0.02) continue;
			ctx.fillStyle = `rgba(165,220,70,${(op * 0.75).toFixed(2)})`;
			ctx.beginPath();
			ctx.arc(f.x + dx, f.y + dy, 1.5, 0, Math.PI * 2);
			ctx.fill();
		}
	}

	function drawMistCanvas(ctx: CanvasRenderingContext2D, now: number) {
		const W = wxCanvas.width;
		for (const m of cMist) {
			const x = Math.sin(now * 0.001 / m.speed + m.offset) * 15;
			ctx.fillStyle = `rgba(${m.r},${m.g},${m.b},${m.op.toFixed(3)})`;
			ctx.fillRect(x - W * 0.15, wxCanvas.height - m.y - m.h, W * 1.3, m.h);
		}
	}

	function drawWindStreaksCanvas(ctx: CanvasRenderingContext2D) {
		ctx.lineWidth = 1;
		for (const w of cWindStreaks) {
			w.x += w.speed;
			if (w.x > wxCanvas.width * 1.1) {
				w.x = -w.len - Math.random() * wxCanvas.width * 0.2;
				w.y = Math.random() * wxCanvas.height * 0.9;
			}
			const rad = w.ang * Math.PI / 180;
			ctx.strokeStyle = `rgba(200,225,255,${w.op.toFixed(3)})`;
			ctx.beginPath();
			ctx.moveTo(w.x, w.y);
			ctx.lineTo(w.x + Math.cos(rad) * w.len, w.y + Math.sin(rad) * w.len);
			ctx.stroke();
		}
	}

	function drawShootingStarCanvas(ctx: CanvasRenderingContext2D) {
		const s = cShootStar;
		if (!s.active) return;
		s.progress += s.speed;
		if (s.progress >= 1) { s.active = false; return; }
		const rad = s.ang * Math.PI / 180;
		const dist = 0.35 * wxCanvas.width;
		const curX = s.x + Math.cos(rad) * dist * s.progress;
		const curY = s.y + Math.sin(rad) * dist * s.progress;
		const tailLen = dist * 0.15;
		const tailX = curX - Math.cos(rad) * tailLen;
		const tailY = curY - Math.sin(rad) * tailLen;
		const grad = ctx.createLinearGradient(tailX, tailY, curX, curY);
		const op = s.progress < 0.15 ? s.progress / 0.15 : Math.max(0, 1 - (s.progress - 0.5) / 0.5);
		grad.addColorStop(0, 'rgba(255,255,255,0)');
		grad.addColorStop(1, `rgba(255,255,255,${(op * 0.9).toFixed(2)})`);
		ctx.strokeStyle = grad;
		ctx.lineWidth = 1.5;
		ctx.beginPath();
		ctx.moveTo(tailX, tailY);
		ctx.lineTo(curX, curY);
		ctx.stroke();
	}

	/* ── CANVAS PARTICLE INITIALIZERS ── */
	function initStarsCanvas() {
		cStars = [];
		const W = wxCanvas.width, H = wxCanvas.height;
		for (let i = 0; i < 12; i++) {
			cStars.push({
				x: Math.random() * W, y: Math.random() * H * 0.72,
				sz: 0.5 + Math.random() * 2.4, baseOp: 0.12 + Math.random() * 0.88,
				phase: Math.random() * Math.PI * 2, speed: 0.4 + Math.random() * 1.2
			});
		}
		nextShootTime = performance.now() + 4000 + Math.random() * 9000;
	}

	function initFirefliesCanvas() {
		cFireflies = [];
		for (let i = 0; i < 3; i++) {
			cFireflies.push({
				x: wxCanvas.width * (0.08 + Math.random() * 0.84),
				y: wxCanvas.height * (0.22 + Math.random() * 0.55),
				dx: Math.random() * 130 - 65, dy: Math.random() * 90 - 45,
				driftDur: 3.5 + Math.random() * 6.5, pulseDur: 2.2 + Math.random() * 4.2,
				phase: Math.random() * Math.PI * 2
			});
		}
	}

	function initMistCanvas(r: number, g: number, b: number) {
		cMist = [];
		for (let i = 0; i < 3; i++) {
			cMist.push({
				y: i * 6.5 * wxCanvas.height / 100 + Math.random() * wxCanvas.height * 0.1,
				h: 55 + Math.random() * 85, r, g, b,
				op: 0.024 + Math.random() * 0.036,
				speed: 8 + Math.random() * 12, offset: Math.random() * Math.PI * 2
			});
		}
	}

	function initWindStreaksCanvas(windSpeed: number) {
		cWindStreaks = [];
		if (windSpeed < 5) return;
		const count = Math.round(Math.min(windSpeed / 5, 5));
		const speedFactor = Math.min(windSpeed / 30, 1);
		for (let i = 0; i < count; i++) {
			cWindStreaks.push({
				x: Math.random() * wxCanvas.width, y: Math.random() * wxCanvas.height * 0.9,
				len: 60 + Math.random() * 120 + speedFactor * 80,
				speed: 2 + speedFactor * 4 + Math.random() * 2,
				ang: -(8 + Math.random() * 12),
				op: 0.06 + Math.random() * 0.18 * speedFactor
			});
		}
	}

	/* ── UNIFIED ANIMATION LOOP (20 FPS) ── */
	function startAnimLoop() {
		cancelAnimationFrame(animId);
		lastFrameTime = 0;

		function step(now: number) {
			if (now - lastFrameTime < 50) { animId = requestAnimationFrame(step); return; }
			lastFrameTime = now;

			const ctx = wxCanvas?.getContext('2d');
			if (!ctx) { animId = requestAnimationFrame(step); return; }

			const hasWork = drops.length > 0 || flakes.length > 0 || cStars.length > 0 ||
				cFireflies.length > 0 || cMist.length > 0 || cWindStreaks.length > 0 || cShootStar.active;

			if (hasWork) {
				ctx.clearRect(0, 0, wxCanvas.width, wxCanvas.height);
				const heavy = currentAnimType === 'storm';
				if (currentAnimType === 'rain' || currentAnimType === 'storm') drawRain(ctx, heavy);
				else if (currentAnimType === 'snow') drawSnow(ctx);
				if (cStars.length) drawStarsCanvas(ctx, now);
				if (cFireflies.length) drawFirefliesCanvas(ctx, now);
				if (cMist.length) drawMistCanvas(ctx, now);
				if (cWindStreaks.length) drawWindStreaksCanvas(ctx);
				if (cShootStar.active) drawShootingStarCanvas(ctx);
			}

			// Shooting star scheduling
			if (cStars.length && now > nextShootTime) {
				const baseAng = 20 + Math.random() * 55;
				const flip = Math.random() > 0.5 ? 1 : -1;
				cShootStar = {
					active: true,
					x: (Math.random() * 80 + 5) * wxCanvas.width / 100,
					y: (Math.random() * 55 + 3) * wxCanvas.height / 100,
					ang: flip * baseAng, progress: 0, speed: 0.015 + Math.random() * 0.01
				};
				nextShootTime = now + 15000 + Math.random() * 20000;
			}

			// Celestial body repositioning (every 30s)
			if (now - lastCelestialTime > 30000) {
				lastCelestialTime = now;
				positionCelestialBodies(_celestialData);
			}

			animId = requestAnimationFrame(step);
		}
		animId = requestAnimationFrame(step);
	}

	/* ── PARTICLES RESET ── */
	function clearParticles() {
		el<HTMLDivElement>('wx-moon')!.style.display = 'none';
		el<HTMLDivElement>('wx-sun-wrap')!.style.display = 'none';
		drops = []; flakes = [];
		cStars = []; cFireflies = []; cMist = []; cWindStreaks = [];
		cShootStar = { active: false, x: 0, y: 0, ang: 0, progress: 0, speed: 0 };
		currentAnimType = '';
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

	// Atmos gradients — merged into root background via JS (eliminates #atmos layer)
	const ATMOS_GRADIENTS: Record<string, string> = {
		night: 'radial-gradient(ellipse 80% 50% at 75% 8%,rgba(55,82,190,0.18) 0%,transparent 60%),radial-gradient(ellipse 100% 45% at 50% 0%,rgba(12,22,80,0.25) 0%,transparent 55%)',
		day: 'radial-gradient(ellipse 120% 60% at 50% 0%,rgba(120,190,255,0.3) 0%,transparent 65%),radial-gradient(ellipse 80% 40% at 85% 20%,rgba(255,240,140,0.18) 0%,transparent 50%)',
		rise: 'radial-gradient(ellipse 140% 60% at 22% 110%,rgba(230,95,30,0.55) 0%,transparent 52%),radial-gradient(ellipse 90% 58% at 72% 108%,rgba(165,40,70,0.28) 0%,transparent 50%)',
		golden: 'radial-gradient(ellipse 140% 62% at 80% 112%,rgba(215,115,25,0.52) 0%,transparent 52%),radial-gradient(ellipse 70% 58% at 12% 110%,rgba(130,45,18,0.24) 0%,transparent 50%)',
		sunset: 'radial-gradient(ellipse 125% 64% at 55% 114%,rgba(195,50,18,0.58) 0%,transparent 52%),radial-gradient(ellipse 78% 68% at 5% 112%,rgba(110,18,90,0.35) 0%,transparent 50%)',
		rain: 'radial-gradient(ellipse 100% 65% at 50% 0%,rgba(22,50,95,0.28) 0%,transparent 65%)',
		storm: 'radial-gradient(ellipse 100% 70% at 50% 0%,rgba(38,18,108,0.4) 0%,transparent 65%),radial-gradient(ellipse 80% 58% at 12% 100%,rgba(18,5,75,0.25) 0%,transparent 55%)',
		snow: 'radial-gradient(ellipse 100% 58% at 50% 0%,rgba(120,165,230,0.14) 0%,transparent 60%)'
	};

	/* ── APPLY THEME ── */
	function applyTheme(precipTheme: string, skyTheme: string, windSpeed = 0) {
		_isPrecip = ['rain', 'storm', 'snow'].includes(precipTheme);

		// Cross-fade the sky background using skyTheme
		const skyPrev = el<HTMLElement>('wx-sky-prev');
		if (skyPrev && _currentTheme && _currentTheme !== skyTheme && BG_GRADIENTS[_currentTheme]) {
			skyPrev.style.transition = 'none';
			skyPrev.style.background = BG_GRADIENTS[_currentTheme];
			skyPrev.style.opacity = '1';
			skyPrev.style.display = 'block';
			void skyPrev.offsetHeight;
			skyPrev.style.transition = 'opacity 3s ease';
			skyPrev.style.opacity = '0';
			// Hide from compositor after fade completes
			setTimeout(() => { if (skyPrev.style.opacity === '0') skyPrev.style.display = 'none'; }, 3200);
		}
		const themeChanged = _currentTheme !== '' && _currentTheme !== skyTheme;
		_currentTheme = skyTheme;

		const hasAlert = container.classList.contains('has-alert');
		container.className = `wx-root t-${skyTheme}${_isPrecip ? ' is-precip' : ''}${hasAlert ? ' has-alert' : ''}`;

		// Merge atmos gradient + haze into root background (eliminates 2 compositor layers)
		const skyGrad = BG_GRADIENTS[skyTheme] || BG_GRADIENTS['night'];
		const atmosGrad = _isPrecip ? 'linear-gradient(rgba(0,0,0,0.45),rgba(0,0,0,0.45))' : (ATMOS_GRADIENTS[skyTheme] || '');
		container.style.background = atmosGrad ? `${atmosGrad},${skyGrad}` : skyGrad;

		const cond = el<HTMLDivElement>('wx-condition');
		if (cond) cond.textContent = LABELS[precipTheme] || LABELS[skyTheme] || '';

		// Treeline
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

		// Tree sway: skip animation entirely when wind < 3
		if (treeCanvas) {
			treeCanvas.style.animation = windSpeed < 3 ? 'none' : '';
		}

		cancelAnimationFrame(animId);
		clearTimeout(lightningTimeout);
		const ctx = wxCanvas?.getContext('2d');
		if (ctx) ctx.clearRect(0, 0, wxCanvas.width, wxCanvas.height);
		el<SVGSVGElement>('wx-lightning-svg')!.style.display = 'none';
		clearParticles();
		applyParticlesAndLighting(precipTheme, skyTheme, windSpeed);
		positionCelestialBodies(_celestialData);
		startAnimLoop();
	}

	function applyParticlesAndLighting(precipTheme: string, skyTheme: string, windSpeed = 0) {
		if (precipTheme === 'rain') {
			currentAnimType = 'rain';
			initRain(false);
		} else if (precipTheme === 'storm') {
			currentAnimType = 'storm';
			initRain(true);
			buildLightning();
		} else if (precipTheme === 'snow') {
			currentAnimType = 'snow';
			initSnow();
		} else if (skyTheme === 'night') {
			initStarsCanvas();
			initFirefliesCanvas();
		} else if (skyTheme === 'rise') {
			initMistCanvas(235, 142, 68);
		} else if (skyTheme === 'golden') {
			initMistCanvas(215, 132, 48);
		} else if (skyTheme === 'sunset') {
			initMistCanvas(195, 60, 30);
		}
		if (precipTheme !== 'rain' && precipTheme !== 'storm' && precipTheme !== 'snow') {
			initWindStreaksCanvas(windSpeed);
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

		// ── Humidity haze (merged into root background in applyTheme) ──

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
		// Initial celestial positioning
		positionCelestialBodies(_celestialData);
		return () => {
			clearInterval(clockInterval);
			window.removeEventListener('resize', onResize);
			cancelAnimationFrame(animId);
			clearTimeout(lightningTimeout);
		};
	});

	$effect(() => {
		const d = data;
		if (mounted && d) render(d);
	});
</script>

<div id="wx-root" class="wx-root" class:entering bind:this={container}>
	<!-- sky cross-fade layer: holds the previous theme's gradient while fading out -->
	<div id="wx-sky-prev"></div>
	<!-- #atmos and #wx-haze removed — merged into root background via JS -->
	<canvas id="wx-canvas" bind:this={wxCanvas}></canvas>
	<canvas id="tree-canvas" bind:this={treeCanvas}></canvas>

	<div id="wx-particles">
		<div id="wx-moon"></div>
		<div id="wx-sun-wrap">
			<div id="wx-sun-halo"></div>
			<div id="wx-sun-core"></div>
		</div>
	</div>

	<svg id="wx-lightning-svg" viewBox="0 0 1000 600" preserveAspectRatio="xMidYMid slice">
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
		display: none; /* hidden from compositor when not cross-fading */
	}

	:global(.wx-root) {
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		font-family: 'Outfit', system-ui, sans-serif;
		background: linear-gradient(165deg, var(--bg0) 0%, var(--bg1) 100%);
		color: var(--text);
		position: relative;
		contain: strict;
	}
	/* #atmos removed — gradient merged into root background via JS */

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
	}
	/* Stars, fireflies, mist, wind streaks, shooting stars all canvas-rendered now */
	/* #wx-haze removed — merged into root background */

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

	/* Fireflies, mist now canvas-rendered */

	/* ── SUN (no blur, no corona, no breathe animation) ── */
	:global(#wx-sun-core) {
		width: clamp(60px, 11vw, 105px);
		height: clamp(60px, 11vw, 105px);
		border-radius: 50%;
		/* Softness baked into gradient — no filter: blur() needed */
		background: radial-gradient(circle, #fff8c0 0%, #ffd840 35%, rgba(255,200,0,0.15) 55%, rgba(255,180,0,0) 72%);
		position: relative;
		z-index: 2;
	}
	/* Corona replaced with simple radial glow — no conic-gradient, no blur, no rotation */
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
			rgba(255, 225, 80, 0.20) 0%,
			rgba(255, 220, 60, 0.08) 40%,
			transparent 70%
		);
		z-index: 0;
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
		stroke: rgba(235, 225, 255, 0.95);
		stroke-width: 3;
		fill: none;
		/* filter: url(#wx-glow-f) removed — faked with thicker stroke + brighter color */
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
		/* backdrop-filter removed — too GPU-expensive on low-power devices */
		background: rgba(200, 100, 5, 0.92);
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
