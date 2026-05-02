(function () {
  function disableScroll() {
    const root = document.documentElement;
    const body = document.body;
    if (root) {
      root.style.overflow = "hidden";
      root.style.overscrollBehavior = "none";
      root.style.height = "100%";
    }
    if (body) {
      body.style.overflow = "hidden";
      body.style.overscrollBehavior = "none";
      body.style.height = "100%";
    }
  }

  function block(event) {
    event.preventDefault();
    event.stopPropagation();
    return false;
  }

  document.addEventListener("dragstart", function (event) {
    const target = event.target;
    if (!target) {
      return;
    }
    if (target.tagName === "IMG" || target.tagName === "A") {
      block(event);
    }
  }, true);

  document.addEventListener("drop", block, true);
  document.addEventListener("dragover", block, true);
  document.addEventListener("wheel", block, { capture: true, passive: false });

  const style = document.createElement("style");
  style.textContent = "html, body { overflow: hidden !important; overscroll-behavior: none !important; } img, a { -webkit-user-drag: none !important; user-drag: none !important; }";
  document.documentElement.appendChild(style);
  disableScroll();
})();