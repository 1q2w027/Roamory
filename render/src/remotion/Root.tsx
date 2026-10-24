import { Composition, Folder, type CalculateMetadataFunction } from "remotion";
import { exampleProps } from "./examples";
import { Highlight } from "./Highlight";
import { layout } from "./layout";
import type { HighlightProps, Style } from "./types";

/** Size, frame rate and length all come from the edit spec. */
const calculateMetadata: CalculateMetadataFunction<HighlightProps> = ({ props }) => ({
  width: props.spec.output.width,
  height: props.spec.output.height,
  fps: props.spec.output.fps,
  durationInFrames: layout(props.spec).durationInFrames,
});

const STYLES: Style[] = ["cinematic", "reels", "documentary", "vlog"];

export const Root = () => (
  <>
    {/* The service renders this one with the job's props. */}
    <Composition
      id="Highlight"
      component={Highlight}
      defaultProps={exampleProps("cinematic")}
      calculateMetadata={calculateMetadata}
      width={1920}
      height={1080}
      fps={30}
      durationInFrames={1}
    />
    {/* Studio playground: each contract example over the sample clips. */}
    <Folder name="Examples">
      {STYLES.map((style) => (
        <Composition
          key={style}
          id={`Example-${style}`}
          component={Highlight}
          defaultProps={exampleProps(style)}
          calculateMetadata={calculateMetadata}
          width={1920}
          height={1080}
          fps={30}
          durationInFrames={1}
        />
      ))}
    </Folder>
  </>
);
