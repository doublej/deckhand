# Bundled resources

`mermaid.min.js` — mermaid **11.12.3**, the official minified build, MIT licensed.

Bundled rather than fetched, and that is the whole design: the artifact CSP forbids a page from
reaching the network at all, and a diagram in a transcript must draw on a phone whose Mac has
just gone to sleep. It is injected as a `WKUserScript` — host-initiated, the same lane the slip
bridge already uses — so nothing about the policy was loosened to make diagrams work.

2.8 MB, which is the honest price of a diagram renderer. It defines `globalThis.mermaid` on its
last line; there is no module loading to arrange.

To update: drop in a newer `dist/mermaid.min.js`, change the version above, and check a diagram
still draws — `MermaidBlock` pins nothing and asks for no API that has moved since 10.
