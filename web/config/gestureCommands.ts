export const gestureIds = [
  "one",
  "two",
  "three",
  "four",
  "five",
  "thumbs_up",
  "thumbs_down",
  "c_shape",
  "fist",
] as const;

export type GestureId = (typeof gestureIds)[number];

export type PresetGestureCommand = {
  gesture: GestureId;
  label: string;
  mark: string;
  commandName: string;
  description: string;
  actionType: string;
  availability: "ready" | "permission" | "unavailable";
  custom: boolean;
};

export const gestureCommands: readonly PresetGestureCommand[] = [
  {
    gesture: "one",
    label: "One",
    mark: "1",
    commandName: "Show control guide",
    description: "Show the browser control quick guide inside Signal.",
    actionType: "Signal UI",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "two",
    label: "Two",
    mark: "2",
    commandName: "Focus custom command",
    description: "Bring the Fist command card into view.",
    actionType: "Signal UI",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "three",
    label: "Three",
    mark: "3",
    commandName: "Reset Signal zoom",
    description: "Return the Signal interface to 100% zoom.",
    actionType: "Signal UI",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "four",
    label: "Four",
    mark: "4",
    commandName: "Start focus timer",
    description: "Start a five-minute timer inside Signal.",
    actionType: "Timer",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "five",
    label: "Five",
    mark: "5",
    commandName: "Show command summary",
    description: "Show the active browser workflow status.",
    actionType: "Signal UI",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "thumbs_up",
    label: "Thumbs Up",
    mark: "↑",
    commandName: "Speak encouragement",
    description: "Speak a short confirmation through the browser.",
    actionType: "Speech",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "thumbs_down",
    label: "Thumbs Down",
    mark: "↓",
    commandName: "Pause Signal media",
    description: "Pause audio or video playing inside Signal.",
    actionType: "Signal media",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "c_shape",
    label: "C",
    mark: "C",
    commandName: "Open command creator",
    description: "Open the browser-safe custom command builder.",
    actionType: "Signal UI",
    availability: "ready",
    custom: false,
  },
  {
    gesture: "fist",
    label: "Fist",
    mark: "●",
    commandName: "Custom command",
    description: "Describe it or teach it by recording.",
    actionType: "Programmable",
    availability: "ready",
    custom: true,
  },
] as const;

export const presetGestures = gestureCommands.filter(
  (command) => !command.custom,
);

export const fistGesture = gestureCommands.find(
  (command) => command.gesture === "fist",
)!;
