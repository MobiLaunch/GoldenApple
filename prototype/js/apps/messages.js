// Messages: pinned conversations, chat bubbles with tails, a floating glass
// composer; sent bubbles spring up from the field, then the other side "types".
import { h, sym, avatar, animate, bus, wait } from "../util.js";
import { createWindow, activeWindow, pill, tb } from "../wm.js";
import { registerApp } from "../apps.js";

const CHATS = [
  { name: "Maya Chen", pinned: true, msgs: [["them", "Did you see the new Control Center build?"], ["me", "Just pushed it! Modules stagger in now"], ["them", "The spring on the Wi-Fi panel is so good 😍"], ["them", "Can we do the same for Bluetooth?"]],
    replies: ["Yes!! Ship it", "Looks amazing on my laptop", "One sec, testing on the external display"] },
  { name: "Jonah Park", pinned: true, msgs: [["them", "Fog's rolling in at Crissy Field"], ["them", "Perfect wallpaper weather"], ["me", "Grab a shot of the tower!"]],
    replies: ["On it 📸", "Sending the RAW files later", "Ha, the tower is completely hidden"] },
  { name: "Design Crew", pinned: true, msgs: [["them", "Reminder: review at 10"], ["me", "I'll bring the motion curves"]], replies: ["👍", "See you there", "Bring coffee ☕️"] },
  { name: "Rosa Alvarez", msgs: [["them", "hintslight wins on 1x panels"], ["me", "Makes sense. Keeping it"], ["them", "Also Inter's cv05 looks great in menus"]], replies: ["Agreed", "Sending screenshots", "🙌"] },
  { name: "Leo Martins", msgs: [["me", "Want to try the ISO this weekend?"], ["them", "Absolutely. USB stick ready"]], replies: ["Booting now…", "It autologged straight in, nice", "The Dock bounce!"] },
];

function openMessages() {
  let cur = CHATS[0];
  const sidebar = h("div");
  const thread = h("div.thread");
  const field = h("input", { placeholder: "Message", spellcheck: true });
  const composer = h("div.composer", h("button.cm-plus.glass-regular", sym("plus")),
    h("label.cm-field.glass-regular", field, h("span.cm-mic", sym("mic"))));
  const who = h("div.title.chat-title");
  const win = createWindow({
    app: "messages", w: 960, h: 640, sidebar, sidebarWidth: 270, className: "messages", content: h("div.chat", thread, composer),
    toolbar: [h("div.grow"), who, h("div.grow"), pill(tb("video", { title: "Video" }), tb("phone", { title: "Audio" })), pill(tb("info", { title: "Details" }))],
  });
  thread.addEventListener("scroll", () => win.main.classList.toggle("scrolled", thread.scrollTop > 2), { passive: true });

  function renderSide() {
    const pinned = CHATS.filter((c) => c.pinned);
    sidebar.replaceChildren(
      h("label.side-search", sym("search"), h("input", { placeholder: "Search" })),
      h("div.pins", pinned.map((c) => h("button.pin", { className: `pin ${c === cur ? "sel" : ""}`, on: { click: () => select(c) } }, avatar(c.name, 56), h("span", c.name.split(" ")[0])))),
      ...CHATS.filter((c) => !c.pinned).map((c) => {
        const last = c.msgs.at(-1);
        return h("div.convo", { className: `convo ${c === cur ? "sel" : ""}`, on: { click: () => select(c) } }, avatar(c.name, 40),
          h("div.c-body", h("div.c-top", h("b", c.name), h("span", "9:41 PM")), h("div.c-prev", last[1])));
      }));
  }
  function select(c) { cur = c; renderSide(); renderThread(true); }

  function bubble(side, text, tail) {
    const emojiOnly = /^\p{Extended_Pictographic}+$/u.test(text.replace(/\s/g, ""));
    return h("div.bub", { className: `bub ${side} ${tail ? "tail" : ""} ${emojiOnly ? "emoji" : ""}` }, text);
  }
  function renderThread(fresh) {
    who.replaceChildren(avatar(cur.name, 26), h("span", cur.name));
    const kids = [h("div.stamp", h("b", "Today"), " 9:41 PM")];
    cur.msgs.forEach(([side, text], i) => kids.push(bubble(side, text, cur.msgs[i + 1]?.[0] !== side)));
    if (cur.msgs.at(-1)[0] === "me") kids.push(h("div.receipt", "Delivered"));
    thread.replaceChildren(...kids);
    thread.scrollTop = thread.scrollHeight;
    if (fresh) animate(thread, [{ opacity: 0 }, { opacity: 1 }], "smooth");
  }

  let replyIdx = 0;
  async function send() {
    const text = field.value.trim();
    if (!text) return;
    field.value = "";
    const convo = cur;
    convo.msgs.push(["me", text]);
    renderThread();
    const b = thread.querySelectorAll(".bub.me");
    // The bubble lifts out of the composer.
    animate(b[b.length - 1], [{ transform: "translateY(46px) scale(.86)", opacity: 0.2, transformOrigin: "bottom right" }, { transform: "none", opacity: 1, transformOrigin: "bottom right" }], "bouncy");
    renderSide();
    await wait(900);
    if (cur !== convo) return;
    const typing = h("div.bub.them.tail.typing", h("i"), h("i"), h("i"));
    thread.querySelector(".receipt")?.replaceChildren("Read 9:41 PM");
    thread.append(typing);
    thread.scrollTop = thread.scrollHeight;
    animate(typing, [{ transform: "scale(.6)", opacity: 0, transformOrigin: "bottom left" }, { transform: "none", opacity: 1, transformOrigin: "bottom left" }], "bouncy");
    await wait(1500);
    const reply = convo.replies[replyIdx++ % convo.replies.length];
    convo.msgs.push(["them", reply]);
    if (cur === convo) {
      renderThread();
      const last = thread.querySelector(".bub.them:last-of-type");
      animate(last, [{ transform: "scale(.8)", opacity: 0, transformOrigin: "bottom left" }, { transform: "none", opacity: 1, transformOrigin: "bottom left" }], "bouncy");
    }
    renderSide();
    if (activeWindow() !== win) bus.emit("notify", { app: "messages", title: convo.name, body: reply });
  }
  field.addEventListener("keydown", (e) => { if (e.key === "Enter") send(); });

  renderSide();
  renderThread();
  setTimeout(() => field.focus(), 80);
  return win;
}

registerApp("messages", openMessages, {
  Conversation: [{ label: "Pin", icon: "pin" }, { label: "Hide Alerts", icon: "bell" }, "-", { label: "Delete Conversation…", icon: "trash" }],
});
