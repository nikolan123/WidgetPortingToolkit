(function() {
  if (window.__WidgetPortingNetworkIssueDetectorInstalled) return;
  window.__WidgetPortingNetworkIssueDetectorInstalled = true;

  var reported = false;
  var patterns = [
    "xmlhttprequest cannot load",
    "cross-origin redirection",
    "cross-origin resource sharing",
    "access control checks",
    "origin null is not allowed by access-control-allow-origin"
  ];

  function textFromArgs(args) {
    var out = [];
    for (var i = 0; i < args.length; i++) {
      try {
        var value = args[i];
        if (typeof value === "string") out.push(value);
        else if (value && value.message) out.push(String(value.message));
        else out.push(String(value));
      } catch (e) {}
    }
    return out.join(" ");
  }

  function matches(text) {
    text = String(text || "").toLowerCase();
    for (var i = 0; i < patterns.length; i++) {
      if (text.indexOf(patterns[i]) !== -1) return true;
    }
    return false;
  }

  function report(payload) {
    if (reported) return;
    var message = textFromArgs([payload && payload.message, payload && payload.url, payload && payload.reason]);
    if (!matches(message)) return;
    reported = true;
    try { window.webkit.messageHandlers.networkIssueDetected.postMessage(payload); } catch (e) {}
  }

  var originalConsoleError = console.error;
  console.error = function() {
    var message = textFromArgs(arguments);
    report({ reason: "console.error", message: message });
    if (typeof originalConsoleError === "function") {
      return originalConsoleError.apply(this, arguments);
    }
  };

  window.addEventListener("error", function(event) {
    var message = textFromArgs([event.message, event.filename]);
    report({ reason: "window.error", message: message, url: event.filename || "" });
  }, true);

  var NativeXHR = window.XMLHttpRequest;
  if (!NativeXHR || !NativeXHR.prototype) return;

  var originalOpen = NativeXHR.prototype.open;
  var originalSend = NativeXHR.prototype.send;

  NativeXHR.prototype.open = function(method, url) {
    this.__wptXHRMethod = method ? String(method) : "GET";
    this.__wptXHRURL = url ? String(url) : "";
    return originalOpen.apply(this, arguments);
  };

  NativeXHR.prototype.send = function() {
    var xhr = this;
    var url = xhr.__wptXHRURL || "";
    var isHTTP = /^https?:\/\//i.test(url);
    var isLocalOrigin = window.location.protocol === "file:" || window.location.origin === "null";

    function maybeReport() {
      if (!isHTTP) return;
      if (xhr.status !== 0) return;
      var reason = isLocalOrigin ? "Origin null XHR blocked" : "Cross-origin XHR blocked";
      report({
        reason: reason,
        message: "XMLHttpRequest cannot load " + url + " due to access control checks.",
        url: url
      });
    }

    try {
      xhr.addEventListener("error", maybeReport);
    } catch (e) {}

    return originalSend.apply(this, arguments);
  };
})();
