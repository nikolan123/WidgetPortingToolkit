# Security Policy

## Reporting a Vulnerability

Please report suspected vulnerabilities privately by emailing [niko@nikolan.net](mailto:niko@nikolan.net) with “Widget Porting Toolkit security report” in the subject. Keep the details out of public issues while the report is being investigated.

Include the app build or commit, your macOS version, the steps to reproduce the issue, and what an attacker could do. If a specific widget triggers the issue, include its name and where it came from.

## Builds

If possible, check whether the issue still occurs in the [latest nightly build](https://github.com/nikolan123/WidgetPortingToolkit/releases/tag/nightly). Reports from older builds are welcome too.

## Running Widgets Safely

Only install `.wdgt` bundles from sources you trust. Dashboard widgets can request permission to run system commands. To disable that capability for a widget, turn off **Allow system command execution** in its runtime settings.
