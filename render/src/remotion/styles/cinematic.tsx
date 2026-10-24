import { loadFont } from "@remotion/google-fonts/CormorantGaramond";
import { AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { fitSize, shadow, useFade, useUnit, type StyleGraphics } from "./common";

const { fontFamily } = loadFont("normal", { weights: ["400", "600"], subsets: ["latin", "latin-ext"] });

/** Slow, wide-tracked serif that settles in, with a hairline rule. */
export const cinematic: StyleGraphics = {
  Title: ({ title, durationInFrames }) => {
    const frame = useCurrentFrame();
    const { width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    const progress = interpolate(frame, [0, durationInFrames], [0, 1], { easing: Easing.out(Easing.cubic) });
    const size = fitSize(title.text.toUpperCase(), unit * 0.11, width * 0.84, 0.9);
    return (
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity, fontFamily, color: "white", textShadow: shadow }}>
        <div
          style={{
            fontSize: size,
            fontWeight: 600,
            letterSpacing: `${interpolate(progress, [0, 1], [0.45, 0.25])}em`,
            transform: `scale(${interpolate(progress, [0, 1], [1.06, 1])})`,
            textTransform: "uppercase",
          }}
        >
          {title.text}
        </div>
        <div style={{ width: unit * 0.5 * progress, height: Math.max(1, unit * 0.002), background: "white", margin: unit * 0.025 }} />
        {title.subtitle ? (
          <div style={{ fontSize: unit * 0.045, letterSpacing: "0.2em", fontStyle: "italic" }}>{title.subtitle}</div>
        ) : null}
      </AbsoluteFill>
    );
  },
  Caption: ({ text, durationInFrames }) => {
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    return (
      <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "center", padding: unit * 0.08, opacity }}>
        <div style={{ fontFamily, fontSize: unit * 0.05, fontStyle: "italic", color: "white", textShadow: shadow, textAlign: "center" }}>
          {text}
        </div>
      </AbsoluteFill>
    );
  },
  EndCard: ({ text, durationInFrames }) => {
    const { width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames, false);
    return (
      <AbsoluteFill style={{ background: "black", justifyContent: "center", alignItems: "center", opacity }}>
        <div style={{ fontFamily, fontSize: fitSize(text, unit * 0.06, width * 0.84, 0.7), letterSpacing: "0.3em", color: "white" }}>
          {text.toUpperCase()}
        </div>
      </AbsoluteFill>
    );
  },
};
