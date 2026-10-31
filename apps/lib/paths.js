.pragma library
// A path as a file:// URL, each part escaped ("Beach #2.jpg" is a file, not
// a fragment). A value that's already a URL is returned as it is.
function fileUrl(path) {
    const p = String(path ?? "");
    if (/^[a-z][a-z0-9+.-]*:/i.test(p)) return p;
    return "file://" + p.split("/").map(encodeURIComponent).join("/");
}
