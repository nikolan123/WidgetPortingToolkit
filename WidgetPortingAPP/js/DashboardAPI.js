//
//  DashboardAPI.js
//  WidgetPortingAPP
//
//  Created by Niko on 9.09.25.
//

(function(){
    if (window.__widgetBridgeInitialized) return;
    window.__widgetBridgeInitialized = true;

    window.__widgetPrefs = __WIDGET_PREFS__;

    window.widget = window.widget || {};
    
    window.widget.identifier = "__WIDGET_IDENTIFIER__";
    
    /* preferences */

    window.widget.setPreferenceForKey = function(value, key) {
        try { window.__widgetPrefs[key] = value; } catch(e) {}
        try {
            window.webkit.messageHandlers.setPreferenceForKey.postMessage({ key: key, value: (value === undefined ? null : value) });
        } catch(e) {}
    };

    window.widget.preferenceForKey = function(key) {
        var v = window.__widgetPrefs ? window.__widgetPrefs[key] : null;
        return (typeof v === 'undefined') ? null : v;
    };
    
    /* transitions */

    window.widget.prepareForTransition = function(direction) {
        try { window.webkit.messageHandlers.prepareForTransition.postMessage(direction); } catch(e) {}
    };

    window.widget.performTransition = function() {
        try { window.webkit.messageHandlers.performTransition.postMessage(null); } catch(e) {}
    };
    
    /* open url/app */
    
    window.widget.openURL = function(url) {
        try { window.webkit.messageHandlers.openURL.postMessage(url); } catch(e) {}
    };

    window.widget.openApplication = function(bundleId) {
        try { window.webkit.messageHandlers.openApplication.postMessage(bundleId); } catch(e) {}
    };
    
    /* window resize */
    
    window.resizeTo = function (w, h) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.resizeTo) {
            window.webkit.messageHandlers.resizeTo.postMessage({ width: w, height: h });
        } else {
            console.log("resizeTo requested:", w, h);
        }
    };
    
    window.widget.setCloseBoxOffset = function(x, y)
    {
      alert("setCloseBoxOffset not implemented.");
    }
    
    /* event hooks */
    
    window.widget.onshow = function() {};
    window.widget.onhide = function() {};
    window.widget.onstartdrag = function() {};
    window.widget.onenddrag = function() {};
    window.widget.onremove = function() {};
    window.widget.onsync = function() {};
    window.widget.onsettingschanged = function() {};
    window.widget.onurlreceived = function(url) {};
    
    /* aliases */
    
    window.onshow = window.widget.onshow;
    window.onhide = window.widget.onhide;
    window.onstartdrag = window.widget.onstartdrag;
    window.onenddrag = window.widget.onenddrag;
    window.onremove = window.widget.onremove;
    window.onsync = window.widget.onsync;
    window.onsettingschanged = window.widget.onsettingschanged;
    window.onurlreceived = window.widget.onurlreceived;

    window.kludget = window.widget;
    window.Widget = window.widget;
})();
