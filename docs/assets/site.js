/* Everything on this site that is not prose is either measured from the page or
   answered by the library compiled to JavaScript. Nothing here re-implements a
   decision the library already makes. */

const engine = import("../engine/moonip.js").catch(() => null);

/* ---------- the header is a real header ---------- */

function oneComplementsSum(text) {
  let sum = 0;
  for (let i = 0; i < text.length; i += 2) {
    const hi = text.charCodeAt(i) & 0xff;
    const lo = i + 1 < text.length ? text.charCodeAt(i + 1) & 0xff : 0;
    sum += (hi << 8) | lo;
    while (sum > 0xffff) sum = (sum & 0xffff) + (sum >>> 16);
  }
  return ~sum & 0xffff;
}

function fnv1a(text) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i) & 0xff;
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash & 0xffff;
}

function hex4(value) {
  return "0x" + value.toString(16).toUpperCase().padStart(4, "0");
}

function measureHeader() {
  const body = document.body.innerText;
  const sum = hex4(oneComplementsSum(body));
  const set = (id, value) => {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  };
  set("hdr-len", hex4(Math.min(document.documentElement.scrollHeight, 0xffff)));
  set("hdr-id", hex4(fnv1a(body)));
  set("hdr-chk", sum);
  set("foot-chk", sum.replace("0x", ""));
}

/* The hop limit counts the sections still ahead, the way a TTL counts the hops
   left to a destination. */
function countHops() {
  const ttl = document.getElementById("hdr-ttl");
  if (!ttl) return;
  const sections = Array.from(document.querySelectorAll(".row, .step"));
  const mark = window.scrollY + 90;
  let passed = 0;
  for (const section of sections) {
    if (section.getBoundingClientRect().bottom + window.scrollY < mark) passed += 1;
  }
  ttl.textContent = String(Math.max(0, sections.length - passed)).padStart(2, "0");
  // The fragment offset counts eight-byte units from the start of the datagram,
  // which is exactly how far down this page the reader has got.
  const off = document.getElementById("hdr-off");
  if (off) off.textContent = hex4(Math.floor(window.scrollY / 8) & 0x1fff);
}

/* ---------- bit cells ---------- */

function drawBits(container, binary, options = {}) {
  const { mask, family } = options;
  container.innerHTML = "";
  for (let i = 0; i < binary.length; i += 1) {
    const bit = document.createElement("i");
    bit.className = "b";
    if (binary[i] === "1") bit.classList.add("one");
    if (family === "v6") bit.classList.add("v6");
    if (family === "v4") bit.classList.add("v4");
    if (typeof mask === "number" && i >= mask) bit.classList.add("host");
    bit.textContent = binary[i];
    container.append(bit);
  }
}

/* ---------- small DOM helpers ---------- */

function tag(text, kind) {
  const span = document.createElement("span");
  span.className = "tag" + (kind ? " " + kind : "");
  span.textContent = text;
  return span;
}

function fillKv(list, pairs) {
  list.innerHTML = "";
  for (const [key, value] of pairs) {
    const dt = document.createElement("dt");
    dt.textContent = key;
    const dd = document.createElement("dd");
    dd.textContent = value;
    list.append(dt, dd);
  }
}

function fillBlocks(container, parts, summary) {
  container.innerHTML = "";
  if (summary) {
    const line = document.createElement("div");
    line.className = "r";
    line.style.color = "var(--ink-2)";
    line.textContent = summary;
    container.append(line);
  }
  parts.forEach((part, index) => {
    const row = document.createElement("div");
    row.className = "r";
    const count = document.createElement("span");
    count.className = "i";
    count.textContent = String(index + 1).padStart(2, "0");
    const text = document.createElement("span");
    text.textContent = part;
    row.append(count, text);
    container.append(row);
  });
}

async function compiled() {
  const mod = await engine;
  return mod || null;
}

/* ---------- the probe on the home page ---------- */

