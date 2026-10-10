#!/usr/bin/env python3
"""Writes a Houston-like Open-Meteo forecast (cloudy, 28 °C, rain later in the
week) to forecast.json, air.json and geocode.json in the given folder, in the
exact shape the APIs return, for offline tests and screenshots:

    apps/weather/tests/make-fixture.py /tmp/wx && GG_WEATHER_FIXTURE=/tmp/wx qs -p apps/weather.qml
"""
import json, math, sys, datetime as dt, os

out = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(out, exist_ok=True)
today = dt.date(2026, 9, 1)
days = [today + dt.timedelta(days=i) for i in range(-1, 10)]
now = "2026-09-01T09:45"

hours = [dt.datetime.combine(d, dt.time(h)) for d in days for h in range(24)]
def temp_at(t):
    return 26.5 + 4.5 * math.sin((t.hour - 9) / 24 * 2 * math.pi) + (t.day % 3) * 0.3
codes = []
for t in hours:
    if t.date() == today and 16 <= t.hour <= 18: codes.append(61)
    else: codes.append(3 if t.hour % 5 else 2)
pop = [30 if c == 61 else (25 if t.hour in (15, 19) else 0) for t, c in zip(hours, codes)]
f = {
    "latitude": 29.76, "longitude": -95.36, "utc_offset_seconds": -18000, "timezone": "America/Chicago",
    "current": {
        "time": now, "interval": 900, "temperature_2m": 27.8, "apparent_temperature": 28.4,
        "relative_humidity_2m": 83, "dew_point_2m": 24.4, "is_day": 1, "weather_code": 3, "cloud_cover": 88,
        "pressure_msl": 1015.3, "wind_speed_10m": 9.7, "wind_direction_10m": 5, "wind_gusts_10m": 19.3,
        "visibility": 20920, "precipitation": 0,
    },
    "hourly": {
        "time": [t.strftime("%Y-%m-%dT%H:%M") for t in hours],
        "temperature_2m": [round(temp_at(t), 1) for t in hours],
        "weather_code": codes,
        "precipitation_probability": pop,
        "is_day": [1 if 7 <= t.hour < 20 else 0 for t in hours],
        "uv_index": [round(max(0, 2.4 * math.sin((t.hour - 6.5) / 13 * math.pi)) * (1.5 if t.hour > 9 else 1), 2) for t in hours],
        "pressure_msl": [round(1014 + 0.2 * i % 3, 1) for i in range(len(hours))],
        "wind_speed_10m": [round(8 + 5 * math.sin(t.hour / 4), 1) for t in hours],
    },
    "daily": {
        "time": [d.isoformat() for d in days],
        "weather_code": [3, 61, 61, 61, 80, 61, 61, 80, 61, 61, 80],
        "temperature_2m_max": [31.5, 32.2, 32.8, 31.7, 32.8, 32.8, 33.3, 31.7, 33.3, 33.3, 31.1],
        "temperature_2m_min": [25.6, 26.1, 24.4, 26.1, 25.0, 25.0, 25.0, 24.4, 25.0, 24.4, 25.6],
        "precipitation_probability_max": [20, 70, 85, 65, 55, 50, 55, 75, 55, 55, 70],
        "precipitation_sum": [0, 6.4, 30.5, 4.1, 2.0, 1.2, 3.3, 7.9, 1.0, 2.2, 6.0],
        "sunrise": [d.isoformat() + "T06:59" for d in days],
        "sunset": [d.isoformat() + "T19:" + str(44 - i) for i, d in enumerate(days)],
        "daylight_duration": [45900 - i * 75 for i in range(len(days))],
        "uv_index_max": [6.1] * len(days),
    },
}
air = {
    "current": {"time": now, "us_aqi": 48},
    "hourly": {"time": [t.strftime("%Y-%m-%dT%H:%M") for t in hours[:48]], "us_aqi": [50] * 48},
}
geo = {"results": [
    {"name": "Houston", "latitude": 29.76328, "longitude": -95.36327, "country": "United States", "admin1": "Texas"},
    {"name": "Houston", "latitude": 61.63, "longitude": -149.8, "country": "United States", "admin1": "Alaska"},
]}
for name, obj in (("forecast", f), ("air", air), ("geocode", geo)):
    with open(os.path.join(out, name + ".json"), "w") as fh:
        json.dump(obj, fh)
