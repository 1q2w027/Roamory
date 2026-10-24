import { linearTiming, TransitionSeries, type TransitionPresentation } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import type React from "react";
import { AbsoluteFill, Html5Audio, interpolate, OffthreadVideo, Sequence, staticFile, useCurrentFrame } from "remotion";
import { dipToBlack } from "./dipToBlack";
import { layout, type PlacedClip } from "./layout";
import { segments } from "./speedRamp";
import { graphics } from "./styles";
import type { HighlightProps, Transition } from "./types";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
/** Music fades out over the last 1.5 s, as on iOS. */
const MUSIC_FADE_OUT_S = 1.5;

const resolve = (src: string) => (/^https?:\/\//.test(src) ? src : staticFile(src));

/** `dissolve` is a plain cross-fade; `fade` dips through black. */
const presentation = (transition: Transition) =>
  (transition === "fade" ? dipToBlack() : fade()) as TransitionPresentation<Record<string, unknown>>;

/**
 * The whole highlight video from one (rebased) edit spec, matching the iOS renderer:
 * clips with transitions, the title over the start, captions while each clip plays alone,
 * a hard cut to the end card, and the music bed under everything.
 */
export const Highlight: React.FC<HighlightProps> = ({ spec, context, clips, music_src }) => {
  const plan = layout(spec);
  const { Title, Caption, EndCard } = graphics[spec.style];
  const gain = 10 ** (spec.music.gain_db / 20);
  const total = plan.durationInFrames;
  const fadeFrames = Math.min(Math.round(MUSIC_FADE_OUT_S * plan.fps), total);

  const series: React.ReactNode[] = [];
  for (const p of plan.clips) {
    if (p.overlapIn > 0) {
      series.push(
        <TransitionSeries.Transition
          key={`t${p.index}`}
          presentation={presentation(p.clip.transition_in)}
          timing={linearTiming({ durationInFrames: p.overlapIn })}
        />,
      );
    }
    series.push(
      <TransitionSeries.Sequence key={`c${p.index}`} durationInFrames={p.durationInFrames} name={p.clip.moment_id}>
        <ClipView placed={p} fps={plan.fps} src={resolve(clips[p.clip.moment_id].src)} audio={!spec.music.duck_original_audio && clips[p.clip.moment_id].has_audio} />
      </TransitionSeries.Sequence>,
    );
  }

  return (
    <AbsoluteFill style={{ background: "black" }}>
      <TransitionSeries>
        {series}
        <TransitionSeries.Sequence durationInFrames={plan.endCard.durationInFrames} name="end card">
          <EndCard text={spec.end_card.text} durationInFrames={plan.endCard.durationInFrames} />
        </TransitionSeries.Sequence>
      </TransitionSeries>

      {plan.clips.map((p) => {
        // While the clip plays alone, and not under the title (Documentary's both sit in the lower third).
        const from = Math.max(p.from + p.overlapIn, plan.titleFrames);
        const length = p.from + p.durationInFrames - p.overlapOut - from;
        if (!p.clip.caption || length <= 0) return null;
        return (
          <Sequence key={`cap${p.index}`} from={from} durationInFrames={length} name="caption">
            <Caption text={p.clip.caption} durationInFrames={length} />
          </Sequence>
        );
      })}

      {plan.titleFrames > 0 ? (
        <Sequence durationInFrames={plan.titleFrames} name="title">
          <Title title={spec.title} context={context} durationInFrames={plan.titleFrames} />
        </Sequence>
      ) : null}

      {music_src ? (
        <Html5Audio
          src={staticFile(music_src)}
          loop
          loopVolumeCurveBehavior="extend"
          volume={(f) => gain * interpolate(f, [total - fadeFrames, total], [1, 0], clamp)}
        />
      ) : null}
    </AbsoluteFill>
  );
};

/**
 * One clip: a run of constant-rate segments (the speed ramp), aspect-filled.
 * A first clip with a transition fades in from black; kept original audio ramps across overlaps.
 */
const ClipView: React.FC<{ placed: PlacedClip; fps: number; src: string; audio: boolean }> = ({ placed, fps, src, audio }) => {
  const frame = useCurrentFrame();
  const { clip, index, durationInFrames, overlapIn, overlapOut } = placed;
  const f = (s: number) => Math.round(s * fps);

  const fadeIn = index === 0 && clip.transition_in !== "cut" ? f(clip.transition_s) : 0;
  const opacity = fadeIn > 0 ? interpolate(frame, [0, fadeIn], [0, 1], clamp) : 1;

  const volumeAt = (clipFrame: number) =>
    Math.min(
      overlapIn > 0 ? interpolate(clipFrame, [0, overlapIn], [0, 1], clamp) : 1,
      overlapOut > 0 ? interpolate(clipFrame, [durationInFrames - overlapOut, durationInFrames], [1, 0], clamp) : 1,
    );

  const segs = segments(clip);
  const starts = segs.map((s) => f(s.output_start_s));
  return (
    <AbsoluteFill style={{ opacity }}>
      {segs.map((s, k) => {
        const from = starts[k];
        const length = (k + 1 < segs.length ? starts[k + 1] : durationInFrames) - from;
        if (length <= 0) return null;
        return (
          <Sequence key={k} from={from} durationInFrames={length} name={s.rate === 1 ? "1x" : `${s.rate.toFixed(2)}x`}>
            <OffthreadVideo
              src={src}
              trimBefore={f(s.source_start_s)}
              playbackRate={s.rate}
              muted={!audio}
              volume={audio ? (vf) => volumeAt(from + vf) : undefined}
              style={{ width: "100%", height: "100%", objectFit: "cover" }}
            />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};
