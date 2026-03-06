//
//  XHRBridge.js
//  WidgetPortingAPP
//
//  Created by Niko on 9.09.25.
//

(function(){
  if (window.__nativeXHRInstalled) return;
  window.__nativeXHRInstalled = true;

  var pending = Object.create(null);

  function toHeadersString(hObj){
    if (!hObj) return "";
    var lines = [];
    for (var k in hObj){
      if (!Object.prototype.hasOwnProperty.call(hObj, k)) continue;
      var v = hObj[k];
      if (Array.isArray(v)) {
        for (var i=0;i<v.length;i++) lines.push(k + ": " + String(v[i]));
      } else {
        lines.push(k + ": " + String(v));
      }
    }
    return lines.join("\\r\\n");
  }

  function NativeXHR(){
    this._id = null;
    this._method = "GET";
    this._url = "";
    this._async = true;
    this._headers = {};
    this._body = null;

    this.readyState = 0; // UNSENT
    this.status = 0;
    this.statusText = "";
    this.responseText = "";
    this.response = "";
    this.responseXML = null;
    this.responseType = ""; // we only support ""/text
    this.onreadystatechange = null;
    this.onload = null;
    this.onerror = null;
    this.ontimeout = null;
    this.onabort = null;
    this.upload = {};
    this.timeout = 0; // ms
    this.withCredentials = false; // ignored on native side
    this._responseHeaders = "";
    this._aborted = false;
  }

NativeXHR.prototype.overrideMimeType = function(mime) {
  this._overrideMimeType = mime; // store if you want, no real effect
};


  NativeXHR.prototype.open = function(method, url, async){
    this._method = String(method || "GET");
    this._url = String(url || "");
    this._async = (async !== false); // default async
    this.readyState = 1; // OPENED
    if (typeof this.onreadystatechange === "function") this.onreadystatechange();
  };

  NativeXHR.prototype.setRequestHeader = function(name, value){
    var k = String(name || "");
    var v = String(value || "");
    if (!this._headers[k]) this._headers[k] = v;
    else this._headers[k] += ", " + v;
  };

  NativeXHR.prototype.getResponseHeader = function(name){
    var target = String(name || "").toLowerCase();
    var hdrs = this._responseHeaders.split(/\\r?\\n/);
    for (var i=0;i<hdrs.length;i++){
      var line = hdrs[i];
      var idx = line.indexOf(":");
      if (idx <= 0) continue;
      var h = line.slice(0, idx).trim().toLowerCase();
      if (h === target) return line.slice(idx+1).trim();
    }
    return null;
  };

  NativeXHR.prototype.getAllResponseHeaders = function(){
    return this._responseHeaders || "";
  };

  NativeXHR.prototype.abort = function(){
    if (this._id == null) return;
    try { window.webkit.messageHandlers.nativeXHR_abort.postMessage({ id: this._id }); } catch(e){}
  };

  NativeXHR.prototype.send = function(body){
    if (this._id != null) return; // sent already
    this._body = (typeof body === "undefined") ? null : body;
    var id = Date.now() + Math.floor(Math.random()*1000000);
    this._id = id;
    pending[id] = this;

    var headersArray = [];
    for (var k in this._headers){
      if (!Object.prototype.hasOwnProperty.call(this._headers, k)) continue;
      headersArray.push([k, this._headers[k]]);
    }

    var payload = {
      id: id,
      method: this._method,
      url: this._url,
      headers: headersArray,
      body: (typeof this._body === "string" || this._body == null) ? this._body : String(this._body),
      timeout: (this.timeout|0),
      withCredentials: !!this.withCredentials
    };

    try {
      window.webkit.messageHandlers.nativeXHR_send.postMessage(payload);
    } catch (e) {
      // If native side not available, error out
      this.readyState = 4;
      if (typeof this.onreadystatechange === "function") this.onreadystatechange();
      if (typeof this.onerror === "function") this.onerror();
      delete pending[id];
    }
  };

  // Called by native to stream state/data back
  window.__nativeXHRCallback = function(msg){
    if (!msg || typeof msg.id === "undefined") return;
    var xhr = pending[msg.id];
    if (!xhr) return;

    if (msg.type === "headers") {
      xhr.status = msg.status|0;
      xhr.statusText = msg.statusText || "";
      xhr._responseHeaders = msg.headers || "";
      xhr.readyState = 2; // HEADERS_RECEIVED
      if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
    } else if (msg.type === "loading") {
      // We do not append partial text (could be large/binary). Just signal state.
      xhr.readyState = 3; // LOADING
      if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
    } else if (msg.type === "done") {
      xhr.status = msg.status|0;
      xhr.statusText = msg.statusText || "";
      xhr._responseHeaders = msg.headers || xhr._responseHeaders || "";
      var text = (typeof msg.text === "string") ? msg.text : "";
      xhr.responseText = text;
      xhr.response = (xhr.responseType === "" || xhr.responseType === "text") ? text : text; // only text supported
      
      // Parse responseXML if content looks like XML
      xhr.responseXML = null;
      if (text && (xhr.responseType === "" || xhr.responseType === "document")) {
        var contentType = xhr.getResponseHeader("content-type") || "";
        if (contentType.indexOf("xml") !== -1 || text.trim().indexOf("<?xml") === 0) {
          try {
            var parser = new DOMParser();
            xhr.responseXML = parser.parseFromString(text, "text/xml");
          } catch(e) {
            // Failed to parse, leave as null
          }
        }
      }
      
      xhr.readyState = 4; // DONE
      if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
      if (msg.ok) { if (typeof xhr.onload === "function") xhr.onload(); }
      else { if (typeof xhr.onerror === "function") xhr.onerror(); }
      delete pending[msg.id];
    } else if (msg.type === "timeout") {
      xhr.readyState = 4;
      if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
      if (typeof xhr.ontimeout === "function") xhr.ontimeout();
      delete pending[msg.id];
    } else if (msg.type === "abort") {
      xhr._aborted = true;
      xhr.readyState = 4;
      if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
      if (typeof xhr.onabort === "function") xhr.onabort();
      delete pending[msg.id];
    } else if (msg.type === "error") {
      xhr.readyState = 4;
      if (typeof xhr.onreadystatechange === "function") xhr.onreadystatechange();
      if (typeof xhr.onerror === "function") xhr.onerror();
      delete pending[msg.id];
    }
  };

  // Install override
  window.XMLHttpRequest = NativeXHR;
})();
