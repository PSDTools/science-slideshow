const WEATHER_CACHE_DURATION_MS = 10 * 60 * 1000; // 10 minutes

let weatherCache: unknown = null;
let weatherCacheTime = 0;

/** Fetch current weather observation from Weather Underground PWS API. */
export async function fetchWeather(
	apiKey: string,
	stationId: string
): Promise<{ data: unknown; error?: string }> {
	// Return in-memory cache if fresh
	if (weatherCache && Date.now() - weatherCacheTime < WEATHER_CACHE_DURATION_MS) {
		return { data: weatherCache };
	}

	try {
		const url =
			`https://api.weather.com/v2/pws/observations/current` +
			`?stationId=${stationId}&format=json&units=e&apiKey=${apiKey}`;
		const res = await fetch(url, {
			headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
		});
		if (!res.ok) {
			return { data: null, error: `Weather API error: ${res.status}` };
		}
		const body = (await res.json()) as { observations?: unknown[] };
		const obs = body.observations;
		if (!obs?.length) {
			return { data: null, error: 'No observations returned' };
		}
		weatherCache = obs[0];
		weatherCacheTime = Date.now();
		return { data: weatherCache };
	} catch (e) {
		return { data: null, error: String(e) };
	}
}
