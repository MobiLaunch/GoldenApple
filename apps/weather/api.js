// Weather data: Open-Meteo requests, WMO weather codes, units and the phrases the
// cards use, worded as Weather on the Mac words them.
//
// Open-Meteo returns times as local wall-clock strings for the location
// ("2026-09-28T14:00"), so everything here compares and formats those strings
// directly and never converts through the machine's own time zone.
.pragma library

var FORECAST = "https://api.open-meteo.com/v1/forecast";
var AIR = "https://air-quality-api.open-meteo.com/v1/air-quality";
var GEOCODE = "https://geocoding-api.open-meteo.com/v1/search";

function forecastUrl(lat, lon) {
    return FORECAST + "?latitude=" + lat + "&longitude=" + lon
        + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,is_day,weather_code,"
        + "cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,visibility,precipitation"
        + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day,uv_index,pressure_msl,wind_speed_10m"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,"
        + "precipitation_sum,sunrise,sunset,daylight_duration,uv_index_max"
        + "&timezone=auto&forecast_days=10&past_days=1";
}
function airUrl(lat, lon) {
    return AIR + "?latitude=" + lat + "&longitude=" + lon + "&current=us_aqi&hourly=us_aqi&timezone=auto&past_days=1&forecast_days=1";
}
function geocodeUrl(name) {
    return GEOCODE + "?count=8&language=en&format=json&name=" + encodeURIComponent(name);
}

// ------------------------------------------------------------------ conditions
// WMO code → [name, icon, sky]
var CODES = {
    0: ["Clear", "sun", "clear"], 1: ["Mostly Clear", "sun", "clear"],
    2: ["Partly Cloudy", "cloud-sun", "partly"], 3: ["Cloudy", "cloud", "cloudy"],
    45: ["Foggy", "fog", "fog"], 48: ["Foggy", "fog", "fog"],
    51: ["Drizzle", "cloud-drizzle", "rain"], 53: ["Drizzle", "cloud-drizzle", "rain"], 55: ["Drizzle", "cloud-drizzle", "rain"],
    56: ["Freezing Drizzle", "cloud-drizzle", "rain"], 57: ["Freezing Drizzle", "cloud-drizzle", "rain"],
    61: ["Light Rain", "cloud-rain", "rain"], 63: ["Rain", "cloud-rain", "rain"], 65: ["Heavy Rain", "cloud-heavyrain", "rain"],
    66: ["Freezing Rain", "cloud-rain", "rain"], 67: ["Freezing Rain", "cloud-heavyrain", "rain"],
    71: ["Light Snow", "cloud-snow", "snow"], 73: ["Snow", "cloud-snow", "snow"], 75: ["Heavy Snow", "cloud-snow", "snow"],
    77: ["Snow Grains", "cloud-snow", "snow"],
    80: ["Showers", "cloud-rain", "rain"], 81: ["Showers", "cloud-rain", "rain"], 82: ["Heavy Showers", "cloud-heavyrain", "rain"],
    85: ["Snow Showers", "cloud-snow", "snow"], 86: ["Snow Showers", "cloud-snow", "snow"],
    95: ["Thunderstorms", "cloud-bolt", "storm"], 96: ["Thunderstorms", "cloud-bolt", "storm"], 99: ["Thunderstorms", "cloud-bolt", "storm"],
};
function cond(code) { return CODES[code] || ["—", "cloud", "cloudy"]; }
function conditionName(code) { return cond(code)[0]; }
// Icons have night variants for the sunny ones.
function icon(code, isDay) {
    var i = cond(code)[1];
    if (isDay === 0 || isDay === false) {
        if (i === "sun") return "moon";
        if (i === "cloud-sun") return "cloud-moon";
    }
    return i;
}
function sky(code, isDay) {
    var s = cond(code)[2];
    return (isDay === 0 || isDay === false) && s !== "storm" ? s + "-night" : s;
}

