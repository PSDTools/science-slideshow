<script lang="ts">
	import { onMount } from 'svelte';
	import WeatherDisplay, { ARC_DEFAULTS } from '$lib/WeatherDisplay.svelte';
	import type { WeatherData, ArcConfig } from '$lib/WeatherDisplay.svelte';

	interface SlideshowConfig {
		weather: { station_id: string; enabled: boolean };
		slideshow: { image_duration_seconds: number; weather_duration_seconds: number };
		arc?: Partial<ArcConfig>;
	}

	interface DriveImage {
		id: string;
		name: string;
		url: string;
	}
	type SlideType =
		| { type: 'weather' }
		| { type: 'radar' }
		| { type: 'image'; url: string; name: string; duration?: number };

	/**
	 * Parse an optional duration from the filename.
	 * Supports:  photo_30s.jpg  (30 seconds)
	 *            photo_2m.jpg   (120 seconds)
	 *            photo_1m30s.jpg (90 seconds)
	 * The pattern can appear anywhere before the extension.
	 */
	function parseDuration(name: string): number | null {
		// Strip extension
		const base = name.replace(/\.[^.]+$/, '');
		// Match _1m30s, _2m, _45s — number + unit, optional combined
		const full = base.match(/_(\d+)m(\d+)s/i);
		if (full) return parseInt(full[1]) * 60 + parseInt(full[2]);
		const mins = base.match(/_(\d+)m(?!\d)/i);
		if (mins) return parseInt(mins[1]) * 60;
		const secs = base.match(/_(\d+)s(?!\w)/i);
		if (secs) return parseInt(secs[1]);
		return null;
	}

	let slides = $state<SlideType[]>([]);
	let current = $state(0);
	let weatherData = $state<WeatherData | null>(null);
	let debug = $state(false);
	let countdown = $state(0);
	let entering = $state(false);
	let arcConfig = $state({ ...ARC_DEFAULTS });

	// Trigger weather entrance animations whenever the weather slide becomes active
	$effect(() => {
		if (slides[current]?.type === 'weather') {
			entering = true;
			const t = setTimeout(() => {
				entering = false;
			}, 2200);
			return () => {
				clearTimeout(t);
				entering = false;
			};
		} else {
			entering = false;
		}
	});
	let cfg = $state<SlideshowConfig>({
		weather: { station_id: '', enabled: false },
		slideshow: { image_duration_seconds: 10, weather_duration_seconds: 15 }
	});

	async function loadConfig() {
		try {
			const r = await fetch('/api/config');
			cfg = await r.json();
			arcConfig = { ...ARC_DEFAULTS, ...(cfg.arc ?? {}) };
		} catch {}
	}

	async function loadWeather(): Promise<WeatherData | null> {
		if (!cfg.weather.enabled) return null;
		try {
			const r = await fetch('/api/weather');
			if (!r.ok) return null;
			return await r.json();
		} catch {
			return null;
		}
	}

	async function loadImages(): Promise<DriveImage[]> {
		try {
			const r = await fetch('/api/images');
			const d = await r.json();
			return d.images ?? [];
		} catch {
			return [];
		}
	}

	function buildSlides(images: DriveImage[], hasWeather: boolean): SlideType[] {
		const s: SlideType[] = [];
		if (hasWeather) {
			s.push({ type: 'weather' });
			s.push({ type: 'radar' });
		}
		for (const img of images) {
			const duration = parseDuration(img.name) ?? undefined;
			s.push({ type: 'image', url: img.url, name: img.name, duration });
		}
		return s;
	}

	onMount(() => {
		let ticker: ReturnType<typeof setInterval>;
		let weatherRefresh: ReturnType<typeof setInterval>;

		async function init() {
			await loadConfig();
			weatherData = await loadWeather();
			const images = await loadImages();
			slides = buildSlides(images, !!weatherData);
			current = 0;
			countdown = currentDuration();

			ticker = setInterval(() => {
				countdown--;
				if (countdown <= 0) {
					current = (current + 1) % (slides.length || 1);
					countdown = currentDuration();
					if (slides[current]?.type === 'weather') {
						loadWeather().then((d) => {
							if (d) weatherData = d;
						});
					}
				}
			}, 1000);

			if (cfg.weather.enabled) {
				weatherRefresh = setInterval(
					async () => {
						const d = await loadWeather();
						if (d) weatherData = d;
					},
					10 * 60 * 1000
				);
			}
		}

		function currentDuration() {
			if (!slides.length) return 10;
			const s = slides[current];
			if (s?.type === 'weather' || s?.type === 'radar')
				return cfg.slideshow.weather_duration_seconds ?? 15;
			// Per-file override wins over config default
			return s?.duration ?? cfg.slideshow.image_duration_seconds ?? 10;
		}

		function onKey(e: KeyboardEvent) {
			if (e.key === 'd' || e.key === 'D') debug = !debug;
		}

		window.addEventListener('keydown', onKey);
		init();

		return () => {
			clearInterval(ticker);
			clearInterval(weatherRefresh);
			window.removeEventListener('keydown', onKey);
		};
	});

	const currentSlide = $derived(slides[current] ?? null);

	function getRadarUrl() {
		// Cache bust the radar loop every 5 minutes (300000ms)
		return `https://radar.weather.gov/ridge/standard/KLSX_loop.gif?t=${Math.floor(Date.now() / 300000)}`;
	}
</script>

<svelte:head>
	<title>Slideshow</title>
</svelte:head>

<div class="root">
	{#each slides as slide, i}
		<div class="slide" class:active={i === current}>
			{#if Math.abs(i - current) <= 1 || (i === 0 && current === slides.length - 1) || (i === slides.length - 1 && current === 0)}
				{#if slide.type === 'image'}
					<img src={slide.url} alt="" />
				{:else if slide.type === 'radar'}
					<!-- svelte-ignore a11y_missing_attribute -->
					<img src={getRadarUrl()} />
				{:else}
					<WeatherDisplay data={weatherData} {entering} {arcConfig} />
				{/if}
			{/if}
		</div>
	{/each}

	{#if slides.length === 0}
		<div class="loading">Loading…</div>
	{/if}

	{#if debug}
		<div class="debug">
			Slide: {current + 1}/{slides.length}<br />
			Next in: {countdown}s<br />
			Type: {currentSlide?.type ?? 'none'}
			{#if currentSlide?.type === 'image'}
				<br />File: {currentSlide.name}
				{#if currentSlide.duration}<br />⏱ custom: {currentSlide.duration}s{/if}
			{/if}
		</div>
	{/if}
</div>

<style>
	:global(html, body) {
		margin: 0;
		padding: 0;
		background: #000;
		width: 100vw;
		height: 100vh;
		overflow: hidden;
		cursor: none !important;
	}

	.root {
		width: 100vw;
		height: 100vh;
		position: relative;
		background: #000;
	}

	.slide {
		position: absolute;
		inset: 0;
		opacity: 0;
		pointer-events: none;
		overflow: hidden;
	}

	.slide.active {
		opacity: 1;
		pointer-events: auto;
	}

	.slide img {
		width: 100%;
		height: 100%;
		object-fit: contain;
	}

	.loading {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		color: rgba(255, 255, 255, 0.3);
		font-family: system-ui, sans-serif;
		font-size: 18px;
	}

	.debug {
		position: fixed;
		top: 10px;
		left: 10px;
		background: rgba(0, 0, 0, 0.85);
		color: #0f0;
		padding: 12px 16px;
		font-family: monospace;
		font-size: 13px;
		border-radius: 8px;
		z-index: 9999;
		line-height: 1.6;
	}
</style>
