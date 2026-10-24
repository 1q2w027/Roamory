import { loadFont as loadInter } from "@remotion/google-fonts/Inter";
import { loadFont as loadSerif } from "@remotion/google-fonts/SourceSerif4";
import { AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { fitSize, useFade, useUnit, type StyleGraphics } from "./common";

const serif = loadSerif("normal", { weights: ["400", "600"], subsets: ["latin", "latin-ext"] }).fontFamily;
const sans = loadInter("normal", { weights: ["500"], subsets: ["latin", "latin-ext"] }).fontFamily;

const accent = "#E8B04B";

/** A bar wipes in from the left, then the lines slide out from behind it. */
const LowerThird = ({ kicker, text, durationInFrames }: { kicker: string | null; text: string; durationInFrames: number }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const unit = useUnit();
  const opacity = useFade(durationInFrames);
  const ease = { easing: Easing.out(Easing.cubic), extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
  const bar = interpolate(frame, [0, Math.round(0.5 * fps)], [0, 1], ease);
  const slide = interpolate(frame, [Math.round(0.15 * fps), Math.round(0.7 * fps)], [-1, 0], ease);
  const size = fitSize(text, unit * 0.05, width * 0.7, 0.5);
  return (
    <AbsoluteFill style={{ justifyContent: "flex-end", padding: unit * 0.08, opacity }}>
      <div style={{ display: "flex", alignItems: "stretch", gap: unit * 0.02 }}>
        <div style={{ width: unit * 0.008, background: accent, transform: `scaleY(${bar})`, transformOrigin: "bottom" }} />
        <div style={{ overflow: "hidden" }}>
          <div style={{ transform: `translateX(${slide * 105}%)` }}>
            {kicker ? (
              <div style={{ fontFamily: sans, fontSize: unit * 0.024, letterSpacing: "0.18em", color: accent, textTransform: "uppercase" }}>
                {kicker}
              </div>
            ) : null}
            <div style={{ fontFamily: serif, fontSize: size, color: "white", textShadow: "0 0 0.3em rgba(0,0,0,0.7)" }}>{text}</div>
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** Calm serif lower thirds; the title carries the place as a kicker. */
export const documentary: StyleGraphics = {
  Title: ({ title, context, durationInFrames }) => {
    const unit = useUnit();
    const opacity = useFade(durationInFrames);
    const place = [context.destination.city, context.destination.country].filter(Boolean).join(", ");
    return (
      <AbsoluteFill>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", opacity }}>
          <div style={{ fontFamily: serif, fontWeight: 600, fontSize: unit * 0.1, color: "white", textShadow: "0 0 0.3em rgba(0,0,0,0.7)" }}>
            {title.text}
          </div>
        </AbsoluteFill>
        <LowerThird kicker={place || null} text={title.subtitle ?? context.trip_type} durationInFrames={durationInFrames} />
      </AbsoluteFill>
    );
  },
  Caption: ({ text, durationInFrames }) => <LowerThird kicker={null} text={text} durationInFrames={durationInFrames} />,
  EndCard: ({ text, durationInFrames }) => {
    const { width } = useVideoConfig();
    const unit = useUnit();
    const opacity = useFade(durationInFrames, false);
    return (
      <AbsoluteFill style={{ background: "black", justifyContent: "center", alignItems: "center", opacity }}>
        <div style={{ fontFamily: serif, fontSize: fitSize(text, unit * 0.06, width * 0.84), color: "white" }}>{text}</div>
        <div style={{ width: unit * 0.06, height: Math.max(1, unit * 0.004), background: accent, marginTop: unit * 0.02 }} />
      </AbsoluteFill>
    );
  },
};
