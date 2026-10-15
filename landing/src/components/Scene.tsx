import Image from "next/image";
import { scenes, type SceneKey } from "@/lib/scenes";

type SceneProps = {
  name: SceneKey;
  sizes?: string;
  className?: string;
  priority?: boolean;
};

/* A crop of the valley painting. */
export function Scene({ name, sizes = "100vw", className = "", priority = false }: SceneProps) {
  const scene = scenes[name];
  return (
    <Image
      src={scene.src}
      alt=""
      fill
      sizes={sizes}
      priority={priority}
      className={`object-cover ${className}`}
      style={{ objectPosition: scene.position }}
    />
  );
}
