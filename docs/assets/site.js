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

/* ---------- start ---------- */

measureHeader();
countHops();
addEventListener("scroll", countHops, { passive: true });
addEventListener("resize", () => {
  measureHeader();
  countHops();
}, { passive: true });
