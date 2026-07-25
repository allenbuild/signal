import type { Metadata } from "next";
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

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://signal-hand.dev",
  ),
  title: {
    default: "signal — Show a gesture. Run a command.",
    template: "%s · Signal",
  },
  description:
    "A private, reviewable gesture command interface for Signal on macOS.",
  openGraph: {
    title: "signal — Show a gesture. Run a command.",
    description:
      "Choose a hand gesture, review its command, and run it with Signal.",
    type: "website",
    images: ["/og.png"],
  },
  twitter: {
    card: "summary_large_image",
    title: "signal — Show a gesture. Run a command.",
    description: "Show a gesture. Run a command.",
    images: ["/og.png"],
  },
};

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
        <a className="skip-link" href="#main-content">
          Skip to content
        </a>
        {children}
      </body>
    </html>
  );
}
