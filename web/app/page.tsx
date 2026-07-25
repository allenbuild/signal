import type { Metadata } from "next";
import { SignalPage } from "../components/signal/SignalPage";

export const metadata: Metadata = {
  title: "signal",
  description: "Show a gesture. Run a command.",
};

export default function Home() {
  return <SignalPage />;
}
