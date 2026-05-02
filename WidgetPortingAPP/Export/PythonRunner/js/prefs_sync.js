(function () {
  function waitForBridge() {
    return new Promise(function (resolve) {
      let tries = 0;
      const timer = setInterval(function () {
        tries += 1;
        if (window.qtBridge && typeof window.qtBridge.postMessage === "function") {
          clearInterval(timer);
          resolve(true);
          return;
        }
        if (tries > 400) {
          clearInterval(timer);
          resolve(false);
        }
      }, 10);
    });
  }

  function loadPreferencesFromBridge() {
    return waitForBridge().then(function (ready) {
      if (!ready) {
        return {};
      }
      try {
        return Promise.resolve(window.qtBridge.postMessage("getAllPreferences", "null"))
          .then(function (raw) {
            const parsed = JSON.parse(raw || "{}");
            if (parsed && parsed.ok && parsed.preferences && typeof parsed.preferences === "object") {
              return parsed.preferences;
            }
            return {};
          })
          .catch(function (error) {
            console.warn("[runner] failed to load preferences from bridge", error);
            return {};
          });
      } catch (error) {
        console.warn("[runner] failed to load preferences from bridge", error);
        return {};
      }
    });
  }

  function installPreferenceHooks(initialPreferences) {
    if (!window.widget) {
      return false;
    }

    window.__widgetPrefs = Object.assign({}, window.__widgetPrefs || {}, initialPreferences);

    window.widget.preferenceForKey = function (key) {
      const k = String(key ?? "");
      if (Object.prototype.hasOwnProperty.call(window.__widgetPrefs, k)) {
        return window.__widgetPrefs[k];
      }
      return null;
    };

    window.widget.setPreferenceForKey = function (value, key) {
      const k = String(key ?? "");
      if (value === null || typeof value === "undefined") {
        delete window.__widgetPrefs[k];
      } else {
        window.__widgetPrefs[k] = value;
      }

      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.setPreferenceForKey) {
          window.webkit.messageHandlers.setPreferenceForKey.postMessage({
            key: k,
            value: (value === undefined ? null : value)
          });
        }
      } catch (error) {
        console.warn("[runner] failed to persist preference", k, error);
      }
    };

    return true;
  }

  loadPreferencesFromBridge().then(function (initialPreferences) {
    let tries = 0;
    const timer = setInterval(function () {
      tries += 1;
      if (installPreferenceHooks(initialPreferences) || tries > 100) {
        clearInterval(timer);
      }
    }, 20);
  });
})();