// Fixed by the service; the agent can't change it (guard.ts allows writes only under src/).
import { Composition, type CalculateMetadataFunction } from "remotion";
import { AgentVideo, durationInFrames } from "./src/Video";

/** The service passes the style preset's output as input props, so the agent can't choose the size or fps. */
export type AgentRootProps = { output: { width: number; height: number; fps: number } };

const calculateMetadata: CalculateMetadataFunction<AgentRootProps> = ({ props }) => ({
  width: props.output.width,
  height: props.output.height,
  fps: props.output.fps,
  durationInFrames,
});

export const Root = () => (
  <Composition
    id="AgentVideo"
    component={AgentVideo}
    defaultProps={{ output: { width: 1920, height: 1080, fps: 30 } }}
    calculateMetadata={calculateMetadata}
    width={1920}
    height={1080}
    fps={30}
    durationInFrames={durationInFrames}
  />
);
