//
//  ExportRuntime.js
//  WidgetPortingAPP
//
//  Created by Niko on 24.04.26.
//

(function () {
    if (window.__widgetPortingExportRuntimeInstalled) return;
    window.__widgetPortingExportRuntimeInstalled = true;

    var WPT_LOG_PREFIX = "[WidgetPortingExport]";
    function wptWarn(msg) {
        try { console.warn(WPT_LOG_PREFIX + " " + msg); } catch (e) {}
    }

    var host = window.WidgetPortHost || window.__WidgetPortHost || null;

    if (!window.webkit) window.webkit = {};
    if (!window.webkit.messageHandlers) window.webkit.messageHandlers = {};

    if (typeof Proxy === "function") {
        var existingHandlers = window.webkit.messageHandlers;
        window.webkit.messageHandlers = new Proxy(existingHandlers, {
            get: function (target, prop) {
                if (prop in target) return target[prop];
                return {
                    postMessage: function () {
                        wptWarn("Native bridge " + String(prop) + " unavailable in browser export.");
                    }
                };
            }
        });
    }

    function widgetIdentifier() {
        try {
            if (window.widget && window.widget.identifier) {
                return String(window.widget.identifier);
            }
        } catch (e) {}
        return "widget_export";
    }

    function prefStorageKey(key) {
        return "WidgetPrefs::" + widgetIdentifier() + "::" + key;
    }

    function savePreference(key, value) {
        try {
            if (value === null || typeof value === "undefined") {
                localStorage.removeItem(prefStorageKey(key));
            } else {
                localStorage.setItem(prefStorageKey(key), JSON.stringify(value));
            }
        } catch (e) {}
    }

    function loadPreference(key) {
        try {
            var raw = localStorage.getItem(prefStorageKey(key));
            if (raw === null) return null;
            return JSON.parse(raw);
        } catch (e) {
            return null;
        }
    }

    function noopHandler(name, impl) {
        if (!window.webkit.messageHandlers[name]) {
            window.webkit.messageHandlers[name] = {
                postMessage: impl || function () {
                    wptWarn("Native bridge " + name + " unavailable in browser export.");
                }
            };
        }
    }

    noopHandler("setPreferenceForKey", function (payload) {
        if (!payload || typeof payload.key !== "string") return;
        if (!window.__widgetPrefs) window.__widgetPrefs = {};
        if (payload.value === null || typeof payload.value === "undefined") {
            delete window.__widgetPrefs[payload.key];
        } else {
            window.__widgetPrefs[payload.key] = payload.value;
        }
        savePreference(payload.key, payload.value);
    });

    noopHandler("openURL", function (url) {
        try { if (url) window.open(String(url), "_blank", "noopener"); } catch (e) {}
    });

    noopHandler("prepareForTransition", function () {});
    noopHandler("performTransition", function () {
        try {
            if (typeof window.onshow === "function") window.onshow();
        } catch (e) {}
    });

    noopHandler("resizeTo", function (payload) {
        if (!payload) return;
        try {
            if (typeof window.resizeTo === "function") {
                window.resizeTo(Number(payload.width) || window.innerWidth, Number(payload.height) || window.innerHeight);
            }
        } catch (e) {
            wptWarn("resizeTo is blocked in this context.");
        }
    });

    noopHandler("nativeXHR_send", function () {
        wptWarn("nativeXHR bridge unavailable; widget should use standard XMLHttpRequest/fetch.");
    });
    noopHandler("nativeXHR_abort", function () {});

    noopHandler("systemCommand", function (payload) {
        if (!payload || typeof payload.token !== "string") return;
        if (payload.action === "cancel") {
            if (host && typeof host.cancelCommand === "function") {
                try { host.cancelCommand(payload.token); } catch (e) {}
            }
            return;
        }
        if (payload.action !== "start") return;

        if (host && typeof host.runCommand === "function") {
            var command = payload.command || "";
            try {
                Promise.resolve(host.runCommand({
                    token: payload.token,
                    command: command,
                    onOutput: function (chunk) {
                        try {
                            if (typeof window.__handleSystemOutput === "function") {
                                window.__handleSystemOutput(payload.token, String(chunk || ""), false, 0);
                            }
                        } catch (e) {}
                    }
                })).then(function (result) {
                    var status = 0;
                    if (result && typeof result.status === "number") status = result.status;
                    if (typeof window.__handleSystemOutput === "function") {
                        window.__handleSystemOutput(payload.token, "", true, status);
                    }
                }).catch(function (err) {
                    var message = "System command failed via host bridge.";
                    try { if (err && err.message) message = String(err.message); } catch (e) {}
                    if (typeof window.__handleSystemOutput === "function") {
                        window.__handleSystemOutput(payload.token, message + "\n", true, 1);
                    }
                });
            } catch (e) {
                if (typeof window.__handleSystemOutput === "function") {
                    window.__handleSystemOutput(payload.token, "System command host bridge crashed.\n", true, 1);
                }
            }
            return;
        }

        wptWarn("System command blocked in HTML export: " + (payload.command || ""));
        if (typeof window.__handleSystemOutput === "function") {
            window.__handleSystemOutput(payload.token, "System commands are unavailable in browser export runtime.\n", true, 127);
        }
    });

    window.System = window.System || {};
    if (typeof window.System.encrypt !== "function") {
        window.System.encrypt = function (value) { return String(value || ""); };
    }
    if (typeof window.System.decrypt !== "function") {
        window.System.decrypt = function (value) { return String(value || ""); };
    }
    if (typeof window.System.version !== "function") {
        window.System.version = function () { return "html-export"; };
    }

    window.Kludget = window.Kludget || {};
    if (!window.Kludget.Settings) {
        window.Kludget.Settings = {
            read: function (key, fallback) {
                try {
                    var v = localStorage.getItem("Kludget::" + key);
                    return v === null ? fallback : v;
                } catch (e) {
                    return fallback;
                }
            },
            write: function (key, value) {
                try { localStorage.setItem("Kludget::" + key, String(value || "")); } catch (e) {}
            },
            remove: function (key) {
                try { localStorage.removeItem("Kludget::" + key); } catch (e) {}
            }
        };
    }
    if (typeof window.Kludget.log !== "function") {
        window.Kludget.log = function (message) {
            try { console.log("[Kludget]", message); } catch (e) {}
        };
    }

    window.__WidgetPortingExportUnsupportedFeatures = [
        "openApplication",
        "setCloseBoxOffset",
        "prepareForTransition",
        "performTransition",
        "nativeXHR",
        "systemCommand"
    ];

    if (!window.TimeZoneInfo) {
        function tzPartsForZone(tz) {
            try {
                var fmt = new Intl.DateTimeFormat("en-US", {
                    timeZone: tz || Intl.DateTimeFormat().resolvedOptions().timeZone,
                    hour12: false,
                    hour: "2-digit",
                    minute: "2-digit",
                    second: "2-digit"
                });
                var parts = fmt.formatToParts(new Date());
                var h = Number((parts.find(function (p) { return p.type === "hour"; }) || {}).value || 0);
                var m = Number((parts.find(function (p) { return p.type === "minute"; }) || {}).value || 0);
                var s = Number((parts.find(function (p) { return p.type === "second"; }) || {}).value || 0);
                return { hours: h, minutes: m, seconds: s };
            } catch (e) {
                var d = new Date();
                return { hours: d.getHours(), minutes: d.getMinutes(), seconds: d.getSeconds() };
            }
        }

        function encodeHMS(parts) {
            var h = Number(parts.hours || 0);
            var m = Number(parts.minutes || 0);
            var s = Number(parts.seconds || 0);
            return h * 10000 + m * 100 + s;
        }

        function offsetForZone(tz) {
            try {
                var parts = new Intl.DateTimeFormat("en-US", {
                    timeZone: tz || Intl.DateTimeFormat().resolvedOptions().timeZone,
                    timeZoneName: "shortOffset"
                }).formatToParts(new Date());
                var zonePart = (parts.find(function (p) { return p.type === "timeZoneName"; }) || {}).value || "";
                var match = zonePart.match(/^GMT([+-])(\d{1,2})(?::?(\d{2}))?$/);
                if (match) {
                    var sign = match[1] === "+" ? 1 : -1;
                    var hh = Number(match[2] || 0);
                    var mm = Number(match[3] || 0);
                    var total = hh * 60 + mm;
                    return sign === 1 ? -total : total;
                }
            } catch (e) {}
            return new Date().getTimezoneOffset();
        }

        function defaultContinentName() {
            try {
                var tz = Intl.DateTimeFormat().resolvedOptions().timeZone || "";
                var continent = String(tz).split("/")[0] || "North America";
                return continent.replace(/_/g, " ");
            } catch (e) {
                return "North America";
            }
        }

        window.TimeZoneInfo = {
            getDefaultContinentName: function () { return defaultContinentName(); },
            getDefaultGeoID: function () { return 0; },
            getDefaultTimeZoneOffset: function () { return new Date().getTimezoneOffset(); },
            currentTimeForTimeZone: function (tz) { return encodeHMS(tzPartsForZone(tz)); },
            getLocalizedTime: function (tz) {
                try {
                    return new Date().toLocaleTimeString([], tz ? { timeZone: tz } : undefined);
                } catch (e) {
                    return new Date().toLocaleTimeString();
                }
            },
            getTimezoneOffsetForTimezoneName: function (tz) { return offsetForZone(tz); }
        };
    }

    function patchWidgetPreferenceAPI() {
        if (!window.widget) return false;
        var originalPreferenceForKey = window.widget.preferenceForKey;
        var originalSetPreference = window.widget.setPreferenceForKey;

        window.widget.preferenceForKey = function (key) {
            var loaded = null;
            try { loaded = loadPreference(String(key || "")); } catch (e) {}
            if (loaded !== null) return loaded;
            if (typeof originalPreferenceForKey === "function") {
                try { return originalPreferenceForKey.call(window.widget, key); } catch (e) {}
            }
            return null;
        };

        window.widget.setPreferenceForKey = function (value, key) {
            try { savePreference(String(key || ""), value); } catch (e) {}
            if (typeof originalSetPreference === "function") {
                try { return originalSetPreference.call(window.widget, value, key); } catch (e) {}
            }
            return undefined;
        };

        try {
            if (window.__widgetPrefs) {
                for (var key in window.__widgetPrefs) {
                    if (Object.prototype.hasOwnProperty.call(window.__widgetPrefs, key)) {
                        var persisted = loadPreference(key);
                        if (persisted !== null) window.__widgetPrefs[key] = persisted;
                    }
                }
            }
        } catch (e) {}

        return true;
    }

    if (!patchWidgetPreferenceAPI()) {
        var tries = 0;
        var interval = setInterval(function () {
            tries += 1;
            if (patchWidgetPreferenceAPI() || tries > 50) {
                clearInterval(interval);
            }
        }, 100);
    }
})();
