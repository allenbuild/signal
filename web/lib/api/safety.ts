import type { ActionPlan } from "./types";
import { ActionPlanSchema } from "./schema";

function fieldsFromIssues(issues: Array<{ path: PropertyKey[] }>): string[] {
  return [...new Set(issues.map((issue) => issue.path.map(String).join(".") || "plan"))];
}

export function validatePlan(
  value: unknown,
): { ok: true; plan: ActionPlan } | { ok: false; fields: string[] } {
  const result = ActionPlanSchema.safeParse(value);
  return result.success
    ? { ok: true, plan: result.data as ActionPlan }
    : { ok: false, fields: fieldsFromIssues(result.error.issues) };
}

export function planContainsActionType(plan: ActionPlan, actionType: string): boolean {
  const visit = (action: ActionPlan["steps"][number]["action"]): boolean => {
    if (action.type === actionType) return true;
    if (action.type !== "conditional") return false;
    const parameters = action.parameters as {
      ifTrue?: ActionPlan["steps"][number]["action"][];
      ifFalse?: ActionPlan["steps"][number]["action"][];
    };
    return [...(parameters.ifTrue ?? []), ...(parameters.ifFalse ?? [])].some(visit);
  };
  return plan.steps.some((step) => visit(step.action));
}

export { isSafePublicUrl } from "./safety-url";
