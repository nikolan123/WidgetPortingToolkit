//
//  DashboardDragRegions.js
//  WidgetPortingAPP
//
//  Created by Niko on 27.04.26.
//

(function () {
    if (window.__dashboardDragRegionsInitialized) return;
    window.__dashboardDragRegionsInitialized = true;

    var pendingDrag = null;
    var activeDrag = null;
    var dragThreshold = 3;
    var sourceRules = [];
    var bundledStylesheetSources = __DASHBOARD_REGION_CSS__;

    function parseStylesheetSource(source) {
        if (!source) return;

        var css = source.replace(/\/\*[\s\S]*?\*\//g, "");
        var rulePattern = /([^{}]+)\{([^{}]*)\}/g;
        var match;

        while ((match = rulePattern.exec(css)) !== null) {
            var selectorText = match[1].trim();
            var body = match[2];
            var propertyMatch = body.match(/-apple-dashboard-region\s*:\s*([^;]+)/);

            if (selectorText && propertyMatch) {
                sourceRules.push({
                    selectorText: selectorText,
                    value: propertyMatch[1].trim()
                });
            }
        }
    }

    function loadStylesheetSources() {
        var styleElements = document.querySelectorAll("style");
        for (var i = 0; i < styleElements.length; i++) {
            parseStylesheetSource(styleElements[i].textContent || "");
        }

        var links = document.querySelectorAll('link[rel~="stylesheet"][href]');
        for (var j = 0; j < links.length; j++) {
            try {
                fetch(links[j].href)
                    .then(function (response) {
                        return response.ok ? response.text() : "";
                    })
                    .then(parseStylesheetSource)
                    .catch(function () {});
            } catch (e) {}
        }
    }

    function dashboardRegionTextForElement(element) {
        var values = [];

        if (element.style && element.style.getPropertyValue) {
            var inlineValue = element.style.getPropertyValue("-apple-dashboard-region");
            if (inlineValue) values.push(inlineValue);
        }

        var inlineStyle = element.getAttribute("style") || "";
        var inlineMatch = inlineStyle.match(/-apple-dashboard-region\s*:\s*([^;]+)/);
        if (inlineMatch) values.push(inlineMatch[1].trim());

        try {
            var computedValue = window.getComputedStyle(element).getPropertyValue("-apple-dashboard-region");
            if (computedValue) values.push(computedValue);
        } catch (e) {}

        for (var i = 0; i < document.styleSheets.length; i++) {
            var sheet = document.styleSheets[i];
            var rules;
            try {
                rules = sheet.cssRules;
            } catch (e) {
                continue;
            }

            collectDashboardRegionRules(element, rules, values);
        }

        for (var j = 0; j < sourceRules.length; j++) {
            try {
                if (element.matches(sourceRules[j].selectorText)) {
                    values.push(sourceRules[j].value);
                }
            } catch (e) {}
        }

        return values.length ? values[values.length - 1] : "";
    }

    function collectDashboardRegionRules(element, rules, values) {
        for (var i = 0; i < rules.length; i++) {
            var rule = rules[i];

            if (rule.cssRules) {
                collectDashboardRegionRules(element, rule.cssRules, values);
                continue;
            }

            if (!rule.selectorText || !rule.style) continue;

            var value = rule.style.getPropertyValue("-apple-dashboard-region");
            if (!value) continue;

            try {
                if (element.matches(rule.selectorText)) values.push(value);
            } catch (e) {}
        }
    }

    function parseLength(value) {
        var parsed = parseFloat(value);
        if (!isFinite(parsed) || parsed < 0) return 0;
        return parsed;
    }

    function parseDashboardRegions(value) {
        if (!value || value === "none") return [];

        var regions = [];
        var pattern = /dashboard-region\(([^)]*)\)/g;
        var match;

        while ((match = pattern.exec(value)) !== null) {
            var parts = match[1].trim().split(/\s+/);
            if (parts.length < 2 || parts[0] !== "control") continue;

            var shape = parts[1];
            if (shape !== "rectangle" && shape !== "circle") continue;

            regions.push({
                shape: shape,
                top: parseLength(parts[2]),
                right: parseLength(parts[3]),
                bottom: parseLength(parts[4]),
                left: parseLength(parts[5])
            });
        }

        return regions;
    }

    function pointIsInRegion(clientX, clientY, element, region) {
        var rect = element.getBoundingClientRect();
        var left = rect.left + region.left;
        var top = rect.top + region.top;
        var right = rect.right - region.right;
        var bottom = rect.bottom - region.bottom;

        if (right < left || bottom < top) return false;

        if (region.shape === "rectangle") {
            return clientX >= left && clientX <= right && clientY >= top && clientY <= bottom;
        }

        var width = right - left;
        var height = bottom - top;
        var radius = Math.min(width, height) / 2;
        var centerX = left + width / 2;
        var centerY = top + height / 2;
        var dx = clientX - centerX;
        var dy = clientY - centerY;

        return dx * dx + dy * dy <= radius * radius;
    }

    function isInControlRegion(clientX, clientY) {
        var elements = document.elementsFromPoint(clientX, clientY);

        for (var i = 0; i < elements.length; i++) {
            var element = elements[i];
            var value = dashboardRegionTextForElement(element).trim();
            if (!value || value === "none") continue;

            var regions = parseDashboardRegions(value);
            for (var j = 0; j < regions.length; j++) {
                if (pointIsInRegion(clientX, clientY, element, regions[j])) return true;
            }
        }

        return false;
    }

    function postDragMessage(name, payload) {
        try {
            window.webkit.messageHandlers[name].postMessage(payload || {});
        } catch (e) {}
    }

    document.addEventListener("mousedown", function (event) {
        if (event.button !== 0) return;
        if (isInControlRegion(event.clientX, event.clientY)) return;

        pendingDrag = {
            startX: event.clientX,
            startY: event.clientY
        };
        activeDrag = null;
    }, true);

    document.addEventListener("mousemove", function (event) {
        if (!pendingDrag || (event.buttons & 1) !== 1) return;

        var dx = event.clientX - pendingDrag.startX;
        var dy = event.clientY - pendingDrag.startY;

        if (!activeDrag) {
            if (Math.abs(dx) < dragThreshold && Math.abs(dy) < dragThreshold) return;
            activeDrag = pendingDrag;
            postDragMessage("dashboardDragStart", {});
        }

        event.preventDefault();
        event.stopPropagation();
    }, true);

    document.addEventListener("mouseup", function (event) {
        if (activeDrag) {
            postDragMessage("dashboardDragEnd", {});
            event.preventDefault();
            event.stopPropagation();
        }

        pendingDrag = null;
        activeDrag = null;
    }, true);

    window.addEventListener("blur", function () {
        if (activeDrag) {
            postDragMessage("dashboardDragEnd", {});
        }

        pendingDrag = null;
        activeDrag = null;
    });

    for (var i = 0; i < bundledStylesheetSources.length; i++) {
        parseStylesheetSource(bundledStylesheetSources[i]);
    }
    loadStylesheetSources();
})();
