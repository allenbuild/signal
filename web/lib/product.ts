export const gestures = [
  { id: "one", label: "One", glyph: "1" },
  { id: "two", label: "Two", glyph: "2" },
  { id: "three", label: "Three", glyph: "3" },
  { id: "four", label: "Four", glyph: "4" },
  { id: "five", label: "Five", glyph: "5" },
  { id: "fist", label: "Fist", glyph: "●" },
  { id: "thumbs_up", label: "Thumbs up", glyph: "↑" },
  { id: "thumbs_down", label: "Thumbs down", glyph: "↓" },
  { id: "c_shape", label: "C shape", glyph: "C" },
] as const;

export const touchControls = [
  {
    title: "Point to move",
    description: "Index-point relative cursor movement across the active display.",
    glyph: "↗",
  },
  {
    title: "Pinch to click",
    description: "Quick thumb-index pinch and release for a native click.",
    glyph: "◎",
  },
  {
    title: "Hold + move to scroll",
    description: "Keep the pinch held and move vertically for system scroll.",
    glyph: "↕",
  },
  {
    title: "Hold + move to zoom",
    description: "Keep the pinch held and move horizontally for system zoom.",
    glyph: "↔",
  },
] as const;