const probeForm = document.getElementById("probe-form");
if (probeForm) {
  const input = document.getElementById("probe-input");
  const answer = document.getElementById("probe-answer");
  const tags = document.getElementById("probe-tags");
  const kv = document.getElementById("probe-kv");
  const bits = document.getElementById("probe-bits");

  const run = async () => {
    const mod = await compiled();
    if (!mod) {
      answer.textContent = "engine missing: build it with moon build --target js src/examples/browser";
      return;
    }
    const result = JSON.parse(mod.probe(input.value));
    if (!result.ok) {
      answer.textContent = "refused";
      tags.innerHTML = "";
      fillKv(kv, [["reason", result.error]]);
      bits.innerHTML = "";
      return;
    }
    answer.textContent = result.text;
    tags.innerHTML = "";
    tags.append(tag(result.family, result.family));
    for (const flag of result.flags) tags.append(tag(flag));
    fillKv(kv, [
      ["exploded", result.exploded],
      ["bytes", result.bytes],
      ["reverse", result.reverse],
    ]);
    drawBits(bits, result.binary, { family: result.family });
  };

  probeForm.addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
}

/* ---------- explorer ---------- */

const exForm = document.getElementById("ex-form");
if (exForm) {
  const input = document.getElementById("ex-address");
  const answer = document.getElementById("ex-answer");
  const tags = document.getElementById("ex-tags");
  const bits = document.getElementById("ex-bits");
  const kv = document.getElementById("ex-kv");

  const run = async () => {
    const mod = await compiled();
    if (!mod) return;
    const result = JSON.parse(mod.probe(input.value));
    if (!result.ok) {
      answer.textContent = "refused: " + result.error;
      tags.innerHTML = "";
      kv.innerHTML = "";
      bits.innerHTML = "";
      return;
    }
    answer.textContent = result.text;
    tags.innerHTML = "";
    tags.append(tag(result.family, result.family));
    for (const flag of result.flags) tags.append(tag(flag));
    fillKv(kv, [
      ["exploded", result.exploded],
      ["bytes", result.bytes],
      ["reverse", result.reverse],
    ]);
    drawBits(bits, result.binary, { family: result.family });
  };
  exForm.addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
}

const splitPanel = document.getElementById("ex-split");
if (splitPanel) {
  const input = splitPanel.querySelector("#split-prefix");
  const slider = splitPanel.querySelector("#split-bits");
  const value = splitPanel.querySelector("#split-value");
  const list = splitPanel.querySelector("#split-list");

  const run = async () => {
    const mod = await compiled();
    if (!mod) return;
    const result = JSON.parse(mod.split(input.value, Number(slider.value)));
    if (!result.ok) {
      fillBlocks(list, [], "refused: " + result.error);
      return;
    }
    fillBlocks(
      list,
      result.parts,
      result.count > result.parts.length
        ? result.parts.length + " of " + result.count + " blocks"
        : result.count + (result.count === 1 ? " block" : " blocks"),
    );
  };
  slider.addEventListener("input", () => {
    value.textContent = "/" + slider.value;
    run();
  });
  input.addEventListener("change", run);
  value.textContent = "/" + slider.value;
  run();
}

const rangePanel = document.getElementById("ex-range");
if (rangePanel) {
  const first = rangePanel.querySelector("#range-first");
  const last = rangePanel.querySelector("#range-last");
  const list = rangePanel.querySelector("#range-list");
  const run = async () => {
    const mod = await compiled();
    if (!mod) return;
    const result = JSON.parse(mod.range(first.value, last.value));
    if (!result.ok) {
      fillBlocks(list, [], "refused: " + result.error);
      return;
    }
    fillBlocks(list, result.parts, result.parts.length + " blocks");
  };
  rangePanel.querySelector("form").addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
}

const mergePanel = document.getElementById("ex-merge");
if (mergePanel) {
  const input = mergePanel.querySelector("#merge-input");
  const list = mergePanel.querySelector("#merge-list");
  const run = async () => {
    const mod = await compiled();
    if (!mod) return;
    const result = JSON.parse(mod.merge(input.value));
    if (!result.ok) {
      fillBlocks(list, [], "refused: " + result.error);
      return;
    }
    fillBlocks(list, result.parts, result.parts.length + " blocks");
  };
  mergePanel.querySelector("form").addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
}

/* ---------- reference filter ---------- */

const filterBox = document.getElementById("q");
if (filterBox) {
  const hits = document.getElementById("hits");
  const empty = document.getElementById("empty");
  const items = Array.from(document.querySelectorAll(".item"));
  const total = items.length;
  const apply = () => {
    const needle = filterBox.value.trim().toLowerCase();
    let shown = 0;
    for (const item of items) {
      const match = needle === "" || item.textContent.toLowerCase().includes(needle);
      item.classList.toggle("hidden", !match);
      if (match) shown += 1;
    }
    for (const group of document.querySelectorAll(".ref-group")) {
      const any = group.querySelector(".item:not(.hidden)") !== null;
      group.classList.toggle("hidden", !any);
    }
    if (hits) hits.textContent = needle === "" ? total + " entries" : shown + " / " + total;
    if (empty) empty.classList.toggle("hidden", shown !== 0);
  };
  filterBox.addEventListener("input", apply);
  apply();
}

