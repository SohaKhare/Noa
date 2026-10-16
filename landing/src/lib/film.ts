/*
  Unused camera stops from an earlier valley film. Photos now come from the CDN.
*/
import { cdnAsset } from "./cdn";

export const valleyStill = cdnAsset("/night.jpg");

export const valleyFilm = {
  poster: cdnAsset("/night.jpg"),
  sources: [] as { src: string; type: string }[],
} as const;

/** Camera stops, in story order. x/y are transform-origin percents. */
export const valleyFrames = [
  { x: 48, y: 54, scale: 1.9 },
  { x: 34, y: 56, scale: 2.35 },
  { x: 76, y: 70, scale: 2.15 },
  { x: 50, y: 18, scale: 1.65 },
  { x: 40, y: 48, scale: 2.1 },
  { x: 50, y: 46, scale: 1.12 },
] as const;

export const storyLabels = ["Chat to task", "Staffing", "KT", "@noa", "Decisions", "Every role"] as const;
