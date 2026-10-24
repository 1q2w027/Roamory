import { loadFont } from "@remotion/google-fonts/Anton";
import { AbsoluteFill, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { fitSize, useFade, useUnit, type StyleGraphics } from "./common";

const { fontFamily } = loadFont("normal", { weights: ["400"], subsets: ["latin", "latin-ext"] });

const accent = "#FFD400";

/** Each word springs in a few frames after the last. Used for the title and captions. */
const KineticWords = ({ text, size, color = "white" }: { text: string; size: number; color?: string }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div style={{ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `0 ${size * 0.25}px` }}>
      {text.split(/\s+/).map((word, i) => {
        const s = spring({ frame: frame - i * 3, fps, config: { damping: 12, stiffness: 180 } });
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              fontSize: size,
              color,
              transform: `translateY(${(1 - s) * size * 0.6}px) scale(${0.6 + 0.4 * s}) rotate(${(1 - s) * -6}deg)`,
              opacity: Math.min(1, s * 1.5),
              textShadow: "0 0.06em 0 rgba(0,0,0,0.6)",
            }}
          >
            {word}
          </span>
        );
      })}
    </div>
  );
};

/** Loud, uppercase, word-by-word: built for 9:16. */
export const reels: StyleGraphics = {
  Title: ({ title, durationInFrames }) => {
    const frame = useCurrentFrame();
    const { fps, width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    const tag = spring({ frame: frame - 6, fps, config: { damping: 14 } });
    const text = title.text.toUpperCase();
    return (
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", fontFamily, opacity, padding: unit * 0.06 }}>
        <KineticWords text={text} size={fitSize(text, unit * 0.2, width * 0.88, 0.5)} />
        {title.subtitle ? (
          <div
            style={{
              marginTop: unit * 0.03,
              padding: `${unit * 0.01}px ${unit * 0.03}px`,
              background: accent,
              color: "black",
              fontSize: unit * 0.06,
              transform: `scaleX(${tag}) rotate(-2deg)`,
            }}
          >
            {title.subtitle.toUpperCase()}
          </div>
        ) : null}
      </AbsoluteFill>
    );
  },
  Caption: ({ text, durationInFrames }) => {
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    return (
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", top: "45%", fontFamily, opacity, padding: unit * 0.08 }}>
        <KineticWords text={text.toUpperCase()} size={unit * 0.08} color={accent} />
      </AbsoluteFill>
    );
  },
  EndCard: ({ text, durationInFrames }) => {
    const frame = useCurrentFrame();
    const { fps, width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames, false);
    const s = spring({ frame, fps, config: { damping: 10 } });
    return (
      <AbsoluteFill style={{ background: "black", justifyContent: "center", alignItems: "center", fontFamily, opacity }}>
        <div style={{ fontSize: fitSize(text, unit * 0.09, width * 0.85, 0.5), color: "white", transform: `scale(${0.8 + 0.2 * s})` }}>
          {text.toUpperCase()}
        </div>
      </AbsoluteFill>
    );
  },
};