// ------------------------------------------------------------------ units
// Open-Meteo is asked for metric; imperial is converted here.
function temp(c, imperial) { return c === null || c === undefined ? "--" : Math.round(imperial ? c * 9 / 5 + 32 : c) + "°"; }
function tempValue(c, imperial) { return imperial ? c * 9 / 5 + 32 : c; }
function speed(kmh, imperial) { return Math.round(imperial ? kmh / 1.609344 : kmh); }
function speedUnit(imperial) { return imperial ? "mph" : "km/h"; }
function distance(m, imperial) {
    var v = imperial ? m / 1609.344 : m / 1000;
    return (v >= 10 ? Math.round(v) : Math.round(v * 10) / 10) + (imperial ? " mi" : " km");
}
function rain(mm, imperial) {
    if (imperial) {
        var inch = mm / 25.4;
        if (inch < 0.005) return "0″";
        var t = inch >= 1 ? inch.toFixed(1) : inch.toFixed(2).replace(/^0/, "");
        return t.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "") + "″";
    }
    return (mm >= 10 ? Math.round(mm) : Math.round(mm * 10) / 10) + " mm";
}
function pressure(hpa, imperial) { return imperial ? (hpa / 33.8639).toFixed(2) : Math.round(hpa).toString(); }
function pressureUnit(imperial) { return imperial ? "inHg" : "hPa"; }
var COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"];
function compass(deg) { return COMPASS[Math.round(((deg % 360) + 360) % 360 / 22.5) % 16]; }

// ------------------------------------------------------------------ time
// "2026-09-28T14:05" → minutes since midnight / hour / day of week, all local to the place.
function minutes(s) { return Number(s.substr(11, 2)) * 60 + Number(s.substr(14, 2)); }
function hourOf(s) { return Number(s.substr(11, 2)); }
function dateOf(s) { return s.substr(0, 10); }
function weekday(dateStr) {
    var p = dateStr.split("-");
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(Date.UTC(+p[0], +p[1] - 1, +p[2])).getUTCDay()];
}
// 12-hour clock where the locale uses it: [number part, "AM"/"PM"] so the
// suffix can be set smaller, as Weather does ("7:43PM", "10AM").
function clock(s, h12, withMinutes) {
    var h = hourOf(s), m = s.substr(14, 2);
    if (!h12) return [(h < 10 ? "0" : "") + h + (withMinutes === false ? "" : ":" + m), ""];
    var suffix = h < 12 ? "AM" : "PM";
    h = h % 12 || 12;
    return [withMinutes === false ? String(h) : h + ":" + m, suffix];
}
function clockText(s, h12, withMinutes) { var c = clock(s, h12, withMinutes); return c[0] + c[1]; }
// The place's current time, from its UTC offset.
function placeNow(offsetSeconds) {
    var d = new Date(Date.now() + offsetSeconds * 1000);
    function p(n) { return (n < 10 ? "0" : "") + n; }
    return d.getUTCFullYear() + "-" + p(d.getUTCMonth() + 1) + "-" + p(d.getUTCDate()) + "T" + p(d.getUTCHours()) + ":" + p(d.getUTCMinutes());
}
function duration(seconds) {
    var h = Math.floor(seconds / 3600), m = Math.round((seconds % 3600) / 60);
    if (m === 60) { h += 1; m = 0; }
    return h + " hr " + m + " min";
}

