/** Harisha — Tailwind config.
 *  Colour is driven by CSS custom properties (see src/input.css) so the
 *  three theme states (system / forced light / forced dark) and the
 *  per-person accent all resolve without duplicating utilities.
 */
module.exports = {
  content: ["./index.html"],
  theme: {
    extend: {
      colors: {
        paper:  "var(--paper)",
        raised: "var(--raised)",
        ink:    "var(--ink)",
        muted:  "var(--muted)",
        rule:   "var(--rule)",
        accent: "var(--accent)",
        pa:     "var(--pa)",
        pb:     "var(--pb)",
        match:  "var(--match)",
        warn:   "var(--warn)",
      },
      fontFamily: {
        sans: ["Archivo", "ui-sans-serif", "system-ui", "sans-serif"],
        mono: ['"JetBrains Mono"', "ui-monospace", "SFMono-Regular", "monospace"],
      },
      borderRadius: { none: "0", sm: "2px", DEFAULT: "2px" },
    },
  },
  plugins: [],
};
