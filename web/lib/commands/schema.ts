import { z } from "zod";

import { gestureIds } from "../../config/gestureCommands";
import { actionPlanSchema } from "../contracts";
import { isBrowserSafePlan } from "./browser-actions";

export const commandSourceSchema = z.enum([
  "preset",
  "natural_language",
  "recording",
  "hybrid",
]);

export const signalCommandSchema = z
  .object({
    schemaVersion: z.literal(1),
    id: z.string().min(1).max(64).regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/),
    gesture: z.enum(gestureIds),
    name: z.string().min(1).max(80),
    description: z.string().max(500),
    source: commandSourceSchema,
    plan: actionPlanSchema,
    createdAt: z.string().datetime(),
    updatedAt: z.string().datetime(),
    enabled: z.boolean(),
  })
  .strict()
  .superRefine((command, context) => {
    if (!isBrowserSafePlan(command.plan)) {
      context.addIssue({
        code: "custom",
        path: ["plan", "steps"],
        message: "Signal commands may contain browser-safe actions only.",
      });
    }
  });

export const savedCommandEnvelopeSchema = z
  .object({
    storageVersion: z.literal(1),
    command: signalCommandSchema,
  })
  .strict();

export type SignalCommand = z.infer<typeof signalCommandSchema>;
export type CommandSource = z.infer<typeof commandSourceSchema>;

export const FIST_COMMAND_STORAGE_KEY = "signal.fist-command.v1";

export function loadSavedFistCommand(
  storage: Pick<Storage, "getItem">,
): SignalCommand | null {
  const serialized = storage.getItem(FIST_COMMAND_STORAGE_KEY);
  if (!serialized) return null;
  try {
    const parsed = savedCommandEnvelopeSchema.safeParse(JSON.parse(serialized));
    return parsed.success && parsed.data.command.gesture === "fist"
      ? parsed.data.command
      : null;
  } catch {
    return null;
  }
}

export function saveFistCommand(
  storage: Pick<Storage, "setItem">,
  command: SignalCommand,
) {
  const parsed = signalCommandSchema.parse(command);
  if (parsed.gesture !== "fist") {
    throw new Error("Only the fist command may be saved by this editor.");
  }
  storage.setItem(
    FIST_COMMAND_STORAGE_KEY,
    JSON.stringify({ storageVersion: 1, command: parsed }),
  );
}
