import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getConfig, saveConfig } from '$lib/server/config';

/** GET /api/arc — return current arc config (merged with built-in defaults) */
export const GET: RequestHandler = () => {
    const cfg = getConfig();
    return json(cfg.arc ?? {});
};

/** POST /api/arc — save arc overrides to config.json */
export const POST: RequestHandler = async ({ request }) => {
    let body: Record<string, unknown>;
    try {
        body = await request.json();
    } catch {
        throw error(400, 'Invalid JSON');
    }

    const allowed = ['xRight', 'xLeft', 'yHorizon', 'yPeak', 'arcExp'];
    const arc: Record<string, number> = {};
    for (const key of allowed) {
        if (typeof body[key] === 'number' && isFinite(body[key] as number)) {
            arc[key] = body[key] as number;
        }
    }

    saveConfig({ arc });
    return json({ ok: true, arc });
};
