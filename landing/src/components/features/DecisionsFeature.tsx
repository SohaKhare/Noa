import { FeatureBlock } from "../story/FeatureBlock";
import { DecisionsEdits } from "../scenes/DecisionsEdits";

export function DecisionsFeature() {
  return (
    <FeatureBlock
      index={5}
      total={6}
      eyebrow="Decisions and edits"
      title="Everyone can edit. The right lead always knows."
      points={[
        "See what was decided today, per project and per person",
        "Small edits apply straight away, with undo",
        "Deadline and scope changes wait for the editor's lead",
      ]}
      scene={<DecisionsEdits />}
    />
  );
}
