# UI redesign placeholder artwork

Everything in this folder is a **development-only, AI-authored placeholder**.
The final game must contain **zero AI-authored artwork**.

- Filenames include `_AI_PLACEHOLDER` so provenance survives copying.
- `manifest.json` is the release-blocking source of truth.
- Replace an asset with human-authored/licensed artwork, update every reference,
  then remove its manifest entry and placeholder file.
- Do not rename, trace, or lightly edit a placeholder and present it as final art.

Run during development:

```bash
python3 tools/tests/check_ui_placeholders.py
```

Run for a release gate (expected to fail until every placeholder and reference is
gone):

```bash
python3 tools/tests/check_ui_placeholders.py --release
```

The generator pass adds six tracked masks: running, stopped, grid, fuel,
condition and power. Their runtime tint communicates the displayed state;
Running and Grid online are green, while project blue remains the main UI accent.
**Stored water / water fill** is still a future icon for the water-panel pass.