/* ---------- the header map ---------- */

const headerMap = document.getElementById("hmap");
if (headerMap) {
  const out = document.getElementById("hmap-out");
  const rest = out.innerHTML;
  const show = (field) => {
    out.innerHTML = "";
    const name = document.createElement("b");
    name.textContent = field.dataset.what || "";
    const why = document.createElement("span");
    why.className = "api";
    why.textContent = field.dataset.why || "";
    out.append(name, why);
  };
  const reset = () => {
    out.innerHTML = rest;
  };
  for (const field of headerMap.querySelectorAll(".hmap-f")) {
    field.addEventListener("mouseenter", () => show(field));
    field.addEventListener("focus", () => show(field));
    field.addEventListener("mouseleave", reset);
    field.addEventListener("blur", reset);
  }
}

/* ---------- back to the top ---------- */

const topLink = document.getElementById("totop");
if (topLink) {
  const mark = () => topLink.classList.toggle("on", window.scrollY > 300);
  addEventListener("scroll", mark, { passive: true });
  mark();
}

/* A page whose theme was chosen on another page still tells the browser what
   colour to paint the chrome around it. */
const chosenTheme = document.documentElement.dataset.theme;
if (chosenTheme) {
  for (const meta of document.querySelectorAll('meta[name="theme-color"]')) {
    meta.setAttribute("content", chosenTheme === "dark" ? "#070809" : "#e6e2d6");
  }
}

/* ---------- day / night ----------
   The switch writes the choice on the root, where the stylesheet already knows how
   to read it, and keeps it for the other pages. The system preference is what the
   page uses until somebody says otherwise. */

const themeSwitch = document.querySelector(".themesw");
if (themeSwitch) {
  const root = document.documentElement;
  const system = () =>
    matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  const current = () => root.dataset.theme || system();

  const paint = () => {
    const mode = current();
    const target = mode === "dark" ? "day" : "night";
    themeSwitch.dataset.mode = mode;
    themeSwitch.setAttribute("aria-label", "Switch to " + target);
    themeSwitch.title = "Switch to " + target;
    const colour = mode === "dark" ? "#070809" : "#e6e2d6";
    for (const meta of document.querySelectorAll('meta[name="theme-color"]')) {
      meta.setAttribute("content", colour);
    }
  };

  themeSwitch.addEventListener("click", () => {
    root.dataset.theme = current() === "dark" ? "light" : "dark";
    try {
      localStorage.setItem("moonip.theme", root.dataset.theme);
    } catch (error) {
      /* storage can be denied; the choice still holds for this page */
    }
    paint();
  });

  // While no choice has been made, the button follows the system as it changes.
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
    if (!root.dataset.theme) paint();
  });

  paint();
}

/* ---------- fragmentation ----------
   A datagram of 47 bytes, cut into six fragments on the eight-byte boundaries the
   header asks for, and handed to the buffer in the order the wire chose. The scroll
   decides how many have arrived. Nothing here is random: the offsets, the lengths
   and the more-fragments flag are the arithmetic RFC 791 prescribes, and the bytes
   are the ASCII of the sentence the exhibit is about. */

const FRAGMENTS = [
  { no: 1, byte: 0, len: 8, mf: 1, hex: "74 68 65 20 6f 66 66 73", order: 1 },
  { no: 2, byte: 8, len: 8, mf: 1, hex: "65 74 20 73 61 79 73 20", order: 3 },
  { no: 3, byte: 16, len: 8, mf: 1, hex: "77 68 65 72 65 3b 20 74", order: 5 },
  { no: 4, byte: 24, len: 8, mf: 1, hex: "68 65 20 6c 65 6e 67 74", order: 0 },
  { no: 5, byte: 32, len: 8, mf: 1, hex: "68 20 73 61 79 73 20 68", order: 4 },
  { no: 6, byte: 40, len: 7, mf: 0, hex: "6f 77 20 6d 75 63 68", order: 2 },
];

const PAYLOAD = "the offset says where; the length says how much";

