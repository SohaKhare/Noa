import { FeatureBlock } from "../story/FeatureBlock";
import { DropIntoProject } from "../scenes/DropIntoProject";

export function StaffingFeature() {
  return (
    <FeatureBlock
      index={2}
      total={6}
      eyebrow="Staffing"
      title="Drag someone to a new project. They arrive briefed."
      points={[
        "One confirm hands over their open tasks and suggests new owners",
        "Repo, channels and Drive access granted from the project's bundle",
        "Their AI agent gets CLAUDE.md, tasks.md and live context",
      ]}
      scene={<DropIntoProject />}
    />
  );
}
