/**
 * Compute today's sunrise and sunset as fractional local hours (e.g. 6.75 = 6:45 AM).
 * Uses the USNO/Almanac for Computers algorithm — accurate to ~1 minute.
 * Returns null for each if the sun doesn't rise/set (polar extremes).
 */
export function getSunTimes(lat: number, lon: number): { sunrise: number | null; sunset: number | null } {
    const toRad = Math.PI / 180;
    const toDeg = 180 / Math.PI;
    const now = new Date();
    const jan1 = new Date(now.getFullYear(), 0, 1);
    const N = Math.ceil((now.getTime() - jan1.getTime()) / 86400000);
    const lngHour = lon / 15;
    const localOffsetHours = -now.getTimezoneOffset() / 60;

    const calc = (isSunrise: boolean): number | null => {
        const t = N + ((isSunrise ? 6 : 18) - lngHour) / 24;
        const M = (0.9856 * t - 3.289 + 360) % 360;
        let L = (M + 1.916 * Math.sin(M * toRad) + 0.020 * Math.sin(2 * M * toRad) + 282.634 + 360) % 360;
        let RA = (toDeg * Math.atan(0.91764 * Math.tan(L * toRad)) + 360) % 360;
        RA = (RA + (Math.floor(L / 90) * 90 - Math.floor(RA / 90) * 90)) / 15;
        const sinDec = 0.39782 * Math.sin(L * toRad);
        const cosDec = Math.cos(Math.asin(sinDec));
        const cosH = (Math.cos(90.833 * toRad) - sinDec * Math.sin(lat * toRad)) / (cosDec * Math.cos(lat * toRad));
        if (cosH > 1 || cosH < -1) return null;
        const H = isSunrise ? (360 - toDeg * Math.acos(cosH)) / 15 : (toDeg * Math.acos(cosH)) / 15;
        const T = H + RA - 0.06571 * t - 6.622;
        return (((T - lngHour + localOffsetHours) % 24) + 24) % 24;
    };

    return { sunrise: calc(true), sunset: calc(false) };
}
