from __future__ import annotations

import json
from pathlib import Path


class PreferenceStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._prefs: dict[str, object] = {}
        self._load()

    def _load(self) -> None:
        if not self.path.exists():
            return
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                self._prefs = raw
        except Exception:
            self._prefs = {}

    def _save(self) -> None:
        self.path.write_text(
            json.dumps(self._prefs, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

    def set(self, key: str, value: object) -> None:
        if value is None:
            self._prefs.pop(key, None)
        else:
            self._prefs[key] = value
        self._save()

    def get_all(self) -> dict[str, object]:
        return dict(self._prefs)


def build_preloaded_prefs_script(preferences: dict[str, object]) -> str:
    payload = json.dumps(preferences, ensure_ascii=False)
    return f"""
(function () {{
  var seed = {payload};
  var store = (seed && typeof seed === "object") ? Object.assign({{}}, seed) : {{}};

  try {{
    Object.defineProperty(window, "__widgetPrefs", {{
      configurable: true,
      enumerable: false,
      get: function () {{
        return store;
      }},
      set: function (value) {{
        if (!value || typeof value !== "object") {{
          return;
        }}
        store = Object.assign({{}}, store, value);
      }}
    }});
  }} catch (error) {{
    window.__widgetPrefs = store;
  }}
}})();
""".strip()