const fragScroll = document.getElementById("frag");
if (fragScroll) {
  const stage = fragScroll.querySelector(".frag-stage");
  const bar = fragScroll.querySelector(".frag-bar");
  const axis = fragScroll.querySelector(".frag-axis");
  const text = fragScroll.querySelector(".frag-text");
  const wire = fragScroll.querySelector(".frag-queue");
  const list = fragScroll.querySelector(".frag-list");
  const stat = fragScroll.querySelector(".frag-stat");

  for (let i = 0; i < PAYLOAD.length; i += 1) {
    const cell = document.createElement("i");
    bar.append(cell);
  }

  for (let byte = 0; byte < PAYLOAD.length; byte += 8) {
    const tick = document.createElement("span");
    tick.textContent = String(byte);
    tick.style.left = (byte / PAYLOAD.length) * 100 + "%";
    axis.append(tick);
  }

  const byArrival = [...FRAGMENTS].sort((a, b) => a.order - b.order);

  for (const fragment of byArrival) {
    const card = document.createElement("div");
    card.className = "frag-card";
    card.dataset.no = String(fragment.no);
    card.style.setProperty("--k", fragment.order);
    card.style.setProperty("--off", fragment.byte);
    card.style.setProperty("--len", fragment.len);
    const number = document.createElement("b");
    number.textContent = "#" + fragment.no;
    const offset = document.createElement("i");
    offset.textContent = "off " + fragment.byte;
    card.append(number, offset);
    wire.append(card);

    const row = document.createElement("li");
    row.dataset.no = String(fragment.no);
    row.innerHTML =
      "<b>#" + fragment.no + "</b>" +
      "<span>" + (fragment.mf ? "MF 1" : "MF 0") + "</span>" +
      "<span>" + fragment.len + " B</span>" +
      "<span>" + fragment.byte + "–" + (fragment.byte + fragment.len - 1) + "</span>" +
      '<span class="hex">' + fragment.hex + "</span>";
    list.append(row);
  }

  const chars = [];
  for (const character of PAYLOAD) {
    const span = document.createElement("i");
    span.textContent = character;
    if (character === " ") span.classList.add("space");
    text.append(span);
    chars.push(span);
  }

  const note = document.createElement("p");
  note.className = "frag-empty";
  note.textContent = "wire clear · six of six delivered";
  wire.append(note);

  const thresholds = FRAGMENTS.map((f) => 0.06 + f.order * 0.145);
  const cards = Array.from(wire.querySelectorAll(".frag-card"));
  const rows = Array.from(list.querySelectorAll("li"));

  const arrival = (progress) => {
    const arrived = new Set(
      FRAGMENTS.filter((f) => progress >= thresholds[FRAGMENTS.indexOf(f)]).map((f) => f.no),
    );
    for (const card of cards) card.classList.toggle("in", arrived.has(Number(card.dataset.no)));
    for (const row of rows) row.classList.toggle("in", arrived.has(Number(row.dataset.no)));

    let bytes = 0;
    const covered = new Array(PAYLOAD.length).fill(false);
    for (const fragment of FRAGMENTS) {
      if (!arrived.has(fragment.no)) continue;
      bytes += fragment.len;
      for (let i = 0; i < fragment.len; i += 1) covered[fragment.byte + i] = true;
    }
    for (let i = 0; i < chars.length; i += 1) chars[i].classList.toggle("got", covered[i]);

    let holes = 0;
    let inside = false;
    for (const filled of covered) {
      if (!filled && !inside) {
        holes += 1;
        inside = true;
      } else if (filled) {
        inside = false;
      }
    }
    const done = arrived.size === FRAGMENTS.length;
    note.classList.toggle("on", done);
    stat.innerHTML = done
      ? "<b>" + PAYLOAD.length + " / " + PAYLOAD.length + "</b> bytes · <b>0</b> holes · reassembled"
      : "<b>" + bytes + " / " + PAYLOAD.length + "</b> bytes · <b>" + arrived.size + "</b> / " +
        FRAGMENTS.length + " fragments · <b>" + holes + "</b> hole" + (holes === 1 ? "" : "s");
  };

  const update = () => {
    const rect = fragScroll.getBoundingClientRect();
    const span = rect.height - (window.innerHeight - 44);
    const progress = span <= 0 ? 1 : Math.min(1, Math.max(0, (44 - rect.top) / span));
    arrival(progress);
  };

  stage.classList.add("booting");
  arrival(0);
  requestAnimationFrame(() => {
    stage.classList.remove("booting");
    update();
  });
  addEventListener("scroll", update, { passive: true });
  addEventListener("resize", update, { passive: true });
}

