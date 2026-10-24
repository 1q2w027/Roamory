// Starter composition. The agent replaces this file (and may add others under src/).
import { AbsoluteFill } from "remotion";

/** Length of the whole video in frames, at the preset's fps. Root.tsx reads it. */
export const durationInFrames = 90;

/** The whole highlight video. */
export const AgentVideo = () => (
  <AbsoluteFill style={{ background: "black", color: "white", justifyContent: "center", alignItems: "center", fontSize: 80 }}>
    Replace src/Video.tsx
  </AbsoluteFill>
);
