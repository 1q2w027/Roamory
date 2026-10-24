import cinematic from "../../../contracts/examples/render_request_cinematic.json";
import documentary from "../../../contracts/examples/render_request_documentary.json";
import reels from "../../../contracts/examples/render_request_reels.json";
import vlog from "../../../contracts/examples/render_request_vlog.json";
import type { HighlightProps, RenderRequest, Style } from "./types";

export const exampleRequests = { cinematic, reels, documentary, vlog } as unknown as Record<Style, RenderRequest>;

/** The sample clips scripts/sync-assets.sh copies into public/sample/ (12 s each, one portrait). */
const SAMPLES = ["sample_a", "sample_b", "sample_c", "sample_d"];

/** Props for an example render request, with the sample clips standing in for its moments. */
export function exampleProps(style: Style): HighlightProps {
  const request = exampleRequests[style];
  return {
    spec: request.edit_spec,
    context: request.context,
    clips: Object.fromEntries(
      request.clips.map((c, i) => [c.moment_id, { src: `sample/${SAMPLES[i % SAMPLES.length]}.mp4`, has_audio: c.has_audio }]),
    ),
    music_src: `music/${request.edit_spec.music.track}.m4a`,
  };
}
