//
//  SystemInject.js
//  WidgetPortingAPP
//
//  Created by Niko on 12.09.25.
//

window.widget.system = function(command, finishedHandler) {
    var supportsSynchronousSystem = "__WIDGET_SYSTEM_SCHEME_ENABLED__" === "true";

    // Synchronous mode
    // When finishedHandler is null/undefined, block JS via synchronous XHR
    // to a custom URL scheme handled natively.
    if (supportsSynchronousSystem && (finishedHandler === null || finishedHandler === undefined)) {
        var XHR = window.__WidgetPortingNativeXMLHttpRequest || window.XMLHttpRequest;
        var xhr = new XHR();
        xhr.open("POST", "widget-system://run?cmd=" + encodeURIComponent(command), false);
        try {
            xhr.send(command);
            var result = JSON.parse(xhr.responseText);
            return {
                outputString: result.outputString || "",
                errorString: result.errorString || "",
                status: result.status != null ? result.status : -1
            };
        } catch (e) {
            return { outputString: "", errorString: e.toString(), status: -1 };
        }
    }

    // Asynchronous mode
    var token = "sys_" + Date.now() + "_" + Math.random();
    var cmd = {
        token: token,
        outputString: "",
        errorString: "",
        status: -1,
        onreadoutput: null,
        onreaderror: null,
        _receivedStreamingOutput: false,
        _finishedHandler: finishedHandler,
        cancel: function() {
            window.webkit.messageHandlers.systemCommand.postMessage({
                action: "cancel",
                token: token
            });
        },
        write: function(str) {
            window.webkit.messageHandlers.systemCommand.postMessage({
                action: "write",
                token: token,
                string: str
            });
        },
        close: function() {
            window.webkit.messageHandlers.systemCommand.postMessage({
                action: "close",
                token: token
            });
        }
    };

    window.__systemCommands = window.__systemCommands || {};
    window.__systemCommands[token] = cmd;

    window.webkit.messageHandlers.systemCommand.postMessage({
        action: "start",
        command: command,
        token: token
    });

    return cmd;
};

// Native callback dispatcher.
// When done=false: extra is isError (boolean) - true for stderr, false for stdout.
// When done=true:  extra is the exit status (number).
window.__handleSystemOutput = function(token, text, done, extra) {
    var cmd = window.__systemCommands && window.__systemCommands[token];
    if (!cmd) return;

    if (!done) {
        if (text) cmd._receivedStreamingOutput = true;
        if (extra) {
            cmd.errorString += text;
            if (cmd.onreaderror) cmd.onreaderror(text);
        } else {
            cmd.outputString += text;
            if (cmd.onreadoutput) cmd.onreadoutput(text);
        }
    } else {
        cmd.status = extra != null ? extra : 0;
        if (text && !cmd._receivedStreamingOutput) {
            if (cmd.status === 0) {
                cmd.outputString += text;
            } else {
                cmd.errorString += text;
            }
        }
        if (cmd._finishedHandler) {
            cmd._finishedHandler(cmd);
        }
        delete window.__systemCommands[token];
    }
};
