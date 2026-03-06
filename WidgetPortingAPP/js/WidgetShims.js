//
//  WidgetShims.js
//  WidgetPortingAPP
//
//  Created by Niko on 9.09.25.
//

// unit converter shim
window.ConverterPlugin = window.ConverterPlugin || {
    valueForFormattedString: function(str, iso) { return parseFloat(String(str || "").replace(/,/g, "")) || 0; },
    formattedStringForValue: function(val, precision) { return Number(val || 0).toFixed(precision || 2); },
    formattedStringForCurrencyValue: function(val, precision, style, iso) { return Number(val || 0).toFixed(precision || 2); },
    currentTimeString: function() { return new Date().toLocaleTimeString(); },
    isUserTimeFormatTwelveHours: function() { return true; },
    currencySymbolForCode: function(iso) { return iso; },
    globalDecimalSeparator: function() { return "."; },
    currencyNameForCode: function(iso) { return iso; }
};

// calculator shim
window.widget = window.widget || {};
widget.calculator = widget.calculator || {};
widget.calculator.evaluateExpression = function(expr, mode) {
    try {
        if (expr === "decimal_string") return ".";
        if (expr === "thousands_separator") return ",";
        return eval(expr);
    } catch (e) {
        return "ERROR";
    }
};

// weather shim
widget.closestCity = function() {
    return null;
};

// KeychainHelper
window.KeychainHelper = {
    passwordForApplication: function(key, id) {
        return System.decrypt(Kludget.Settings.read(key + id, ""));
    },
    setPasswordForApplication: function(key, id, passwd) {
        Kludget.Settings.write(key + id, System.encrypt(passwd));
    },
    systemVersion: function() {
        return "1.0.6";
    }
};

// KeyChainAccess (mailchecker)
window.KeyChainAccess = Object.create(KeychainHelper);
KeyChainAccess.setAppName = function(appname) { this.app = appname; };
KeyChainAccess.loadPassword = function(user) { return this.passwordForApplication(this.app, user); };
KeyChainAccess.savePassword = function(user, passwd) { this.setPasswordForApplication(this.app, user, passwd); };
KeyChainAccess.setDebugOn = function(debug) {};

// RoundPlugin (converter)
window.RoundPlugin = {
    logMessage: function(msg) { alert(msg); },
    getFormattedValue: function(v) {
        var prec = 1;
        for(var j = 0; j < the_precision; j++) prec *= 10;
        return Math.round(v * prec)/prec;
    },
    getNumericValue: function(v) { return this.getFormattedValue(v); },
    getSeparators: function() { return ",."; }
};
