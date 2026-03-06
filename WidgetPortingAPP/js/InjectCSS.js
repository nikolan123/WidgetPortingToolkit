//
//  injectCSS.js
//  WidgetPortingAPP
//
//  Created by Niko on 9.09.25.
//

(function(){
  var s = document.createElement('style');
  s.type = 'text/css';
  s.appendChild(document.createTextNode(`
* {
    -webkit-user-drag: none;
    -webkit-user-select: none;
}

*[src*="SupportDirectory/"][src*="button"],
*[style*="SupportDirectory/"][style*="button"] {
    cursor: pointer;
}
  
body {
    overflow: hidden;
}
  `));
  document.documentElement.appendChild(s);
})();
