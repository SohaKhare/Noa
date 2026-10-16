import { FeatureBlock } from "../story/FeatureBlock";
import { RoleViews } from "../scenes/RoleViews";

export function RolesFeature() {
  return (
    <FeatureBlock
      index={6}
      total={6}
      eyebrow="Every role"
      title="Not just for developers."
      points={[
        "Designers get a brief, ops a runbook",
        "Client servicing sees what was promised to the client",
        "PMs get project state, kept current as work moves",
      ]}
      scene={<RoleViews />}
    />
  );
}
