<script lang="ts">
	import { onMount } from 'svelte';
	import WeatherDisplay, {
		type WeatherData,
		type ArcConfig,
		ARC_DEFAULTS
	} from '$lib/WeatherDisplay.svelte';
	import { getSunTimes } from '$lib/sunTimes';

	/* ── live-fetch state ── */
	let useLive = $state(false);
	let liveData = $state<WeatherData | null>(null);

	async function fetchLive() {
		try {
			liveData = await (await fetch('/api/weather')).json();
		} catch {
			liveData = {};
		}
	}

	/* ── slider state ── */
	let temp = $state(65); // °F
	let precipRate = $state(0); // in/hr
	let windGust = $state(0); // mph
	let windSpeed = $state(0); // mph
	let humidity = $state(55); // %
	let dewPt = $state(45); // °F
	let pressure = $state(29.92); // inHg
	let uv = $state(3);
	let useLiveTime = $state(true);
	let manualTime = $state(
		(() => {
			const d = new Date();
			return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
		})()
	);

	// Fractional local hour from the time picker, or null to use real clock
	const timeOverride = $derived<number | null>(
		useLiveTime
			? null
			: parseInt(manualTime.split(':')[0]) + parseInt(manualTime.split(':')[1]) / 60
	);

	/* synthetic WeatherData from sliders */
	const syntheticData = $derived<WeatherData>({
		imperial: {
			temp,
			windSpeed,
			windGust,
			windChill:
				temp < 50 && windSpeed > 3
					? Math.round(
							35.74 +
								0.6215 * temp -
								35.75 * Math.pow(windSpeed, 0.16) +
								0.4275 * temp * Math.pow(windSpeed, 0.16)
						)
					: undefined,
			heatIndex:
				temp >= 80
					? Math.round(
							-42.379 +
								2.04901523 * temp +
								10.14333127 * humidity -
								0.22475541 * temp * humidity -
								6.83783e-3 * temp * temp -
								5.481717e-2 * humidity * humidity +
								1.22874e-3 * temp * temp * humidity +
								8.5282e-4 * temp * humidity * humidity -
								1.99e-6 * temp * temp * humidity * humidity
						)
					: undefined,
			precipRate,
			pressure,
			dewpt: dewPt,
			elev: 820
		},
		humidity,
		uv,
		winddir: 225,
		stationID: 'DEV-MODE',
		neighborhood: 'Test Panel',
		lat: liveData?.lat ?? 38.9,
		lon: liveData?.lon ?? -92.3,
		obsTimeLocal: new Date().toISOString()
	});

	/* when useLiveHour is false, patch the hour into inferTheme via a proxy obsTimeLocal */
	/* The hourly theme is derived from new Date() inside inferTheme() — to override it we patch
     the component clock. Since we can't easily intercept that, we use a small workaround:
     we temporarily override Date for the render by changing obsTimeLocal. The inferTheme() in
     WeatherDisplay uses new Date().getHours() directly, so for hour-testing the user just
     changes their system clock or we add an optional hourOverride prop. For now, the panel
     shows exactly what theme would be active at the slider values with live time. */

	const displayData = $derived<WeatherData>(useLive ? (liveData ?? {}) : syntheticData);

	/* infer the theme locally for the label display */
	function inferThemeLocal(w: WeatherData): string {
		const imp = w.imperial || {};
		const rate = imp.precipRate,
			t = imp.temp,
			gust = imp.windGust;
		const h = timeOverride ?? new Date().getHours() + new Date().getMinutes() / 60;
		if (rate != null && rate > 0) {
			if (t != null && t <= 33) return 'snow';
			if ((gust != null && gust > 20) || rate > 0.08) return 'storm';
			return 'rain';
		}
		const lat = w.lat,
			lon = w.lon;
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

	const activeTheme = $derived(inferThemeLocal(displayData));

	let panelOpen = $state(true);
	let arcOpen = $state(false);

	// Time playback
	let playing = $state(false);
	let playSpeed = $state(30); // simulated minutes per real second
	let _playFrac = 0; // precise accumulator (fractional minutes, non-reactive)
	let _rafId: number | null = null;
	let _lastRafTime: number | null = null;

	function tick(now: number) {
		if (!playing) return;
		if (_lastRafTime !== null) {
			const dt = (now - _lastRafTime) / 1000;
			_playFrac = (((_playFrac + playSpeed * dt) % 1440) + 1440) % 1440;
			const h = Math.floor(_playFrac / 60);
			const m = Math.floor(_playFrac % 60);
			manualTime = `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
		}
		_lastRafTime = now;
		_rafId = requestAnimationFrame(tick);
	}

	function togglePlay() {
		if (playing) {
			playing = false;
			if (_rafId !== null) {
				cancelAnimationFrame(_rafId);
				_rafId = null;
			}
			_lastRafTime = null;
		} else {
			useLiveTime = false;
			const [hStr, mStr] = manualTime.split(':');
			_playFrac = parseInt(hStr) * 60 + parseInt(mStr);
			playing = true;
			_lastRafTime = null;
			_rafId = requestAnimationFrame(tick);
		}
	}

	// Arc config for celestial body positioning
	let arcConfig = $state<ArcConfig>({ ...ARC_DEFAULTS });
	let dragging: 'rise' | 'peak' | 'set' | null = $state(null);
	let arcSvg: SVGSVGElement | undefined = $state(undefined);

	const arcPoints = $derived(
		Array.from({ length: 41 }, (_, i) => {
			const t = i / 40;
			const { xRight, xLeft, yHorizon, yPeak, arcExp } = arcConfig;
			const x = xRight - (xRight - xLeft) * t;
			const y = yHorizon - (yHorizon - yPeak) * Math.pow(Math.sin(Math.PI * t), arcExp);
			return `${x.toFixed(2)},${y.toFixed(2)}`;
		}).join(' ')
	);

	function svgPt(e: PointerEvent): { x: number; y: number } | null {
		if (!arcSvg) return null;
		const r = arcSvg.getBoundingClientRect();
		return {
			x: ((e.clientX - r.left) / r.width) * 100,
			y: ((e.clientY - r.top) / r.height) * 130
		};
	}

	function onArcMove(e: PointerEvent) {
		if (!dragging) return;
		const p = svgPt(e);
		if (!p) return;
		if (dragging === 'rise') {
			arcConfig.xRight = Math.round(Math.max(55, Math.min(100, p.x)));
			arcConfig.yHorizon = Math.round(Math.max(80, Math.min(145, p.y)));
		} else if (dragging === 'set') {
			arcConfig.xLeft = Math.round(Math.max(0, Math.min(45, p.x)));
			arcConfig.yHorizon = Math.round(Math.max(80, Math.min(145, p.y)));
		} else if (dragging === 'peak') {
			arcConfig.yPeak = Math.round(Math.max(5, Math.min(90, p.y)));
		}
	}

	// Arc save
	let saveStatus = $state<'idle' | 'saving' | 'saved' | 'error'>('idle');
	async function saveArc() {
		saveStatus = 'saving';
		try {
			const r = await fetch('/api/arc', {
				method: 'POST',
				headers: { 'Content-Type': 'application/json' },
				body: JSON.stringify(arcConfig)
			});
			saveStatus = r.ok ? 'saved' : 'error';
		} catch {
			saveStatus = 'error';
		}
		setTimeout(() => (saveStatus = 'idle'), 2500);
	}

	onMount(() => {
		fetchLive();
		// Load saved arc from config.json
		fetch('/api/arc')
			.then((r) => r.json())
			.then((saved) => {
				if (saved && typeof saved === 'object') {
					arcConfig = { ...ARC_DEFAULTS, ...saved };
				}
			})
			.catch(() => {});
		const t = setInterval(fetchLive, 60_000);
		return () => {
			clearInterval(t);
			if (_rafId !== null) cancelAnimationFrame(_rafId);
		};
	});
</script>

<svelte:head><title>Weather Dev</title></svelte:head>

<!-- Full-screen weather -->
<WeatherDisplay data={displayData} {timeOverride} {arcConfig} />

<!-- Floating control panel -->
<div class="panel" class:closed={!panelOpen}>
	<div class="panel-header">
		<span class="panel-title">⚙ Weather Tester</span>
		<button class="toggle-btn" onclick={() => (panelOpen = !panelOpen)}>
			{panelOpen ? '−' : '+'}
		</button>
	</div>

	{#if panelOpen}
		<div class="panel-body">
			<!-- Live toggle -->
			<label class="row">
				<span>Use live weather</span>
				<input type="checkbox" bind:checked={useLive} />
			</label>

			{#if !useLive}
				<div class="divider"></div>

				<!-- Hour override -->
				<label class="row">
					<span>Live time</span>
					<input type="checkbox" bind:checked={useLiveTime} />
				</label>
				{#if !useLiveTime}
					<label class="slider-row">
						<span>Time: {manualTime}</span>
						<div class="time-controls">
							<input
								type="time"
								bind:value={manualTime}
								oninput={() => {
									if (playing) {
										const [h, m] = manualTime.split(':');
										_playFrac = +h * 60 + +m;
									}
								}}
							/>
							<button
								class="play-btn"
								class:active={playing}
								onclick={togglePlay}
								title={playing ? 'Pause' : 'Play'}
							>
								{playing ? '⏸' : '▶'}
							</button>
						</div>
					</label>
					<label class="slider-row">
						<span>Speed: {playSpeed} min/s — full day in {Math.round(1440 / playSpeed)}s</span>
						<input type="range" min="1" max="120" step="1" bind:value={playSpeed} />
					</label>
				{/if}

				<div class="divider"></div>

				<label class="slider-row">
					<span>Temp: {temp}°F</span>
					<input type="range" min="-10" max="115" step="1" bind:value={temp} />
				</label>

				<label class="slider-row">
					<span>Precip: {precipRate.toFixed(2)} in/hr</span>
					<input type="range" min="0" max="0.5" step="0.01" bind:value={precipRate} />
				</label>

				<label class="slider-row">
					<span>Wind: {windSpeed} mph</span>
					<input type="range" min="0" max="80" step="1" bind:value={windSpeed} />
				</label>

				<label class="slider-row">
					<span>Gust: {windGust} mph</span>
					<input type="range" min="0" max="80" step="1" bind:value={windGust} />
				</label>

				<label class="slider-row">
					<span>Humidity: {humidity}%</span>
					<input type="range" min="0" max="100" step="1" bind:value={humidity} />
				</label>

				<label class="slider-row">
					<span>Dew Pt: {dewPt}°F</span>
					<input type="range" min="-20" max="80" step="1" bind:value={dewPt} />
				</label>

				<label class="slider-row">
					<span>Pressure: {pressure.toFixed(2)}"</span>
					<input type="range" min="28.0" max="31.5" step="0.01" bind:value={pressure} />
				</label>

				<label class="slider-row">
					<span>UV: {uv}</span>
					<input type="range" min="0" max="11" step="1" bind:value={uv} />
				</label>

				<!-- Quick presets -->
				<div class="divider"></div>
				<div class="presets-label">Quick presets</div>
				<div class="presets">
					{#each [{ label: 'Night', fn: () => {
								precipRate = 0;
								temp = 58;
								windSpeed = 4;
								windGust = 6;
								useLiveTime = false;
								manualTime = '02:00';
							} }, { label: 'Day', fn: () => {
								precipRate = 0;
								temp = 72;
								windSpeed = 8;
								windGust = 12;
								useLiveTime = false;
								manualTime = '12:00';
							} }, { label: 'Rise', fn: () => {
								precipRate = 0;
								temp = 62;
								windSpeed = 3;
								windGust = 5;
								useLiveTime = false;
								manualTime = '06:30';
							} }, { label: 'Golden', fn: () => {
								precipRate = 0;
								temp = 68;
								windSpeed = 5;
								windGust = 8;
								useLiveTime = false;
								manualTime = '18:00';
							} }, { label: 'Rain', fn: () => {
								precipRate = 0.04;
								temp = 55;
								windSpeed = 10;
								windGust = 18;
								useLiveTime = false;
								manualTime = '14:00';
							} }, { label: 'Storm', fn: () => {
								precipRate = 0.12;
								temp = 60;
								windSpeed = 25;
								windGust = 38;
								useLiveTime = false;
								manualTime = '14:00';
							} }, { label: 'Snow', fn: () => {
								precipRate = 0.05;
								temp = 28;
								windSpeed = 8;
								windGust = 14;
								useLiveTime = false;
								manualTime = '14:00';
							} }, { label: 'Sunset', fn: () => {
								precipRate = 0;
								temp = 66;
								windSpeed = 4;
								windGust = 7;
								useLiveTime = false;
								manualTime = '19:30';
							} }] as p}
						<button class="preset-btn" onclick={p.fn}>{p.label}</button>
					{/each}
				</div>
			{/if}

			<div class="divider"></div>

			<!-- Arc Editor -->
			<div class="arc-section">
				<button class="arc-header" onclick={() => (arcOpen = !arcOpen)}>
					<span>Arc Editor</span>
					<span class="arc-toggle">{arcOpen ? '−' : '+'}</span>
				</button>
				{#if arcOpen}
					<div class="arc-body">
						<!-- svelte-ignore a11y_no_static_element_interactions -->
						<svg
							bind:this={arcSvg}
							viewBox="0 0 100 130"
							class="arc-svg"
							onpointermove={onArcMove}
							onpointerup={() => {
								dragging = null;
							}}
							onpointerleave={() => {
								dragging = null;
							}}
						>
							<!-- visible screen rect -->
							<rect x="0" y="0" width="100" height="100" fill="rgba(120,184,245,0.06)" />
							<!-- off-screen rect -->
							<rect x="0" y="100" width="100" height="30" fill="rgba(0,0,0,0.30)" />
							<!-- horizon line -->
							<line
								x1="0"
								y1="100"
								x2="100"
								y2="100"
								stroke="rgba(255,255,255,0.25)"
								stroke-dasharray="3 2"
								stroke-width="0.5"
							/>
							<text x="1" y="98" font-size="4" fill="rgba(255,255,255,0.28)">screen edge</text>
							<!-- arc curve -->
							<polyline
								points={arcPoints}
								fill="none"
								stroke="rgba(255,200,80,0.75)"
								stroke-width="1.2"
								stroke-linecap="round"
								stroke-linejoin="round"
							/>
							<!-- Rise handle (right = east) -->
							<!-- svelte-ignore a11y_no_static_element_interactions -->
							<circle
								cx={arcConfig.xRight}
								cy={arcConfig.yHorizon}
								r="4"
								fill="rgba(255,160,40,0.9)"
								stroke="white"
								stroke-width="0.8"
								style="cursor:grab;touch-action:none"
								onpointerdown={(e) => {
									arcSvg?.setPointerCapture(e.pointerId);
									dragging = 'rise';
								}}
							/>
							<text
								x={arcConfig.xRight - 10}
								y={arcConfig.yHorizon - 5}
								font-size="4"
								fill="rgba(255,210,100,0.85)"
								pointer-events="none">Rise</text
							>
							<!-- Set handle (left = west) -->
							<!-- svelte-ignore a11y_no_static_element_interactions -->
							<circle
								cx={arcConfig.xLeft}
								cy={arcConfig.yHorizon}
								r="4"
								fill="rgba(255,120,40,0.9)"
								stroke="white"
								stroke-width="0.8"
								style="cursor:grab;touch-action:none"
								onpointerdown={(e) => {
									arcSvg?.setPointerCapture(e.pointerId);
									dragging = 'set';
								}}
							/>
							<text
								x={arcConfig.xLeft + 2}
								y={arcConfig.yHorizon - 5}
								font-size="4"
								fill="rgba(255,180,80,0.85)"
								pointer-events="none">Set</text
							>
							<!-- Peak handle -->
							<!-- svelte-ignore a11y_no_static_element_interactions -->
							<circle
								cx={(arcConfig.xRight + arcConfig.xLeft) / 2}
								cy={arcConfig.yPeak}
								r="4"
								fill="rgba(255,240,100,0.9)"
								stroke="white"
								stroke-width="0.8"
								style="cursor:ns-resize;touch-action:none"
								onpointerdown={(e) => {
									arcSvg?.setPointerCapture(e.pointerId);
									dragging = 'peak';
								}}
							/>
							<text
								x={(arcConfig.xRight + arcConfig.xLeft) / 2 + 2}
								y={arcConfig.yPeak - 4}
								font-size="4"
								fill="rgba(255,245,150,0.85)"
								pointer-events="none">Peak</text
							>
						</svg>
						<label class="slider-row">
							<span>Exponent: {arcConfig.arcExp.toFixed(2)} (flat ← → pointy)</span>
							<input type="range" min="0.20" max="2.0" step="0.05" bind:value={arcConfig.arcExp} />
						</label>
						<div class="arc-vals">
							xR={arcConfig.xRight} xL={arcConfig.xLeft} yH={arcConfig.yHorizon} yP={arcConfig.yPeak}
						</div>
						<div class="arc-actions">
							<button
								class="preset-btn"
								onclick={() => {
									arcConfig = { ...ARC_DEFAULTS };
								}}>Reset defaults</button
							>
							<button
								class="save-arc-btn"
								class:saving={saveStatus === 'saving'}
								class:saved={saveStatus === 'saved'}
								class:error={saveStatus === 'error'}
								onclick={saveArc}
								disabled={saveStatus === 'saving'}
							>
								{saveStatus === 'saving'
									? 'Saving…'
									: saveStatus === 'saved'
										? '✓ Saved!'
										: saveStatus === 'error'
											? '✗ Error'
											: '💾 Save Arc'}
							</button>
						</div>
					</div>
				{/if}
			</div>

			<div class="divider"></div>
			<div class="theme-badge">Theme: <strong>{activeTheme}</strong></div>
			<a class="back-link" href="/weather">← Live page</a>
		</div>
	{/if}
</div>

<style>
	:global(body) {
		margin: 0;
		overflow: hidden;
	}

	.panel {
		position: fixed;
		top: 20px;
		left: 20px;
		z-index: 100;
		width: 300px;
		background: rgba(8, 10, 20, 0.82);
		backdrop-filter: blur(18px);
		border: 1px solid rgba(255, 255, 255, 0.1);
		border-radius: 14px;
		color: #dde8f8;
		font-family: 'Outfit', system-ui, sans-serif;
		font-size: 13px;
		box-shadow: 0 8px 40px rgba(0, 0, 0, 0.55);
		transition: all 0.25s ease;
		max-height: calc(100vh - 40px);
		display: flex;
		flex-direction: column;
	}
	.panel.closed {
		width: auto;
		border-radius: 10px;
	}

	.panel-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 10px 14px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.07);
		flex-shrink: 0;
	}
	.panel-title {
		font-weight: 500;
		letter-spacing: 0.04em;
		font-size: 13px;
	}
	.toggle-btn {
		background: rgba(255, 255, 255, 0.08);
		border: none;
		color: #dde8f8;
		width: 24px;
		height: 24px;
		border-radius: 6px;
		cursor: pointer;
		font-size: 16px;
		line-height: 1;
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.toggle-btn:hover {
		background: rgba(255, 255, 255, 0.16);
	}

	.panel-body {
		padding: 10px 14px 12px;
		display: flex;
		flex-direction: column;
		gap: 6px;
		overflow-y: auto;
		overscroll-behavior: contain;
		scrollbar-width: thin;
		scrollbar-color: rgba(120, 184, 245, 0.25) transparent;
	}

	.row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		gap: 8px;
		cursor: pointer;
	}
	.row input[type='checkbox'] {
		accent-color: #7ab8f5;
		width: 16px;
		height: 16px;
		cursor: pointer;
	}

	.slider-row {
		display: flex;
		flex-direction: column;
		gap: 3px;
	}
	.slider-row span {
		font-size: 11px;
		color: rgba(200, 220, 255, 0.6);
		letter-spacing: 0.04em;
	}
	.slider-row input[type='range'] {
		width: 100%;
		accent-color: #7ab8f5;
		height: 4px;
		cursor: pointer;
	}
	.slider-row input[type='time'] {
		width: 100%;
		background: rgba(255, 255, 255, 0.07);
		border: 1px solid rgba(255, 255, 255, 0.12);
		border-radius: 6px;
		color: #c8daf4;
		font-family: inherit;
		font-size: 13px;
		padding: 4px 8px;
		cursor: pointer;
		outline: none;
	}
	.slider-row input[type='time']:focus {
		border-color: rgba(120, 184, 245, 0.5);
	}

	.time-controls {
		display: flex;
		gap: 6px;
		align-items: center;
	}
	.time-controls input[type='time'] {
		flex: 1;
	}
	.play-btn {
		background: rgba(255, 255, 255, 0.08);
		border: 1px solid rgba(255, 255, 255, 0.12);
		color: #c8daf4;
		font-size: 13px;
		width: 30px;
		height: 28px;
		border-radius: 6px;
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 0.15s;
		flex-shrink: 0;
	}
	.play-btn:hover {
		background: rgba(255, 255, 255, 0.16);
	}
	.play-btn.active {
		background: rgba(120, 184, 245, 0.22);
		border-color: rgba(120, 184, 245, 0.4);
		color: #a8d4ff;
	}

	.divider {
		height: 1px;
		background: rgba(255, 255, 255, 0.07);
		margin: 2px 0;
	}

	.presets-label {
		font-size: 10px;
		letter-spacing: 0.2em;
		text-transform: uppercase;
		color: rgba(200, 220, 255, 0.38);
		margin-bottom: 2px;
	}
	.presets {
		display: flex;
		flex-wrap: wrap;
		gap: 5px;
	}
	.preset-btn {
		background: rgba(255, 255, 255, 0.07);
		border: 1px solid rgba(255, 255, 255, 0.1);
		color: #c8daf4;
		font-size: 11px;
		padding: 3px 9px;
		border-radius: 6px;
		cursor: pointer;
		font-family: inherit;
		transition: background 0.15s;
	}
	.preset-btn:hover {
		background: rgba(255, 255, 255, 0.15);
	}

	.theme-badge {
		font-size: 11px;
		color: rgba(200, 220, 255, 0.5);
		letter-spacing: 0.06em;
	}
	.theme-badge strong {
		color: #a8d0f8;
	}

	.back-link {
		display: inline-block;
		margin-top: 2px;
		font-size: 11px;
		color: rgba(160, 200, 255, 0.5);
		text-decoration: none;
		letter-spacing: 0.04em;
	}
	.back-link:hover {
		color: rgba(160, 200, 255, 0.9);
	}

	/* Arc editor */
	.arc-section {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}
	.arc-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		background: none;
		border: none;
		color: #c8daf4;
		font-family: inherit;
		font-size: 12px;
		font-weight: 500;
		cursor: pointer;
		padding: 2px 0;
		width: 100%;
	}
	.arc-header:hover {
		color: #e8f0ff;
	}
	.arc-toggle {
		font-size: 16px;
		line-height: 1;
	}
	.arc-body {
		display: flex;
		flex-direction: column;
		gap: 5px;
	}
	.arc-svg {
		width: 100%;
		aspect-ratio: 100 / 130;
		border: 1px solid rgba(255, 255, 255, 0.1);
		border-radius: 4px;
		background: rgba(0, 0, 0, 0.15);
		touch-action: none;
		user-select: none;
	}
	.arc-vals {
		font-size: 10px;
		color: rgba(200, 220, 255, 0.38);
		font-variant-numeric: tabular-nums;
		letter-spacing: 0.04em;
	}
	.arc-actions {
		display: flex;
		gap: 6px;
		align-items: center;
		flex-wrap: wrap;
	}
	.save-arc-btn {
		background: rgba(100, 180, 120, 0.15);
		border: 1px solid rgba(100, 200, 130, 0.28);
		color: #90e0a8;
		font-size: 11px;
		padding: 3px 10px;
		border-radius: 6px;
		cursor: pointer;
		font-family: inherit;
		transition:
			background 0.15s,
			color 0.15s;
		flex: 1;
	}
	.save-arc-btn:hover:not(:disabled) {
		background: rgba(100, 180, 120, 0.28);
	}
	.save-arc-btn:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.save-arc-btn.saving {
		border-color: rgba(150, 200, 255, 0.3);
		color: #90c8f8;
	}
	.save-arc-btn.saved {
		background: rgba(80, 160, 100, 0.3);
		border-color: rgba(100, 200, 130, 0.55);
		color: #a0f0b8;
	}
	.save-arc-btn.error {
		background: rgba(180, 60, 60, 0.2);
		border-color: rgba(220, 80, 80, 0.4);
		color: #f09090;
	}
</style>
