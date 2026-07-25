import type { Metadata } from "next";
import { headers } from "next/headers";
import { Cormorant_Garamond, Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const signalSerif = Cormorant_Garamond({
  variable: "--font-signal-serif",
  subsets: ["latin"],
  weight: ["500", "600"],
});

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const configuredOrigin = process.env.NEXT_PUBLIC_SITE_URL?.trim();
  const host =
    requestHeaders.get("x-forwarded-host") ??
    requestHeaders.get("host") ??
    "signal.example";
  const protocol =
    requestHeaders.get("x-forwarded-proto") ??
    (host.includes("localhost") ? "http" : "https");
  const metadataBase = configuredOrigin
    ? new URL(configuredOrigin)
    : new URL(`${protocol}://${host}`);
  const socialImage = new URL("/og.png", metadataBase).toString();

  return {
    metadataBase,
    title: {
      default: "signal — Download for Chrome",
      template: "%s · Signal",
    },
    description: "Download the Signal hand-control extension for Chrome.",
    icons: { icon: "/favicon.png", shortcut: "/favicon.png" },
    openGraph: {
      title: "signal — Download for Chrome",
      description: "Hand control and one-shot gesture commands across browser tabs.",
      type: "website",
      images: [
        {
          url: socialImage,
          width: 1731,
          height: 909,
          alt: "Signal browser gesture command interface",
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title: "signal — Download for Chrome",
      description: "Download the Signal hand-control extension for Chrome.",
      images: [socialImage],
    },
  };
}

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body
        className={`${geistSans.variable} ${geistMono.variable} ${signalSerif.variable} antialiased`}
      >
        {children}
      </body>
    </html>
  );
}
