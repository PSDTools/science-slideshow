<script lang="ts">
	import { onMount } from 'svelte';
	import WeatherDisplay, { type WeatherData, ARC_DEFAULTS } from '$lib/WeatherDisplay.svelte';
	import type { ArcConfig } from '$lib/WeatherDisplay.svelte';

	let weatherData = $state<WeatherData | null>(null);
	let arcConfig = $state<ArcConfig>({ ...ARC_DEFAULTS });

	async function load() {
		try {
			const r = await fetch('/api/weather');
			weatherData = await r.json();
		} catch {
			weatherData = {};
		}
	}

	async function loadArc() {
		try {
			const saved = await (await fetch('/api/arc')).json();
			if (saved && typeof saved === 'object') {
				arcConfig = { ...ARC_DEFAULTS, ...saved };
			}
		} catch {}
	}

	onMount(() => {
		load();
		loadArc();
		// refresh every 10 minutes
		const t = setInterval(load, 10 * 60 * 1000);
		return () => clearInterval(t);
	});
</script>

<svelte:head><title>Weather</title></svelte:head>

{#if weatherData !== null}
	<WeatherDisplay data={weatherData} {arcConfig} />
{/if}