/* ---------- the hop walk ----------
   Seven questions, asked in the order the registries list their rows. The first
   one that answers yes is where the packet stops; if none does, the address is
   neither private nor reachable, which only shared address space manages. Every
   answer is read from the compiled library's own flags. */

const TRACE = [
  { key: "unspecified", gate: "is_unspecified", where: "0.0.0.0 · ::", label: "the unspecified address", why: "the bits are all zero: there is no destination here" },
  { key: "loopback", gate: "is_loopback", where: "127.0.0.0/8 · ::1", label: "loopback", why: "the packet would never leave the host" },
  { key: "multicast", gate: "is_multicast", where: "224.0.0.0/4 · ff00::/8", label: "multicast", why: "a group, not a host: delivery is a different question" },
  { key: "link local", gate: "is_link_local", where: "169.254.0.0/16 · fe80::/10", label: "link local", why: "reachable on one link and no further" },
  { key: "site local", gate: "is_site_local", where: "fec0::/10", label: "site local", why: "deprecated by RFC 3879, still listed" },
  { key: "private", gate: "is_private", where: "the registry rows that are not reachable", label: "not globally reachable", why: "inside a block the IANA registry marks off" },
  { key: "global", gate: "is_global", where: "what is left", label: "globally reachable", why: "outside every block either registry claims" },
];

const ladder = document.getElementById("ladder");
if (ladder) {
  const form = document.getElementById("trace-form");
  const input = document.getElementById("trace-input");
  const verdict = document.getElementById("verdict");
  const traced = document.getElementById("trace-addr");
  const hops = Array.from(ladder.querySelectorAll(".hop"));
  let run = 0;

  const idle = () => {
    for (const hop of hops) {
      hop.className = "hop idle";
      hop.querySelector(".res").textContent = "·";
    }
  };

  const say = (state, title, line) => {
    verdict.className = "verdict" + (state ? " " + state : "");
    verdict.innerHTML =
      '<span class="k">verdict</span><b></b><p></p>';
    verdict.querySelector("b").textContent = title;
    verdict.querySelector("p").textContent = line;
  };

  const walk = async () => {
    const token = (run += 1);
    const text = input.value.trim();
    traced.textContent = text;
    idle();
    say("", "reading", "asking the compiler's answers, in order");

    const mod = await compiled();
    if (!mod) {
      say("", "no engine", "build it with moon build --target js src/examples/browser");
      return;
    }
    const result = JSON.parse(mod.probe(text));
    if (!result.ok) {
      say("neither", "no route", "the text is not an address, so there is nothing to ask it");
      traced.textContent = "—";
      return;
    }

    const flags = new Set(result.flags);
    const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;
    let stop = -1;

    for (let index = 0; index < TRACE.length; index += 1) {
      if (token !== run) return;
      const hop = hops[index];
      const yes = flags.has(TRACE[index].key);
      hop.className = "hop " + (yes ? "stop" : "pass");
      hop.querySelector(".res").textContent = yes ? "yes" : "no";
      if (yes) {
        stop = index;
        break;
      }
      if (!calm) await new Promise((resolve) => setTimeout(resolve, 110));
    }
    if (token !== run) return;

    const answered = stop < 0 ? TRACE.length : stop + 1;
    if (stop >= 0) {
      const rung = TRACE[stop];
      say(
        "",
        rung.label,
        "hop " + answered + " of " + TRACE.length + " — " + rung.why +
          (stop === TRACE.length - 1 ? "." : ". Nothing after it is asked."),
      );
    } else {
      say(
        "neither",
        "neither private nor reachable",
        "all " + TRACE.length + " questions answered no: shared address space, 100.64.0.0/10, " +
          "the one block the registry marks as neither",
      );
    }
  };

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    walk();
  });
  for (const chip of document.querySelectorAll(".chips button")) {
    chip.addEventListener("click", () => {
      input.value = chip.dataset.address;
      walk();
    });
  }
  idle();
  walk();
}

/* ---------- start ---------- */

measureHeader();
countHops();
addEventListener("scroll", countHops, { passive: true });
addEventListener("resize", () => {
  measureHeader();
  countHops();
}, { passive: true });
