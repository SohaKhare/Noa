import { FeatureBlock } from "../story/FeatureBlock";
import { KTBrief } from "../scenes/KTBrief";

export function KTFeature() {
  return (
    <FeatureBlock
      index={3}
      total={6}
      eyebrow="Knowledge transfer"
      title="KT without the two-hour call."
      points={[
        "Purpose, open work, decisions and why, who to ask, what to read",
        "Written from real messages and meetings, never invented",
        "Sent on WhatsApp, with a day-7 check-in",
      ]}
      scene={<KTBrief />}
    />
  );
}
