import { cdnAsset } from "./cdn";

/* Photo crops for cards. Night sky and night water, both on the CDN. */
const night = cdnAsset("/night.jpg");
const water = cdnAsset("/night-water.jpg");

export const scenes = {
  connect: { src: night, position: "50% 30%" },
  talk: { src: water, position: "50% 40%" },
  approve: { src: night, position: "30% 60%" },
  dropIn: { src: water, position: "40% 55%" },
  privacy: { src: night, position: "70% 25%" },
  current: { src: water, position: "50% 35%" },
  context: { src: night, position: "50% 70%" },
  tabs: { src: water, position: "60% 45%" },
  cta: { src: night, position: "50% 40%" },
} as const;

export type SceneKey = keyof typeof scenes;
