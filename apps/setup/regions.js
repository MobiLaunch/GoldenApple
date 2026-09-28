// Countries for Setup Assistant: flag, a default time zone and the keyboard
// layout (XKB) people there usually type on. Picking one presets the keyboard
// and time zone, as choosing a region does on the Mac.
.pragma library

var LIST = [
    ["United States", "🇺🇸", "America/New_York", "us", "en_US"],
    ["United Kingdom", "🇬🇧", "Europe/London", "gb", "en_GB"],
    ["Canada", "🇨🇦", "America/Toronto", "us", "en_CA"],
    ["Australia", "🇦🇺", "Australia/Sydney", "us", "en_AU"],
    ["New Zealand", "🇳🇿", "Pacific/Auckland", "us", "en_NZ"],
    ["Ireland", "🇮🇪", "Europe/Dublin", "ie", "en_IE"],
    ["India", "🇮🇳", "Asia/Kolkata", "us", "en_IN"],
    ["Singapore", "🇸🇬", "Asia/Singapore", "us", "en_SG"],
    ["South Africa", "🇿🇦", "Africa/Johannesburg", "us", "en_ZA"],
    ["Germany", "🇩🇪", "Europe/Berlin", "de", "de_DE"],
    ["Austria", "🇦🇹", "Europe/Vienna", "at", "de_AT"],
    ["Switzerland", "🇨🇭", "Europe/Zurich", "ch", "de_CH"],
    ["France", "🇫🇷", "Europe/Paris", "fr", "fr_FR"],
    ["Belgium", "🇧🇪", "Europe/Brussels", "be", "fr_BE"],
    ["Netherlands", "🇳🇱", "Europe/Amsterdam", "us", "nl_NL"],
    ["Luxembourg", "🇱🇺", "Europe/Luxembourg", "ch(fr)", "fr_LU"],
    ["Spain", "🇪🇸", "Europe/Madrid", "es", "es_ES"],
    ["Portugal", "🇵🇹", "Europe/Lisbon", "pt", "pt_PT"],
    ["Italy", "🇮🇹", "Europe/Rome", "it", "it_IT"],
    ["Denmark", "🇩🇰", "Europe/Copenhagen", "dk", "da_DK"],
    ["Norway", "🇳🇴", "Europe/Oslo", "no", "nb_NO"],
    ["Sweden", "🇸🇪", "Europe/Stockholm", "se", "sv_SE"],
    ["Finland", "🇫🇮", "Europe/Helsinki", "fi", "fi_FI"],
    ["Iceland", "🇮🇸", "Atlantic/Reykjavik", "is", "is_IS"],
    ["Poland", "🇵🇱", "Europe/Warsaw", "pl", "pl_PL"],
    ["Czechia", "🇨🇿", "Europe/Prague", "cz", "cs_CZ"],
    ["Slovakia", "🇸🇰", "Europe/Bratislava", "sk", "sk_SK"],
    ["Hungary", "🇭🇺", "Europe/Budapest", "hu", "hu_HU"],
    ["Romania", "🇷🇴", "Europe/Bucharest", "ro", "ro_RO"],
    ["Greece", "🇬🇷", "Europe/Athens", "gr", "el_GR"],
    ["Turkey", "🇹🇷", "Europe/Istanbul", "tr", "tr_TR"],
    ["Ukraine", "🇺🇦", "Europe/Kyiv", "ua", "uk_UA"],
    ["Israel", "🇮🇱", "Asia/Jerusalem", "il", "he_IL"],
    ["United Arab Emirates", "🇦🇪", "Asia/Dubai", "us", "ar_AE"],
    ["Saudi Arabia", "🇸🇦", "Asia/Riyadh", "us", "ar_SA"],
    ["Egypt", "🇪🇬", "Africa/Cairo", "us", "ar_EG"],
    ["Nigeria", "🇳🇬", "Africa/Lagos", "us", "en_NG"],
    ["Kenya", "🇰🇪", "Africa/Nairobi", "us", "en_KE"],
    ["Japan", "🇯🇵", "Asia/Tokyo", "jp", "ja_JP"],
    ["South Korea", "🇰🇷", "Asia/Seoul", "kr", "ko_KR"],
    ["China mainland", "🇨🇳", "Asia/Shanghai", "cn", "zh_CN"],
    ["Hong Kong", "🇭🇰", "Asia/Hong_Kong", "us", "zh_HK"],
    ["Taiwan", "🇹🇼", "Asia/Taipei", "tw", "zh_TW"],
    ["Thailand", "🇹🇭", "Asia/Bangkok", "us", "th_TH"],
    ["Vietnam", "🇻🇳", "Asia/Ho_Chi_Minh", "us", "vi_VN"],
    ["Philippines", "🇵🇭", "Asia/Manila", "us", "en_PH"],
    ["Indonesia", "🇮🇩", "Asia/Jakarta", "us", "id_ID"],
    ["Malaysia", "🇲🇾", "Asia/Kuala_Lumpur", "us", "ms_MY"],
    ["Mexico", "🇲🇽", "America/Mexico_City", "latam", "es_MX"],
    ["Brazil", "🇧🇷", "America/Sao_Paulo", "br", "pt_BR"],
    ["Argentina", "🇦🇷", "America/Argentina/Buenos_Aires", "latam", "es_AR"],
    ["Chile", "🇨🇱", "America/Santiago", "latam", "es_CL"],
    ["Colombia", "🇨🇴", "America/Bogota", "latam", "es_CO"],
    ["Peru", "🇵🇪", "America/Lima", "latam", "es_PE"],
].map(function (r) { return { name: r[0], flag: r[1], zone: r[2], keyboard: r[3], locale: r[4] }; });

// The country to suggest: from the time zone, then the language setting.
function guess(zone, lang) {
    var i, byZone = null;
    for (i = 0; i < LIST.length; i++) if (LIST[i].zone === zone) byZone = LIST[i];
    if (byZone) return byZone;
    var loc = (lang || "").split(".")[0];
    for (i = 0; i < LIST.length; i++) if (LIST[i].locale === loc) return LIST[i];
    return LIST[0];
}

// "us" → "us", "ch(fr)" → ["ch", "fr"]: layout and variant for Hyprland.
function layout(kb) {
    var m = /^([a-z]+)(?:\(([a-z]+)\))?$/.exec(kb) || [kb, kb, ""];
    return { layout: m[1], variant: m[2] || "" };
}
