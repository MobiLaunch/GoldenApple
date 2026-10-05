// Languages and toolchains, for icons, file types and the template gallery.
.pragma library

// Toolchain id → name, manifest file, icon gradient and the symbol on it.
var TOOLCHAINS = {
    goldengate: { name: "CitronOS", manifest: "Interface.lcdesign", colors: ["#ffd84d", "#ff8a00"], symbol: "sparkles" },
    swift: { name: "Swift", manifest: "Package.swift", colors: ["#ff8f5e", "#e8382a"], symbol: "swift" },
    python: { name: "Python", manifest: "pyproject.toml", colors: ["#5ea3e8", "#2f5f99"], symbol: "python" },
    cargo: { name: "Rust", manifest: "Cargo.toml", colors: ["#f0a35e", "#a8461c"], symbol: "rust" },
    meson: { name: "C", manifest: "meson.build", colors: ["#8fa9cf", "#3e5378"], symbol: "c-language" },
};

function toolchain(id) { return TOOLCHAINS[id] || { name: "Folder", manifest: "", colors: ["#9aa1ab", "#5f6670"], symbol: "folder" }; }

// The files a project of each toolchain opens with first.
var START_FILES = {
    goldengate: ["Interface.lcdesign"],
    swift: ["ContentView.swift", "main.swift"],
    python: ["window.py", "main.py"],
    cargo: ["main.rs", "lib.rs"],
    meson: ["main.c"],
};

// File name → { type, symbol, color } (color tints the navigator and tab icons).
function fileInfo(name) {
    const n = String(name || "").toLowerCase();
    const ext = n.includes(".") ? n.split(".").pop() : "";
    if (n === "package.swift") return { type: "Swift Package Manifest", symbol: "gear", color: "#a2845e" };
    if (n === "cargo.toml") return { type: "Cargo Manifest", symbol: "gear", color: "#a2845e" };
    if (n === "meson.build") return { type: "Meson Build File", symbol: "gear", color: "#a2845e" };
    if (n === "pyproject.toml") return { type: "Python Project", symbol: "gear", color: "#a2845e" };
    if (ext === "lcdesign") return { type: "CitronOS Interface", symbol: "sparkles", color: "#ff9f0a" };
    const byExt = {
        swift: ["Swift Source", "code", "#f05138"],
        rs: ["Rust Source", "code", "#c06a2b"],
        py: ["Python Source", "code", "#3572a5"],
        c: ["C Source", "code", "#5f6b7a"],
        h: ["C Header", "code", "#8a6bbf"],
        cpp: ["C++ Source", "code", "#f34b7d"],
        qml: ["QML Document", "code", "#3fa535"],
        js: ["JavaScript", "code", "#d4b106"],
        css: ["Style Sheet", "paintbrush", "#7d4fbd"],
        json: ["JSON", "doc", "#6e7781"],
        toml: ["TOML", "doc", "#9c4221"],
        md: ["Markdown Text", "doc", "#0a84ff"],
        txt: ["Plain Text", "doc", "transparent"],
        xml: ["XML", "doc", "#e37933"],
        desktop: ["Desktop Entry", "doc", "#6e7781"],
        png: ["PNG Image", "photo", "#30d158"],
        jpg: ["JPEG Image", "photo", "#30d158"],
        jpeg: ["JPEG Image", "photo", "#30d158"],
        svg: ["SVG Image", "photo", "#ff9f0a"],
        gif: ["GIF Image", "photo", "#30d158"],
        webp: ["WebP Image", "photo", "#30d158"],
    };
    const hit = byExt[ext];
    if (hit) return { type: hit[0], symbol: hit[1], color: hit[2] };
    return { type: "Plain Text", symbol: "doc", color: "transparent" };
}

function isImage(name) { return /\.(png|jpe?g|svg|gif|webp)$/i.test(String(name)); }

// File ▸ New ▸ File suggestions for each toolchain.
var NEW_FILE = { goldengate: "Logic.js", swift: "File.swift", python: "module.py", cargo: "module.rs", meson: "file.c" };
