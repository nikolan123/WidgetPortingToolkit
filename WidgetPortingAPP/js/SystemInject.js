//
//  SystemInject.js
//  WidgetPortingAPP
//
//  Created by Niko on 12.09.25.
//

window.widget.system = function(command, finishedHandler) {
    const token = "sys_" + Date.now() + "_" + Math.random();
    const cmd = {
        token: token,
        _onreadoutput: null,
        _finishedHandler: finishedHandler,
        onreadoutput: null,
        cancel: function() {
            window.webkit.messageHandlers.systemCommand.postMessage({
                action: "cancel",
                token: token
            });
        }
    };

    // Store it globally so native can send data back
    window.__systemCommands = window.__systemCommands || {};
    window.__systemCommands[token] = cmd;

    window.webkit.messageHandlers.systemCommand.postMessage({
        action: "start",
        command: command,
        token: token
    });

    return cmd;
};

window.__handleSystemOutput = function(token, text, done, status) {
    const cmd = window.__systemCommands && window.__systemCommands[token];
    if (!cmd) return;

    if (text && cmd.onreadoutput) cmd.onreadoutput(text);
    if (done && cmd._finishedHandler) {
        cmd._finishedHandler({
            outputString: text || "",
            errorString: "",
            status: status ?? 0
        });
        delete window.__systemCommands[token];
    }
};
