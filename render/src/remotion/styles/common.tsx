import type React from "react";
import { interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import type { EditSpec, TripContext } from "../types";

export type TitleProps = { title: EditSpec["title"]; context: TripContext; durationInFrames: number };
export type CaptionProps = { text: string; durationInFrames: number };
export type EndCardProps = { text: string; durationInFrames: number };

/** What each style draws over the video. Andrew's designs go in the style files. */
export type StyleGraphics = {
  Title: React.FC<TitleProps>;
  Caption: React.FC<CaptionProps>;
  EndCard: React.FC<EndCardProps>;
};

/** Opacity with short fades in and (optionally) out, like the iOS TitleOverlay: min(0.4 s, a quarter). */
export function useFade(durationInFrames: number, fadeOut = true): number {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const fade = Math.max(1, Math.min(Math.round(0.4 * fps), Math.floor(durationInFrames / 4)));
  const fadeIn = interpolate(frame, [0, fade], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  if (!fadeOut) return fadeIn;
  const out = interpolate(frame, [durationInFrames - fade, durationInFrames], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return Math.min(fadeIn, out);
}

/** Shorter side of the frame; sizes scale with it so 16:9 and 9:16 look alike. */
export function useUnit(): number {
  const { width, height } = useVideoConfig();
  return Math.min(width, height);
}

/** Shrinks a single line to fit `width` (to half size at most). Estimated from the character count. */
export function fitSize(text: string, size: number, width: number, emPerChar = 0.55): number {
  const estimated = text.length * size * emPerChar;
  return estimated <= width ? size : Math.max(size / 2, (size * width) / estimated);
}

export const shadow = "0 0 0.15em rgba(0,0,0,0.8)";
