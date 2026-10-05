// CitronOS Web's page script for saved passwords. It runs in an isolated
// world (WebEngineScript.ApplicationWorld): it shares the page's DOM but none
// of its JavaScript, so the page can't read the token or call these functions.
// browser backend substitutes __TOKEN__ and, for filling, __CREDENTIALS__.
//
// Capture: when a sign-in is submitted (a form's submit, Enter in a field, or
// a click on its submit button: many sites sign in without a real submit), it
// logs "\u0001gg-pw:<token>:{u, p}" for Web to offer saving. On a username-
// first page (no password field yet) it logs "\u0001gg-user:<token>:{u}" so
// the next page's password can be saved under that name.
//
// Fill: fills the first saved login into the page's sign-in fields, now and
// as fields appear (single-page apps draw them late), for 30 seconds.
(function () {
    "use strict";
    var TOKEN = "__TOKEN__";
    var CREDENTIALS = __CREDENTIALS__;
    var state = window.__ggPasswords || (window.__ggPasswords = { last: "" });

    function visible(el) { return !!(el.offsetWidth || el.offsetHeight || el.getClientRects().length); }
    function textLike(el) {
        var t = (el.getAttribute("type") || "text").toLowerCase();
        return el.tagName === "INPUT" && ["text", "email", "tel", ""].indexOf(t) >= 0 && !el.disabled;
    }
    function usernameLike(el) {
        if (!textLike(el)) return false;
        var hint = ((el.getAttribute("autocomplete") || "") + " " + (el.name || "") + " " + (el.id || "") + " " +
                    (el.getAttribute("type") || "")).toLowerCase();
        return /user|email|login|account|identifier|phone/.test(hint);
    }
    // The username field for a password field: the last text-like field
    // before it in the same form (or page).
    function userFieldFor(pw) {
        var scope = pw.form || pw.closest("form") || document;
        var fields = Array.prototype.filter.call(scope.querySelectorAll("input"), textLike);
        var best = null;
        for (var i = 0; i < fields.length; i++)
            if (fields[i].compareDocumentPosition(pw) & Node.DOCUMENT_POSITION_FOLLOWING) best = fields[i];
        return best;
    }
    function passwordFields(scope) {
        return Array.prototype.filter.call((scope || document).querySelectorAll("input[type=password]"),
                                           function (el) { return !el.disabled; });
    }

    function report(scope) {
        var filled = passwordFields(scope).filter(function (el) { return el.value; });
        if (!filled.length) {
            var user = Array.prototype.filter.call((scope || document).querySelectorAll("input"), usernameLike)
                .filter(function (el) { return el.value && visible(el); })[0];
            if (user) console.log("\u0001gg-user:" + TOKEN + ":" + JSON.stringify({ u: user.value }));
            return;
        }
        // Sign-up and change-password forms have several: the last is the new one.
        var pw = filled[filled.length - 1];
        var userField = userFieldFor(pw);
        var message = JSON.stringify({ u: userField ? userField.value : "", p: pw.value });
        if (message === state.last) return;
        state.last = message;
        console.log("\u0001gg-pw:" + TOKEN + ":" + message);
    }

    if (!state.listening) {
        state.listening = true;
        document.addEventListener("submit", function (e) { report(e.target); }, true);
        document.addEventListener("keydown", function (e) {
            if (e.key === "Enter" && e.target && e.target.tagName === "INPUT") report(e.target.form || document);
        }, true);
        document.addEventListener("click", function (e) {
            var b = e.target && e.target.closest && e.target.closest("button, input[type=submit], [role=button]");
            if (!b) return;
            var type = (b.getAttribute("type") || (b.tagName === "BUTTON" && b.form ? "submit" : "")).toLowerCase();
            var words = (b.innerText || b.value || b.getAttribute("aria-label") || "").toLowerCase();
            if (type === "submit" || /sign ?in|log ?in|continue|next|submit|sign ?up|create|register|save/.test(words))
                setTimeout(function () { report(b.form || b.closest("form") || document); }, 0);
        }, true);
    }

    if (!CREDENTIALS || !CREDENTIALS.length) return;
    var login = CREDENTIALS[0];
    // Set the value the way typing does, so frameworks (React, Vue…) see it.
    function set(el, value) {
        var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
        setter.call(el, value);
        el.dispatchEvent(new Event("input", { bubbles: true }));
        el.dispatchEvent(new Event("change", { bubbles: true }));
    }
    function fill() {
        var pws = passwordFields(document).filter(function (el) {
            return !el.value && (el.getAttribute("autocomplete") || "").toLowerCase() !== "new-password";
        });
        pws.forEach(function (pw) {
            set(pw, login.password);
            var user = userFieldFor(pw);
            if (user && !user.value && login.username) set(user, login.username);
        });
        if (!passwordFields(document).length && login.username) {
            var user = Array.prototype.filter.call(document.querySelectorAll("input"), usernameLike)
                .filter(function (el) { return !el.value && visible(el); })[0];
            if (user) set(user, login.username);
        }
    }
    fill();
    if (state.observer) state.observer.disconnect();
    state.observer = new MutationObserver(fill);
    state.observer.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(function () { state.observer.disconnect(); }, 30000);
})();
