// Fixed by the service; the agent can't change it (guard.ts allows writes only under src/).
import { registerRoot } from "remotion";
import { Root } from "./Root";

registerRoot(Root);
