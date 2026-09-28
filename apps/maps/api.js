// Maps services, none needing an account: map tiles from CARTO (OpenStreetMap
// data; Voyager is close to Apple Maps' palette), Esri World Imagery for
// satellite, place search from Photon (komoot) and routes from OSRM on
// routing.openstreetmap.de.
.pragma library

var STYLES = {
    standard: { name: "Standard", url: function (z, x, y) { return "https://" + "abcd"[(x + y) % 4] + ".basemaps.cartocdn.com/rastertiles/voyager/" + z + "/" + x + "/" + y + "@2x.png"; },
                credit: "© OpenStreetMap contributors © CARTO", bg: "#f2efe9" },
    muted:    { name: "Muted", url: function (z, x, y) { return "https://" + "abcd"[(x + y) % 4] + ".basemaps.cartocdn.com/light_all/" + z + "/" + x + "/" + y + "@2x.png"; },
                credit: "© OpenStreetMap contributors © CARTO", bg: "#f5f5f3" },
    dark:     { name: "Dark", url: function (z, x, y) { return "https://" + "abcd"[(x + y) % 4] + ".basemaps.cartocdn.com/dark_all/" + z + "/" + x + "/" + y + "@2x.png"; },
                credit: "© OpenStreetMap contributors © CARTO", bg: "#262626" },
    satellite:{ name: "Satellite", url: function (z, x, y) { return "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/" + z + "/" + y + "/" + x; },
                credit: "© Esri, Maxar, Earthstar Geographics", bg: "#1b2a1f" },
};

function searchUrl(q, lat, lon) {
    return "https://photon.komoot.io/api/?limit=10&lang=en&q=" + encodeURIComponent(q)
        + (lat !== undefined ? "&lat=" + lat.toFixed(4) + "&lon=" + lon.toFixed(4) : "");
}
var PROFILES = { car: "routed-car", foot: "routed-foot", bike: "routed-bike" };
function routeUrl(mode, from, to) {
    return "https://routing.openstreetmap.de/" + PROFILES[mode] + "/route/v1/driving/"
        + from.lon + "," + from.lat + ";" + to.lon + "," + to.lat
        + "?overview=full&geometries=geojson&alternatives=true&steps=true";
}

// Photon feature → place
function place(f) {
    var p = f.properties || {}, c = f.geometry.coordinates;
    var street = [p.housenumber, p.street].filter(Boolean).join(" ");
    var area = [p.city || p.town || p.village || p.district, p.state, p.country].filter(Boolean);
    var name = p.name || street || area[0] || "Dropped Pin";
    var address = [street !== name ? street : "", p.postcode ? (area[0] ? area[0] + " " + p.postcode : p.postcode) : area[0], area[1], area[2]]
        .filter(Boolean).filter(function (s, i, a) { return a.indexOf(s) === i && s !== name; }).join(", ");
    return { name: name, address: address, lat: c[1], lon: c[0], kind: p.osm_value || p.type || "", key: p.osm_key || "" };
}

// A colour and symbol for a place, as Maps colours its pins by category.
function category(pl) {
    var k = (pl.key || "") + ":" + (pl.kind || "");
    if (/restaurant|cafe|fast_food|bar|pub|food|bakery/.test(k)) return ["#ff9f0a", "star"];
    if (/shop|mall|supermarket|store/.test(k)) return ["#ffcc00", "tag"];
    if (/park|garden|forest|nature|wood|leisure|peak|beach/.test(k)) return ["#34c759", "pin"];
    if (/school|university|college|library|museum|theatre|cinema|arts/.test(k)) return ["#af52de", "book"];
    if (/hospital|clinic|pharmacy|doctors/.test(k)) return ["#ff3b30", "plus"];
    if (/station|railway|bus|aerodrome|airport|subway|tram/.test(k)) return ["#0a84ff", "car"];
    if (/city|town|village|suburb|place|state|country|county/.test(k)) return ["#8e8e93", "location"];
    return ["#ff3b30", "pin"];
}

