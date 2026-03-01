import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getConfig } from '$lib/server/config';
import { getCachedImages, isCacheStale, fetchPublicFolder } from '$lib/server/images';

export const GET: RequestHandler = async () => {
	const config = getConfig();
	const folderId = config.google_drive?.folder_id ?? '';

	if (isCacheStale()) {
		await fetchPublicFolder(folderId);
	}

	const { images, lastUpdate } = getCachedImages();
	return json({ images, count: images.length, last_updated: lastUpdate });
};
