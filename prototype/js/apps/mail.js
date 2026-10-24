// Mail: mailbox sidebar, message list, reader. Archive/delete collapse the row,
// flags toggle, and Compose opens a window whose Send flies the message away.
import { h, sym, avatar, animate, bus } from "../util.js";
import { createWindow, pill, tb, div } from "../wm.js";
import { registerApp } from "../apps.js";

const MSGS = [
  { id: 1, box: "inbox", from: "Hyprland Weekly", subject: "0.52 is out: gestures, layer rules and more", date: "9:41 PM", unread: true,
    body: ["Hi there,", "This release brings a new gesture syntax, per-layer blur controls and a faster renderer for fractional scaling.", "The full changelog is on the website. As always, thanks to everyone who tested the release candidates.", "— The Hyprland team"] },
  { id: 2, box: "inbox", from: "Maya Chen", subject: "Liquid Glass review notes", date: "6:12 PM", unread: true, flagged: true,
    body: ["Hey!", "I went through the Control Center build. The stagger feels great; could we try 12ms instead of 14ms between modules?", "Also the rim on the Dock looks a little bright on the Dusk wallpaper. Maybe drop it to 70%?", "Otherwise this is really coming together.", "Maya"] },
  { id: 3, box: "inbox", from: "Arch Linux", subject: "Scheduled mirror maintenance", date: "Yesterday", unread: false,
    body: ["The primary mirror will be unavailable on Sunday between 02:00 and 04:00 UTC while storage is migrated.", "Mirrors in the mirrorlist are unaffected."] },
  { id: 4, box: "inbox", from: "Jonah Park", subject: "Photos from the Presidio walk", date: "Yesterday", unread: true,
    body: ["Uploaded the set from Saturday. The fog rolling under the bridge came out amazing.", "Want to use one as a wallpaper candidate?", "J."] },
  { id: 5, box: "inbox", from: "Quickshell", subject: "Your issue #812 was closed", date: "Thursday", unread: false,
    body: ["The fix for layer surface masks with fractional scaling has landed in master.", "It will ship in the next tagged release."] },
  { id: 6, box: "inbox", from: "Rosa Alvarez", subject: "Font hinting on 1x displays", date: "Wednesday", unread: false,
    body: ["I compared hintslight and hintnone on a 1080p panel.", "hintslight keeps Inter crisper at 13px, so I'd keep your default."] },
  { id: 7, box: "sent", from: "You", subject: "Re: Liquid Glass review notes", date: "6:40 PM", unread: false, body: ["12ms it is. Pushing shortly."] },
];
const BOXES = [["inbox", "Inbox", "envelope"], ["vip", "VIP", "star"], ["flagged", "Flagged", "flag"], ["drafts", "Drafts", "doc"], ["sent", "Sent", "paperplane"]];

