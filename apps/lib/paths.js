.pragma library
function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/");
}
