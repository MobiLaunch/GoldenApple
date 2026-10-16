.pragma library
// The Weather widget's slice of apps/weather/api.js: the Open-Meteo request,
// WMO weather codes and a summary of a forecast in the words the widget uses.
// Open-Meteo times are the place's own wall-clock strings, compared as strings.

function forecastUrl(lat, lon) {
    return "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon
        + "&current=temperature_2m,is_day,weather_code"
        + "&hourly=temperature_2m,weather_code,is_day"
        + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
        + "&timezone=auto&forecast_days=2";
}
function geocodeUrl(name) {
    return "https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name=" + encodeURIComponent(name);
}
function cityFromZone(zone) {
    if (!zone || zone.indexOf("/") < 0 || /^(UTC|GMT|Etc)/.test(zone)) return "";
    return zone.split("/").pop().replace(/_/g, " ");
}

// WMO code → [name, icon, sky]
var CODES = {
    0: ["Clear", "sun", "clear"], 1: ["Mostly Clear", "sun", "clear"], 2: ["Partly Cloudy", "cloud-sun", "partly"],
    3: ["Cloudy", "cloud", "cloudy"], 45: ["Foggy", "fog", "fog"], 48: ["Foggy", "fog", "fog"],
    51: ["Drizzle", "cloud-drizzle", "rain"], 53: ["Drizzle", "cloud-drizzle", "rain"], 55: ["Drizzle", "cloud-drizzle", "rain"],
    56: ["Freezing Drizzle", "cloud-drizzle", "rain"], 57: ["Freezing Drizzle", "cloud-drizzle", "rain"],
    61: ["Light Rain", "cloud-rain", "rain"], 63: ["Rain", "cloud-rain", "rain"], 65: ["Heavy Rain", "cloud-heavyrain", "rain"],
    66: ["Freezing Rain", "cloud-rain", "rain"], 67: ["Freezing Rain", "cloud-heavyrain", "rain"],
    71: ["Light Snow", "cloud-snow", "snow"], 73: ["Snow", "cloud-snow", "snow"], 75: ["Heavy Snow", "cloud-snow", "snow"],
    77: ["Snow Grains", "cloud-snow", "snow"], 80: ["Showers", "cloud-rain", "rain"], 81: ["Showers", "cloud-rain", "rain"],
    82: ["Heavy Showers", "cloud-heavyrain", "rain"], 85: ["Snow Showers", "cloud-snow", "snow"], 86: ["Snow Showers", "cloud-snow", "snow"],
    95: ["Thunderstorms", "cloud-bolt", "storm"], 96: ["Thunderstorms", "cloud-bolt", "storm"], 99: ["Thunderstorms", "cloud-bolt", "storm"]
};
function cond(code) { return CODES[code] || ["—", "cloud", "cloudy"]; }
function icon(code, isDay) {
    var i = cond(code)[1];
    if (!isDay && i === "sun") return "moon";
    if (!isDay && i === "cloud-sun") return "cloud-moon";
    return i;
}
function temp(c, imperial) { return c === null || c === undefined ? "--" : Math.round(imperial ? c * 9 / 5 + 32 : c) + "°"; }
function hourLabel(s, now) {
    if (s.substr(0, 13) === now.substr(0, 13)) return "Now";
    var h = Number(s.substr(11, 2));
    return (h % 12 || 12) + (h < 12 ? "AM" : "PM");
}
// The sky behind the widget, top and bottom colours, as Weather paints it.
function sky(kind, isDay) {
    if (!isDay) return kind === "clear" || kind === "partly" ? ["#0b1736", "#28385e"] : ["#1c2433", "#3a4252"];
    return { clear: ["#2f7fd8", "#7db6ee"], partly: ["#3a7bc8", "#86acd6"], cloudy: ["#5b6f86", "#8fa0b3"],
             fog: ["#7d8590", "#a6adb5"], rain: ["#43536a", "#6f7f93"], snow: ["#7f93ab", "#b6c4d4"],
             storm: ["#2d3442", "#525b6b"] }[kind] || ["#3a7bc8", "#86acd6"];
}

// forecast (Open-Meteo JSON) → what the widget shows.
function summary(f, imperial) {
    var c = f.current, today = c.time.substr(0, 10);
    var d = Math.max(0, f.daily.time.indexOf(today));
    var start = Math.max(0, f.hourly.time.findIndex(function (t) { return t.substr(0, 13) === c.time.substr(0, 13); }));
    var hours = [];
    for (var i = start; i < Math.min(f.hourly.time.length, start + 6); i++)
        hours.push({ label: hourLabel(f.hourly.time[i], c.time), icon: icon(f.hourly.weather_code[i], f.hourly.is_day[i]),
                     temp: temp(f.hourly.temperature_2m[i], imperial) });
    var info = cond(c.weather_code);
    return {
        temp: temp(c.temperature_2m, imperial), condition: info[0], icon: icon(c.weather_code, c.is_day),
        high: temp(f.daily.temperature_2m_max[d], imperial), low: temp(f.daily.temperature_2m_min[d], imperial),
        sky: sky(info[2], c.is_day), hours: hours
    };
}
