import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getCachedImages } from '$lib/server/images';

export const GET: RequestHandler = () => {
	const { images, lastUpdate } = getCachedImages();
	return json({ status: 'ok', images_cached: images.length, last_update: lastUpdate });
};
