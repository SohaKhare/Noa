import Image from "next/image";

/* A photo break between sections, the way Elf spaces its pages. */
export function PhotoBand({ src }: { src: string }) {
  return (
    <div className="px-3 py-2 sm:px-4">
      <div className="relative h-[32vh] min-h-[200px] overflow-hidden rounded-[28px]">
        <Image src={src} alt="" fill sizes="100vw" className="object-cover" />
      </div>
    </div>
  );
}
