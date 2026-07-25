import type { Metadata } from "next";
import { SignalBuilder } from "@/components/builder/SignalBuilder";

export const metadata: Metadata = {
  title: "Builder · Signal",
  description:
    "Build, review, export, and share a version 1 Signal gesture profile without an account.",
};

export default function BuilderPage() {
  return <SignalBuilder />;
}