function openMail() {
  const st = { box: "inbox", sel: MSGS[1].id };
  const sidebar = h("div");
  const list = h("div.mail-list");
  const reader = h("div.mail-reader");
  const title = h("div.title");
  const flagBtn = tb("flag", { title: "Flag", click: () => { const m = cur(); if (m) { m.flagged = !m.flagged; render(); } } });
  const win = createWindow({
    app: "mail", w: 1120, h: 680, sidebar, sidebarWidth: 200, className: "mail", content: h("div.mail-split", list, reader),
    toolbar: [title, h("div.grow"), pill(tb("compose", { title: "New Message", click: compose })),
      pill(tb("archive", { title: "Archive", click: () => remove() }), tb("trash", { title: "Delete", click: () => remove() })),
      pill(tb("reply", { title: "Reply", click: compose }), tb("reply-all", { title: "Reply All" }), tb("forward-mail", { title: "Forward" })),
      pill(flagBtn), h("label.pill.search", sym("search"), h("input", { placeholder: "Search" }))],
  });
  [list, reader].forEach((el) => el.addEventListener("scroll", () => win.main.classList.toggle("scrolled", el.scrollTop > 2), { passive: true }));

  const inBox = () => MSGS.filter((m) => (st.box === "flagged" ? m.flagged : st.box === "vip" ? ["Maya Chen", "Jonah Park"].includes(m.from) : m.box === st.box));
  const cur = () => MSGS.find((m) => m.id === st.sel);

  function render() {
    const unread = MSGS.filter((m) => m.box === "inbox" && m.unread).length;
    sidebar.replaceChildren(h("div.sec", "Favourites"), ...BOXES.map(([k, label, icon]) =>
      h("div.side-row", { className: `side-row ${st.box === k ? "sel" : ""}`, on: { click: () => { st.box = k; st.sel = inBox()[0]?.id; render(); } } }, sym(icon), label,
        k === "inbox" && unread ? h("span.count", String(unread)) : null)),
      h("div.sec", "Golden"), ...[["Archive", "archive"], ["Junk", "xmark"], ["Trash", "trash"]].map(([l, i]) => h("div.side-row", sym(i), l)));
    const msgs = inBox();
    const box = BOXES.find((b) => b[0] === st.box);
    title.replaceChildren(h("div.stack", box[1], h("span.subtitle", `${msgs.length} messages${st.box === "inbox" ? `, ${unread} unread` : ""}`)));
    list.replaceChildren(...msgs.map((m) => {
      const row = h("div.mrow", { className: `mrow ${m.id === st.sel ? "sel" : ""} ${m.unread ? "unread" : ""}`, on: { click: () => { st.sel = m.id; m.unread = false; render(); } } },
        h("span.dot"), h("div.m-body",
          h("div.m-top", h("b", m.from), m.flagged ? h("span.m-flag", sym("flag")) : null, h("span.m-date", m.date)),
          h("div.m-subj", m.subject), h("div.m-prev", m.body.join(" "))));
      row.dataset.id = m.id;
      return row;
    }));
    flagBtn.classList.toggle("on", !!cur()?.flagged);
    renderReader();
  }

  let shown = null;
  function renderReader() {
    const m = cur();
    if (!m) { reader.replaceChildren(h("div.m-empty", "No Message Selected")); shown = null; return; }
    if (shown === m.id) return;
    shown = m.id;
    reader.replaceChildren(h("article",
      h("header", avatar(m.from, 42), h("div.who", h("b", m.from), h("span", "To: You")), h("span.when", m.date)),
      h("h1", m.subject), ...m.body.map((p) => h("p", p))));
    reader.scrollTop = 0;
    animate(reader.firstChild, [{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "none" }], "snappy");
  }

  async function remove() {
    const m = cur(); if (!m) return;
    const row = list.querySelector(`[data-id="${m.id}"]`);
    const next = inBox()[inBox().indexOf(m) + 1] ?? inBox()[inBox().indexOf(m) - 1];
    if (row) {
      row.style.overflow = "hidden";
      await row.animate([{ height: `${row.offsetHeight}px`, opacity: 1 }, { height: "0px", opacity: 0, paddingTop: 0, paddingBottom: 0 }], { duration: 260, easing: "cubic-bezier(.3,0,.2,1)", fill: "forwards" }).finished;
    }
    MSGS.splice(MSGS.indexOf(m), 1);
    st.sel = next?.id;
    render();
  }

  function compose() {
    const re = cur();
    const to = h("input", { value: re && re.from !== "You" ? re.from : "" });
    const subj = h("input", { value: re ? `Re: ${re.subject.replace(/^Re: /, "")}` : "" });
    const body = h("textarea", { placeholder: "" });
    const cw = createWindow({
      app: "mail", w: 620, h: 460, className: "mail-compose",
      toolbar: [h("div.title", "New Message"), h("div.grow"), pill(tb("paperplane", { title: "Send", click: send }))],
      content: h("div.compose", h("label", h("span", "To:"), to), h("label", h("span", "Subject:"), subj), body),
    });
    setTimeout(() => (to.value ? body : to).focus(), 60);
    async function send() {
      cw.el.style.pointerEvents = "none";
      await cw.el.animate([{ transform: "none", opacity: 1 }, { transform: "translateY(-40px) scale(.9)", opacity: 1, offset: 0.35 }, { transform: "translate(30vw, -80vh) scale(.2) rotate(-8deg)", opacity: 0 }],
        { duration: 700, easing: "cubic-bezier(.5,0,.2,1)", fill: "forwards" }).finished;
      MSGS.push({ id: Date.now(), box: "sent", from: "You", subject: subj.value || "(No Subject)", date: "Now", body: [body.value || " "] });
      cw.close();
      render();
      bus.emit("notify", { app: "mail", title: "Message Sent", body: subj.value || "(No Subject)" });
    }
  }

  render();
  return win;
}

registerApp("mail", openMail, {
  Mailbox: [{ label: "Get All New Mail", kbd: "⇧⌘N" }, "-", { label: "Go To", submenu: BOXES.map(([, l, i]) => ({ label: l, icon: i })) }],
  Message: [{ label: "Send Again", disabled: true }, { label: "Reply", kbd: "⌘R" }, { label: "Reply All", kbd: "⇧⌘R" }, { label: "Forward", kbd: "⇧⌘F" }, "-", { label: "Flag", icon: "flag" }, { label: "Mark as Unread", kbd: "⇧⌘U" }],
});
