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

The approved redesign also calls for future temporary status icons for
**Running**, **Grid online**, and **Stored water / water fill**. They are tracked
in the manifest but intentionally not created by the character-creation pass.
