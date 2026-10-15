import { Children, type ReactNode } from "react";

/* Feature sections at Elf's section rhythm: content on the page, not a second full-screen card. */
export function FeatureStory({ children }: { children: ReactNode }) {
  return (
    <section id="product" aria-label="What Noa does" className="px-5 py-24 sm:py-32">
      <div className="mx-auto flex max-w-7xl flex-col gap-24 sm:gap-32">
        {Children.map(children, (child) => (
          <div>{child}</div>
        ))}
      </div>
    </section>
  );
}
