import type { TransitionPresentation, TransitionPresentationComponentProps } from "@remotion/transitions";
import { AbsoluteFill } from "remotion";

type Props = Record<string, never>;

/** A fade through black: the outgoing clip fades to black over the first half, the next fades in over the second. */
const DipToBlack = ({ children, presentationDirection, presentationProgress }: TransitionPresentationComponentProps<Props>) => {
  const p = presentationProgress;
  const opacity = presentationDirection === "exiting" ? Math.max(0, 1 - 2 * p) : Math.max(0, 2 * p - 1);
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

export const dipToBlack = (): TransitionPresentation<Props> => ({ component: DipToBlack, props: {} });
