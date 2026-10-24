import { loadFont as loadHand } from "@remotion/google-fonts/Caveat";
import { loadFont as loadPoppins } from "@remotion/google-fonts/Poppins";
import { AbsoluteFill, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { fitSize, useFade, useUnit, type StyleGraphics } from "./common";

const poppins = loadPoppins("normal", { weights: ["800"], subsets: ["latin", "latin-ext"] }).fontFamily;
const hand = loadHand("normal", { weights: ["700"], subsets: ["latin", "latin-ext"] }).fontFamily;

const sticker = "#FF5A5F";

/** Bouncy sticker labels with a handwritten note. */
export const vlog: StyleGraphics = {
  Title: ({ title, durationInFrames }) => {
    const frame = useCurrentFrame();
    const { fps, width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    const pop = spring({ frame, fps, config: { damping: 9, stiffness: 140 } });
    const note = spring({ frame: frame - 8, fps, config: { damping: 14 } });
    return (
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity }}>
        <div
          style={{
            fontFamily: poppins,
            fontWeight: 800,
            fontSize: fitSize(title.text, unit * 0.11, width * 0.7, 0.65),
            color: "white",
            background: sticker,
            padding: `${unit * 0.01}px ${unit * 0.04}px`,
            borderRadius: unit * 0.03,
            boxShadow: `0 ${unit * 0.01}px 0 rgba(0,0,0,0.35)`,
            transform: `scale(${pop}) rotate(${-3 + (1 - pop) * -10}deg)`,
          }}
        >
          {title.text}
        </div>
        {title.subtitle ? (
          <div
            style={{
              fontFamily: hand,
              fontSize: unit * 0.07,
              color: "white",
              textShadow: "0 0.05em 0.1em rgba(0,0,0,0.6)",
              marginTop: unit * 0.02,
              transform: `translateY(${(1 - note) * unit * 0.05}px) rotate(2deg)`,
              opacity: note,
            }}
          >
            {title.subtitle}
          </div>
        ) : null}
      </AbsoluteFill>
    );
  },
  Caption: ({ text, durationInFrames }) => {
    const frame = useCurrentFrame();
    const { fps } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    const s = spring({ frame, fps, config: { damping: 12 } });
    return (
      <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "flex-start", padding: unit * 0.08, opacity }}>
        <div style={{ fontFamily: hand, fontSize: unit * 0.065, color: "white", textShadow: "0 0.05em 0.1em rgba(0,0,0,0.6)", transform: `translateX(${(1 - s) * -unit * 0.3}px) rotate(-2deg)` }}>
          {text}
        </div>
      </AbsoluteFill>
    );
  },
  EndCard: ({ text, durationInFrames }) => {
    const frame = useCurrentFrame();
    const { fps, width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames, false);
    const pop = spring({ frame, fps, config: { damping: 10 } });
    return (
      <AbsoluteFill style={{ background: "black", justifyContent: "center", alignItems: "center", opacity }}>
        <div style={{ fontFamily: poppins, fontWeight: 800, fontSize: fitSize(text, unit * 0.06, width * 0.8, 0.65), color: sticker, transform: `scale(${0.85 + 0.15 * pop})` }}>
          {text}
        </div>
      </AbsoluteFill>
    );
  },
};
