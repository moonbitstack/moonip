/* The two interactive areas call the library built to JavaScript. Nothing on this
   site re-implements a decision the library already makes: every value shown comes
   back from `engine/moonip.js` as JSON. */

const engine = import("../engine/moonip.js").catch(() => null);

function cellRow(container, binary, options = {}) {
  const { mask, family } = options;
  container.innerHTML = "";
  container.classList.toggle("long", binary.length > 32);
  for (let i = 0; i < binary.length; i += 1) {
    const bit = document.createElement("i");
    bit.className = "bit " + (family === "v6" ? "six" : "four");
    if (binary[i] === "1") bit.classList.add("one");
    if (typeof mask === "number" && i >= mask) bit.classList.add("host");
    bit.textContent = binary[i];
    container.append(bit);
  }
}

function tag(text, kind) {
  const span = document.createElement("span");
  span.className = "tag" + (kind ? " " + kind : "");
  span.textContent = text;
  return span;
}

function renderList(container, parts, summary) {
  container.innerHTML = "";
  if (summary) {
    const line = document.createElement("p");
    line.className = "hint";
    line.style.margin = "0 0 8px";
    line.textContent = summary;
    container.append(line);
  }
  parts.forEach((part, index) => {
    const row = document.createElement("div");
    row.className = "row";
    const count = document.createElement("span");
    count.className = "idx";
    count.textContent = String(index + 1).padStart(2, "0");
    const text = document.createElement("span");
    text.textContent = part;
    row.append(count, text);
    container.append(row);
  });
  if (parts.length === 0) {
    const row = document.createElement("div");
    row.className = "row";
    row.textContent = "nothing left";
    container.append(row);
  }
}

async function read(json) {
  const mod = await engine;
  if (!mod) return null;
  try {
    return JSON.parse(json);
  } catch {
    return { ok: false, error: "the engine gave something that was not JSON" };
  }
}

function missing(container) {
  container.textContent = "the compiled engine is not here; build it with moon build --target js src/examples/browser";
}

/* ---------- the probe on the home page ---------- */

async function runProbe(form) {
  const input = form.querySelector("#probe-input");
  const answer = document.querySelector("#probe-answer");
  const tags = document.querySelector("#probe-tags");
  const bits = document.querySelector("#probe-bits");
  if (!input || !answer) return;
  const mod = await engine;
  if (!mod) {
    missing(answer);
    return;
  }
  const result = JSON.parse(mod.probe(input.value));
  if (!result.ok) {
    answer.textContent = "refused: " + result.error;
    tags.innerHTML = "";
    bits.innerHTML = "";
    return;
  }
  answer.textContent =
    result.text + "  " + result.family + " /" + result.bits + "  " + result.bytes;
  tags.innerHTML = "";
  tags.append(tag(result.family, result.family));
  for (const flag of result.flags) tags.append(tag(flag));
  cellRow(bits, result.binary, { family: result.family });
}

const probeForm = document.querySelector("#probe-form");
if (probeForm) {
  probeForm.addEventListener("submit", (event) => {
    event.preventDefault();
    runProbe(probeForm);
  });
  runProbe(probeForm);
}

/* ---------- the explorer ---------- */

function bind(id, handler) {
  const el = document.querySelector(id);
  if (el) handler(el);
}

bind("#ex-form", (form) => {
  const input = form.querySelector("#ex-address");
  const answer = document.querySelector("#ex-answer");
  const tags = document.querySelector("#ex-tags");
  const bits = document.querySelector("#ex-bits");
  const details = document.querySelector("#ex-details");
  const run = async () => {
    const mod = await engine;
    if (!mod) return missing(answer);
    const result = JSON.parse(mod.probe(input.value));
    if (!result.ok) {
      answer.textContent = "refused: " + result.error;
      tags.innerHTML = "";
      bits.innerHTML = "";
      details.innerHTML = "";
      return;
    }
    answer.textContent = result.text;
    tags.innerHTML = "";
    tags.append(tag(result.family, result.family));
    for (const flag of result.flags) tags.append(tag(flag));
    cellRow(bits, result.binary, { family: result.family });
    details.innerHTML = "";
    for (const [name, value] of [
      ["exploded", result.exploded],
      ["bytes", result.bytes],
      ["reverse", result.reverse],
    ]) {
      const row = document.createElement("div");
      row.className = "row";
      const key = document.createElement("span");
      key.className = "idx";
      key.textContent = name;
      const val = document.createElement("span");
      val.textContent = value;
      row.append(key, val);
      details.append(row);
    }
  };
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
});

bind("#ex-split", (panel) => {
  const input = panel.querySelector("#split-prefix");
  const slider = panel.querySelector("#split-bits");
  const value = panel.querySelector("#split-value");
  const list = panel.querySelector("#split-list");
  const run = async () => {
    const mod = await engine;
    if (!mod) return;
    const bits = Number(slider.value);
    const result = JSON.parse(mod.split(input.value, bits));
    if (!result.ok) {
      renderList(list, [], "refused: " + result.error);
      return;
    }
    renderList(list, result.parts, result.count > result.parts.length
      ? "showing " + result.parts.length + " of " + result.count
      : result.count + (result.count === 1 ? " block" : " blocks"));
  };
  const sync = () => {
    value.textContent = "/" + slider.value;
    run();
  };
  slider.addEventListener("input", sync);
  input.addEventListener("change", run);
  sync();
});

bind("#ex-range", (panel) => {
  const first = panel.querySelector("#range-first");
  const last = panel.querySelector("#range-last");
  const list = panel.querySelector("#range-list");
  const run = async () => {
    const mod = await engine;
    if (!mod) return;
    const result = JSON.parse(mod.range(first.value, last.value));
    if (!result.ok) {
      renderList(list, [], "refused: " + result.error);
      return;
    }
    renderList(list, result.parts, result.parts.length + " blocks");
  };
  panel.querySelector("form").addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
});

bind("#ex-merge", (panel) => {
  const input = panel.querySelector("#merge-input");
  const list = panel.querySelector("#merge-list");
  const run = async () => {
    const mod = await engine;
    if (!mod) return;
    const result = JSON.parse(mod.merge(input.value));
    if (!result.ok) {
      renderList(list, [], "refused: " + result.error);
      return;
    }
    renderList(list, result.parts, result.parts.length + " blocks");
  };
  panel.querySelector("form").addEventListener("submit", (event) => {
    event.preventDefault();
    run();
  });
  run();
});

/* ---------- the reference filter ---------- */

bind("#q", (box) => {
  const hits = document.querySelector("#hits");
  const empty = document.querySelector("#empty");
  const items = Array.from(document.querySelectorAll(".item"));
  const total = items.length;
  const filter = () => {
    const needle = box.value.trim().toLowerCase();
    let shown = 0;
    for (const item of items) {
      const match = needle === "" || item.textContent.toLowerCase().includes(needle);
      item.classList.toggle("hidden", !match);
      if (match) shown += 1;
    }
    for (const group of document.querySelectorAll(".group")) {
      const any = group.querySelector(".item:not(.hidden)") !== null;
      group.classList.toggle("hidden", !any);
    }
    if (hits) hits.textContent = needle === "" ? total + " entries" : shown + " of " + total;
    if (empty) empty.classList.toggle("hidden", shown !== 0);
  };
  box.addEventListener("input", filter);
  filter();
});