// ------------------------------------------------------------------ formatting
function duration(s) {
    var m = Math.round(s / 60);
    if (m < 60) return m + " min";
    var h = Math.floor(m / 60); m = m % 60;
    return h + " hr" + (m ? " " + m + " min" : "");
}
function distance(m, imperial) {
    if (imperial) {
        var mi = m / 1609.344;
        if (mi < 0.1) return Math.round(m * 3.28084 / 50) * 50 + " ft";
        return (mi < 10 ? Math.round(mi * 10) / 10 : Math.round(mi)) + (mi === 1 ? " mile" : " miles");
    }
    if (m < 1000) return Math.round(m / 10) * 10 + " m";
    var km = m / 1000;
    return (km < 10 ? Math.round(km * 10) / 10 : Math.round(km)) + " km";
}
function eta(seconds, h12) {
    var d = new Date(Date.now() + seconds * 1000);
    var h = d.getHours(), m = d.getMinutes();
    var mm = (m < 10 ? "0" : "") + m;
    if (!h12) return (h < 10 ? "0" : "") + h + ":" + mm + " ETA";
    return ((h % 12) || 12) + ":" + mm + (h < 12 ? " AM" : " PM") + " ETA";
}

// OSRM step → an instruction, the way Maps words them.
function instruction(step) {
    var m = step.maneuver || {}, name = step.name || step.ref || "";
    var onto = name ? " onto " + name : "";
    var mod = (m.modifier || "").replace("sharp ", "sharp ").replace("slight ", "slight ");
    switch (m.type) {
    case "depart": return "Start" + (name ? " on " + name : "");
    case "arrive": return "Arrive at your destination";
    case "turn": case "end of road": return (mod === "straight" ? "Continue" : "Turn " + mod) + onto;
    case "continue": case "new name": return "Continue" + onto;
    case "merge": return "Merge" + onto;
    case "on ramp": return "Take the ramp" + onto;
    case "off ramp": return "Take the exit" + onto;
    case "fork": return "Keep " + (mod.indexOf("left") >= 0 ? "left" : "right") + onto;
    case "roundabout": case "rotary": return "At the roundabout, take exit " + (m.exit || 1) + onto;
    default: return (mod ? "Go " + mod : "Continue") + onto;
    }
}
function turnSymbol(step) {
    var mod = (step.maneuver && step.maneuver.modifier) || "";
    if (step.maneuver && step.maneuver.type === "arrive") return "pin";
    if (mod.indexOf("left") >= 0) return "chevron-left";
    if (mod.indexOf("right") >= 0) return "chevron-right";
    return "arrow-up";
}

// ------------------------------------------------------------------ geometry
function worldPx(lat, lon, z) {
    var n = 256 * Math.pow(2, z), la = Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI / 180;
    return { x: (lon + 180) / 360 * n, y: (1 - Math.log(Math.tan(la) + 1 / Math.cos(la)) / Math.PI) / 2 * n };
}
function fromWorldPx(x, y, z) {
    var n = 256 * Math.pow(2, z);
    var lon = x / n * 360 - 180;
    var lat = Math.atan(Math.sinh(Math.PI * (1 - 2 * y / n))) * 180 / Math.PI;
    return { lat: lat, lon: lon };
}
// The zoom at which a box of coordinates fits w × h pixels.
function fitZoom(pts, w, h) {
    var minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (var i = 0; i < pts.length; i++) {
        minLat = Math.min(minLat, pts[i][1]); maxLat = Math.max(maxLat, pts[i][1]);
        minLon = Math.min(minLon, pts[i][0]); maxLon = Math.max(maxLon, pts[i][0]);
    }
    var a = worldPx(maxLat, minLon, 0), b = worldPx(minLat, maxLon, 0);
    var zx = Math.log2(w / Math.max(1e-9, b.x - a.x)), zy = Math.log2(h / Math.max(1e-9, b.y - a.y));
    return { zoom: Math.max(2, Math.min(17, Math.min(zx, zy))), lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2,
             center: fromWorldPx((a.x + b.x) / 2, (a.y + b.y) / 2, 0) };
}
function cityFromZone(zone) {
    if (!zone || zone.indexOf("/") < 0 || /^(UTC|GMT|Etc)/.test(zone)) return "";
    return zone.split("/").pop().replace(/_/g, " ");
}