// ------------------------------------------------------------------ scales and phrases
// Air quality (US AQI)
function aqiCategory(v) {
    return v <= 50 ? "Good" : v <= 100 ? "Moderate" : v <= 150 ? "Unhealthy for Sensitive Groups"
         : v <= 200 ? "Unhealthy" : v <= 300 ? "Very Unhealthy" : "Hazardous";
}
function aqiSentence(now, yesterday) {
    var s = "Air quality index is " + Math.round(now) + ", which is ";
    if (yesterday === null || yesterday === undefined) return "Air quality index is " + Math.round(now) + ".";
    var d = now - yesterday;
    return s + (Math.abs(d) < 10 ? "similar to" : d < 0 ? "better than" : "worse than") + " yesterday at about this time.";
}
function uvCategory(v) {
    v = Math.round(v);
    return v <= 2 ? "Low" : v <= 5 ? "Moderate" : v <= 7 ? "High" : v <= 10 ? "Very High" : "Extreme";
}
function visibilitySentence(m) {
    return m >= 16000 ? "Perfectly clear view." : m >= 8000 ? "Clear view." : m >= 4000 ? "Light haze is affecting visibility."
         : m >= 1000 ? "Haze is affecting visibility." : "Fog is affecting visibility.";
}
function feelsSentence(actual, feels, humidity, wind) {
    var d = feels - actual;
    if (Math.abs(d) < 1.5) return "Similar to the actual temperature.";
    if (d < 0) return wind > 10 ? "Wind is making it feel cooler." : "It feels cooler than the actual temperature.";
    return humidity > 60 ? "Humidity is making it feel warmer." : "It feels warmer than the actual temperature.";
}
function cloudSentence(pct) {
    return pct < 10 ? "Clear skies." : pct < 30 ? "Mostly clear skies." : pct < 60 ? "Partly cloudy skies."
         : pct < 90 ? "Mostly cloudy skies." : "Overcast skies.";
}

// The line under "Conditions": what the rest of the day looks like.
function summary(f, imperial) {
    var c = f.current, d = f.daily;
    var today = 1; // index 0 is yesterday (past_days=1)
    var gust = speed(c.wind_gusts_10m, imperial) + " " + speedUnit(imperial);
    var name = conditionName(d.weather_code[today]).toLowerCase();
    var rainChance = d.precipitation_probability_max[today];
    var s = name.charAt(0).toUpperCase() + name.slice(1) + " conditions expected today";
    if (rainChance >= 30) s += ", with a " + rainChance + "% chance of rain";
    return s + ". Wind gusts are up to " + gust + ".";
}

// Colour of a temperature on the forecast bars, from cold blue to hot red (°C).
function tempColor(c) {
    var stops = [[-10, [0.37, 0.36, 0.90]], [0, [0.35, 0.78, 0.98]], [10, [0.19, 0.82, 0.35]],
                 [20, [1.0, 0.84, 0.04]], [28, [1.0, 0.58, 0.0]], [36, [1.0, 0.27, 0.23]]];
    if (c <= stops[0][0]) return stops[0][1];
    for (var i = 1; i < stops.length; i++) {
        if (c <= stops[i][0]) {
            var a = stops[i - 1], b = stops[i], t = (c - a[0]) / (b[0] - a[0]);
            return [a[1][0] + (b[1][0] - a[1][0]) * t, a[1][1] + (b[1][1] - a[1][1]) * t, a[1][2] + (b[1][2] - a[1][2]) * t];
        }
    }
    return stops[stops.length - 1][1];
}

// ------------------------------------------------------------------ moon
var SYNODIC = 29.530588853;
function moonAge(ms) {
    var ref = Date.UTC(2000, 0, 6, 18, 14); // a new moon
    var age = ((ms - ref) / 86400000) % SYNODIC;
    return age < 0 ? age + SYNODIC : age;
}
function moonPhaseName(age) {
    var p = age / SYNODIC;
    return p < 0.0339 || p > 0.9661 ? "New Moon" : p < 0.2161 ? "Waxing Crescent" : p < 0.2839 ? "First Quarter"
         : p < 0.4661 ? "Waxing Gibbous" : p < 0.5339 ? "Full Moon" : p < 0.7161 ? "Waning Gibbous"
         : p < 0.7839 ? "Last Quarter" : "Waning Crescent";
}
function daysToFull(age) {
    var d = SYNODIC / 2 - age;
    if (d < 0) d += SYNODIC;
    return Math.round(d);
}

// ------------------------------------------------------------------ locations
// A timezone like "America/Chicago" names a city worth starting with.
function cityFromZone(zone) {
    if (!zone || zone.indexOf("/") < 0) return "";
    var city = zone.split("/").pop().replace(/_/g, " ");
    return /^(UTC|GMT|Etc)/.test(zone) ? "" : city;
}
