import type { Metadata } from "next";
import { headers } from "next/headers";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({ variable: "--font-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-mono", subsets: ["latin"] });

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host") ?? "signal.example";
  const protocol = requestHeaders.get("x-forwarded-proto") ?? (host.includes("localhost") ? "http" : "https");
  const base = new URL(`${protocol}://${host}`);
  const socialImage = new URL("/og.png", base).toString();
  return {
    metadataBase: base,
    title: "Signal — Hand control in your browser",
    description:
      "Local webcam hand tracking, virtual cursor controls, and programmable browser-safe gesture commands—no installation required.",
    icons: { icon: "/favicon.png", shortcut: "/favicon.png" },
    openGraph: {
      title: "Signal — Point. Pinch. Program.",
      description: "A local hand-control interface and programmable command layer for the browser.",
      type: "website",
      images: [{ url: socialImage, width: 1200, height: 630, alt: "Signal browser hand-control interface" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "Signal — Point. Pinch. Program.",
      description: "Your hand is now a programmable interface for Signal in the browser.",
      images: [socialImage],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>
        <a className="skip-link" href="#main-content">Skip to main content</a>
        {children}
      </body>
    </html>
  );
}
