import { FeatureBlock } from "../story/FeatureBlock";
import { AskNoa } from "../scenes/AskNoa";

export function AskFeature() {
  return (
    <FeatureBlock
      index={4}
      total={6}
      eyebrow="@noa"
      title="Ask anything. Get the answer and the receipt."
      points={[
        "Tag @noa in any channel your team already uses",
        "Every claim links to the message or meeting behind it",
        "Only uses what the person asking is allowed to see",
      ]}
      scene={<AskNoa />}
    />
  );
}
