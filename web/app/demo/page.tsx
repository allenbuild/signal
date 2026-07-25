import type { Metadata } from "next";
import { SignalDemo } from "@/components/builder/SignalDemo";

export const metadata: Metadata = {
  title: "Browser Demo · Signal",
  description:
    "Safely simulate Signal’s nine command gestures and reviewed receipts inside the browser.",
};

export default function DemoPage() {
  return <SignalDemo />;
}
