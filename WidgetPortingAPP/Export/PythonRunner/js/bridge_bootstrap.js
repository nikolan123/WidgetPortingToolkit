(function () {
  let bridgeReady = false;
  const pendingMessages = [];

  function send(name, payload) {
    const serialized = JSON.stringify(payload ?? null);
    if (!bridgeReady || !window.qtBridge || typeof window.qtBridge.postMessage !== "function") {
      pendingMessages.push({ name, payload: serialized });
      return Promise.resolve(null);
    }
    try {
      return window.qtBridge.postMessage(name, serialized);
    } catch (error) {
      console.error("[runner] bridge call failed", name, error);
      return Promise.resolve(null);
    }
  }

  function flushPending() {
    if (!bridgeReady || !window.qtBridge || typeof window.qtBridge.postMessage !== "function") {
      return;
    }
    while (pendingMessages.length > 0) {
      const item = pendingMessages.shift();
      try {
        window.qtBridge.postMessage(item.name, item.payload);
      } catch (error) {
        console.error("[runner] bridge flush failed", item.name, error);
      }
    }
  }

  function installWebKitHandlers() {
    window.webkit = window.webkit || {};
    window.webkit.messageHandlers = window.webkit.messageHandlers || {};

    const handlers = [
      "openURL",
      "openApplication",
      "setPreferenceForKey",
      "getAllPreferences",
      "prepareForTransition",
      "performTransition",
      "resizeTo",
      "systemCommand",
      "system",
      "command",
      "preferences",
      "widget",
      "log"
    ];

    for (const name of handlers) {
      let hasOwn = false;
      try {
        hasOwn = Object.prototype.hasOwnProperty.call(window.webkit.messageHandlers, name);
      } catch (error) {
        hasOwn = false;
      }
      if (!hasOwn) {
        window.webkit.messageHandlers[name] = {
          postMessage(payload) {
            return send(name, payload);
          }
        };
      }
    }
  }

  function bootWhenReady(tries) {
    if (bridgeReady) {
      return;
    }
    if (!window.QWebChannel || !window.qt || !window.qt.webChannelTransport) {
      if (tries < 400) {
        setTimeout(function () {
          bootWhenReady(tries + 1);
        }, 10);
      }
      return;
    }

    new QWebChannel(window.qt.webChannelTransport, function (channel) {
      window.qtBridge = channel.objects.qtBridge;
      bridgeReady = !!(window.qtBridge && typeof window.qtBridge.postMessage === "function");
      if (bridgeReady) {
        flushPending();
      }
    });
  }

  function loadScript(src, onLoad) {
    function insert() {
      const parent = document.head || document.documentElement || document.body;
      if (!parent) {
        return false;
      }
      const script = document.createElement("script");
      script.src = src;
      script.onload = onLoad;
      parent.appendChild(script);
      return true;
    }

    if (insert()) {
      return;
    }

    const onReady = function () {
      if (insert()) {
        document.removeEventListener("DOMContentLoaded", onReady);
      }
    };
    document.addEventListener("DOMContentLoaded", onReady);
  }

  installWebKitHandlers();

  if (window.QWebChannel) {
    bootWhenReady(0);
  } else {
    loadScript("qrc:///qtwebchannel/qwebchannel.js", function () {
      bootWhenReady(0);
    });
  }
})();