<script lang="ts">
	import { onMount } from 'svelte';
	import WeatherDisplay, { ARC_DEFAULTS } from '$lib/WeatherDisplay.svelte';
	import type { WeatherData, ArcConfig } from '$lib/WeatherDisplay.svelte';

	interface SlideshowConfig {
		weather: { station_id: string; enabled: boolean };
		slideshow: {
			image_duration_seconds: number;
			weather_duration_seconds: number;
			weather_every_n_slides?: number;
		};
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

	let images = $state<SlideType[]>([]);
	let currentSlideType = $state<'weather' | 'radar' | 'image'>('weather');
	let imageIndex = $state(0);
	let imagesSinceWeather = $state(0);
	let weatherData = $state<WeatherData | null>(null);
	let debug = $state(false);
	let countdown = $state(0);
	let radarUrl = $state('https://radar.weather.gov/ridge/standard/KLSX_loop.gif');
	let arcConfig = $state({ ...ARC_DEFAULTS });
	let lastConfigHash = $state('');
	let cfg = $state<SlideshowConfig>({
		weather: { station_id: '', enabled: false },
		slideshow: { image_duration_seconds: 10, weather_duration_seconds: 15 }
	});

	async function loadConfig(): Promise<boolean> {
		try {
			const r = await fetch(`/api/config.json?t=${Date.now()}`);
			const newCfg = await r.json();
			const hash = JSON.stringify(newCfg);
			if (hash === lastConfigHash) return false;
			lastConfigHash = hash;
			cfg = newCfg;
			arcConfig = { ...ARC_DEFAULTS, ...(cfg.arc ?? {}) };
			return true;
		} catch {
			return false;
		}
	}

	async function loadWeather(): Promise<WeatherData | null> {
		if (!cfg.weather.enabled) return null;
		try {
			const r = await fetch(`/api/weather.json?t=${Date.now()}`);
			if (!r.ok) return null;
			return await r.json();
		} catch {
			return null;
		}
	}

	async function loadImages(): Promise<DriveImage[]> {
		try {
			const r = await fetch(`/api/images.json?t=${Date.now()}`);
			const d = await r.json();
			return d.images ?? [];
		} catch {
			return [];
		}
	}

	function buildImageSlides(driveImages: DriveImage[]): SlideType[] {
		return driveImages.map((img) => {
			const duration = parseDuration(img.name) ?? undefined;
			return { type: 'image' as const, url: img.url, name: img.name, duration };
		});
	}

	function advanceSlide() {
		const hasWeather = !!weatherData;
		const every = cfg.slideshow.weather_every_n_slides ?? 3;

		if (!hasWeather || images.length === 0) {
			// No weather or no images — just cycle images
			if (images.length > 0) {
				imageIndex = (imageIndex + 1) % images.length;
				currentSlideType = 'image';
			}
			return;
		}

		// State machine: weather → radar → N images → weather → ...
		if (currentSlideType === 'weather') {
			radarUrl = `https://radar.weather.gov/ridge/standard/KLSX_loop.gif?t=${Math.floor(Date.now() / 300000)}`;
			currentSlideType = 'radar';
		} else if (currentSlideType === 'radar') {
			currentSlideType = 'image';
			imagesSinceWeather = 1;
			imageIndex = imageIndex % images.length;
		} else {
			// Currently on an image
			if (imagesSinceWeather >= every) {
				// Shown enough images, back to weather
				currentSlideType = 'weather';
				imagesSinceWeather = 0;
				// Refresh weather data when entering weather slide
				loadWeather().then((d) => {
					if (d) weatherData = d;
				});
			} else {
				// Next image
				imageIndex = (imageIndex + 1) % images.length;
				imagesSinceWeather++;
			}
		}
	}

	onMount(() => {
		let ticker: ReturnType<typeof setInterval>;
		let weatherRefresh: ReturnType<typeof setInterval>;
		let configRefresh: ReturnType<typeof setInterval>;

		let pendingImages: SlideType[] | null = null;

		async function refreshSlides(immediate = false) {
			weatherData = await loadWeather();
			const driveImages = await loadImages();
			const newImages = buildImageSlides(driveImages);
			if (immediate || images.length === 0) {
				images = newImages;
				imageIndex = 0;
				imagesSinceWeather = 0;
				currentSlideType = weatherData ? 'weather' : 'image';
				countdown = currentDuration();
			} else {
				pendingImages = newImages;
			}
		}

		async function init() {
			await loadConfig();
			await refreshSlides(true);

			ticker = setInterval(() => {
				countdown--;
				// Preload next image when 3s away from transition
				if (countdown === 3 && currentSlideType !== 'weather') {
					const nextIdx = (imageIndex + (currentSlideType === 'image' ? 1 : 0)) % (images.length || 1);
					const next = images[nextIdx];
					if (next?.type === 'image') {
						const img = new Image();
						img.src = next.url;
					}
				}
				if (countdown <= 0) {
					// Apply queued image changes at weather transition
					if (pendingImages && (currentSlideType === 'weather' || currentSlideType === 'radar')) {
						images = pendingImages;
						pendingImages = null;
						imageIndex = 0;
					}
					advanceSlide();
					countdown = currentDuration();
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

			// Poll for config/image changes every 5 minutes
			configRefresh = setInterval(async () => {
				const changed = await loadConfig();
				if (changed) {
					console.log('[slideshow] Config changed, rebuilding slides');
					await refreshSlides();
				} else {
					const driveImages = await loadImages();
					const imageIds = driveImages.map((i) => i.id).join(',');
					const currentImageIds = images
						.filter((s): s is Extract<SlideType, { type: 'image' }> => s.type === 'image')
						.map((s) => s.url.replace('/image/', '').replace('.jpg', ''))
						.join(',');
					if (imageIds !== currentImageIds) {
						console.log('[slideshow] Images changed, rebuilding slides');
						await refreshSlides();
					}
				}
			}, 5 * 60 * 1000);
		}

		function currentDuration() {
			if (currentSlideType === 'weather' || currentSlideType === 'radar')
				return cfg.slideshow.weather_duration_seconds ?? 15;
			if (images.length === 0) return 10;
			const s = images[imageIndex] as Extract<SlideType, { type: 'image' }> | undefined;
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
			clearInterval(configRefresh);
			window.removeEventListener('keydown', onKey);
		};
	});

	const currentImageSlide = $derived(
		images[imageIndex] as Extract<SlideType, { type: 'image' }> | undefined
	);
</script>

<svelte:head>
	<title>Slideshow</title>
</svelte:head>

<div class="root">
	<div class="slide" class:active={currentSlideType === 'weather'}>
		<WeatherDisplay data={weatherData} {arcConfig} />
	</div>
	<div class="slide" class:active={currentSlideType === 'radar'}>
		<!-- svelte-ignore a11y_missing_attribute -->
		<img src={radarUrl} decoding="async" />
	</div>
	<div class="slide" class:active={currentSlideType === 'image'}>
		{#if currentImageSlide}
			<img src={currentImageSlide.url} alt="" decoding="async" />
		{/if}
	</div>

	{#if images.length === 0 && !weatherData}
		<div class="loading">Loading…</div>
	{/if}

	{#if debug}
		<div class="debug">
			Image: {imageIndex + 1}/{images.length} ({imagesSinceWeather}/{cfg.slideshow.weather_every_n_slides ?? 3})<br />
			Next in: {countdown}s<br />
			Type: {currentSlideType}
			{#if currentSlideType === 'image' && currentImageSlide}
				<br />File: {currentImageSlide.name}
				{#if currentImageSlide.duration}<br />⏱ custom: {currentImageSlide.duration}s{/if}
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
		display: none;
		pointer-events: none;
		overflow: hidden;
	}

	.slide.active {
		display: block;
		pointer-events: auto;
	}

	.slide img {
		width: 100%;
		height: 100%;
		object-fit: contain;
		image-rendering: pixelated;
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
