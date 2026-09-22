# Reports → Appraisals — Month Picker Overlapping / Clipped

**Date:** 2026-08-29
**Component:** Month / "Month View" date picker on the Appraisals report screens
**Affected pages:**
- Reports → Appraisals → **Probation Appraisal Status** (`SELECT MONTH`)
- Reports → Appraisals → **Export Performance** (`MONTH VIEW`)
- Reports → Appraisals → **Export Department Performance** (`MONTH VIEW`)

> **Scope note:** this report was written from the three screenshots. The web
> panel source was not available to inspect, so the exact file paths and class
> names below are marked `<fill in>`. The diagnosis, the 60-second test in §3,
> and the fixes in §4 are all directly actionable.

---

## 1. Symptom

Clicking the month field opens the picker, but only the **year navigation
header** (`«  2026  »`) is visible. The month grid (JAN–DEC) underneath it is
cut off, and the visible sliver sits on top of / behind the controls in the
row below.

Identical behaviour on all three pages — so this is **one shared component or
one shared CSS rule**, not three separate bugs. Fix it once and all three are
fixed.

---

## 2. Why this happens

An absolutely-positioned dropdown that opens *out of* its container has
exactly three common failure modes. All three look like "overlapping" to the
user:

| # | Cause | What you see |
|---|---|---|
| **C1** | An ancestor has `overflow: hidden` (or `auto` / `scroll`) | Panel is **cut off cleanly** at the card/row edge. Most likely here — the cut in all three screenshots is a straight horizontal line. |
| **C2** | Panel's `z-index` is below a later sibling, or it is trapped in a lower stacking context | Panel is **painted behind** the next field/button; you see the other control punch through it. |
| **C3** | Panel is positioned relative to the wrong ancestor (missing `position: relative`, or a `transform` / `filter` / `will-change` on an ancestor creates a new containing block) | Panel appears **offset** — wrong left/top, drifting from the input. |

C1 and C2 often occur together: a Bootstrap card gives you `overflow: hidden`
**and** creates a stacking context.

---

## 3. Confirm which one, in about a minute

Open the page, click the month field so the picker is open, then in DevTools:

**Test A — is it clipped? (C1)**

Select the picker element in the Elements panel and run in the Console:

```js
let el = $0, hits = [];
for (let p = el.parentElement; p; p = p.parentElement) {
  const o = getComputedStyle(p);
  if (o.overflow !== 'visible' || o.overflowX !== 'visible' || o.overflowY !== 'visible') {
    hits.push([p, o.overflow, o.overflowX, o.overflowY]);
  }
}
console.table(hits);
```

Any row that comes back is a clipping ancestor. **That's your culprit for C1** —
note its class (likely `.card`, `.card-body`, `.table-responsive`, or a
custom `.filter-panel`).

**Test B — is it painted behind something? (C2)**

```js
console.log(getComputedStyle($0).zIndex, getComputedStyle($0).position);
```

If `zIndex` is `auto`, `0`, or lower than the sibling that's covering it →
C2.

**Test C — is it mispositioned? (C3)**

```js
let el = $0, hits = [];
for (let p = el.parentElement; p; p = p.parentElement) {
  const s = getComputedStyle(p);
  if (s.transform !== 'none' || s.filter !== 'none' || s.perspective !== 'none' ||
      s.willChange !== 'auto' || s.contain !== 'none') {
    hits.push([p, s.transform, s.filter, s.willChange]);
  }
}
console.table(hits);
```

Any hit creates a new containing block, which breaks `position: absolute`
placement for the dropdown.

---

## 4. Fixes

### 4.1 Recommended — render the picker on `<body>` (fixes C1, C2 and C3 at once)

The most robust fix is to stop nesting the panel inside the card at all.
Every picker library supports this. Use the one that matches your stack:

**bootstrap-datepicker** (the `« 2026 »` header in the screenshots is this
library's `datepicker-months` view):

```js
$('#month_view').datepicker({
  format: 'MM yyyy',
  viewMode: 'months',
  minViewMode: 'months',
  autoclose: true,
  container: 'body'          // <-- the fix
});
```

**flatpickr:**

```js
flatpickr('#month_view', {
  plugins: [new monthSelectPlugin({ shorthand: true, dateFormat: 'Y-m' })],
  appendTo: document.body,   // <-- the fix
  static: false
});
```

**Air Datepicker:**

```js
new AirDatepicker('#month_view', {
  view: 'months',
  minView: 'months',
  container: document.body   // <-- the fix
});
```

**Bootstrap 5 native dropdown:** add `data-bs-container="body"` on the
trigger, or initialise with `{ container: 'body' }`.

> ⚠️ When you move the panel to `body`, make sure your close-on-outside-click
> handler doesn't treat the panel as "outside" the field. Most libraries
> handle this; if you wrote the handler yourself, check it (see §6).

### 4.2 If you cannot re-parent — unclip the ancestor (C1)

Find the ancestor from Test A and let it overflow. **Scope it narrowly** —
do not make `.card { overflow: visible }` global, it will break tables and
rounded-corner clipping elsewhere:

```css
/* Reports → Appraisals filter row only */
.appraisal-filters .card,
.appraisal-filters .card-body {
  overflow: visible;
}
```

If the ancestor is a `.table-responsive` (which *needs* `overflow: auto` for
horizontal scrolling), you **must** use §4.1 instead — you cannot unclip it
without losing the scroll.

### 4.3 Raise the stacking (C2)

```css
.datepicker.datepicker-dropdown {   /* or your library's panel class */
  z-index: 1060;                    /* above Bootstrap modal-backdrop (1050) */
}
```

And make sure the field's own wrapper establishes positioning:

```css
.appraisal-filters .form-group {
  position: relative;
}
```

Pick a value consistent with the rest of the app rather than `9999` — if a
picker ever has to open inside a modal, it needs to beat the modal
(Bootstrap 5: modal `1055`, so `1060` is the right neighbourhood).

### 4.4 Remove the containing-block breaker (C3)

If Test C found an ancestor with a `transform` (a common culprit is an
animation utility class, or `transform: translateZ(0)` added for "GPU
acceleration"), remove it from that ancestor or apply §4.1.

---

## 5. Where to make the change

All three pages show the same picker, so find the shared origin first:

- [ ] Is there a **shared Blade partial** for the filter row?
      (`resources/views/reports/appraisals/_filters.blade.php` or similar) —
      `<fill in>`
- [ ] Or a **shared JS initialiser** that binds every `.month-picker` /
      `[data-month-picker]` on page load — `<fill in>`
- [ ] Or is the picker initialised **separately in each of the three views**?
      If so, this is also a good moment to extract it into one partial so the
      next fix is a one-liner.

Fix the shared source, not the three pages individually.

---

## 6. Regression checks after the fix

- [ ] Picker opens fully — all 12 months visible on all three pages
- [ ] `«` / `»` year navigation works and stays inside the panel
- [ ] Selecting a month writes the correct value into the input **and** into
      the hidden field the form actually submits
- [ ] Clicking outside closes the picker (especially important after §4.1 —
      this is the one thing re-parenting tends to break)
- [ ] Picker closes on `Esc` and on scroll-away
- [ ] **Probation Appraisal Status:** picker does not cover the `SELECT BRANCH`
      dropdown, and opening `SELECT BRANCH` closes the month picker
- [ ] **Export Performance / Export Department Performance:** the green
      `Export …` button stays clickable while the picker is open
- [ ] Page still submits and the report returns rows for the chosen month
- [ ] Check at a narrow viewport (≈768px) — the panel must not push horizontal
      page scroll
- [ ] If any of these screens can appear inside a modal, verify there too

---

## 7. Suggested one-line summary for the ticket

> The Appraisals month picker is rendered inside the filter card, which clips
> it (`overflow: hidden`) and traps it in a low stacking context. Initialise
> the picker with `container: 'body'` (or `appendTo: document.body`) in the
> shared filter component, and give the panel `z-index: 1060`. Affects
> Probation Appraisal Status, Export Performance, and Export Department
> Performance.
