//
//  InjectCSS.js
//  WidgetPortingAPP
//
//  Created by Niko on 25.04.26.
//

(function () {
  var style = document.createElement("style");
  style.type = "text/css";
  style.appendChild(
    document.createTextNode(`
* {
  -webkit-user-drag: none;
  -webkit-user-select: none;
}

html,
body {
  overflow: hidden !important;
  margin: 0 !important;
  padding: 0 !important;
  width: 100% !important;
  height: 100% !important;
}
`)
  );
  (document.head || document.documentElement).appendChild(style);
})();
