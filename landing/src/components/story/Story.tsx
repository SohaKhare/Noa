import { AskFeature } from "../features/AskFeature";
import { ChatToTaskFeature } from "../features/ChatToTaskFeature";
import { DecisionsFeature } from "../features/DecisionsFeature";
import { KTFeature } from "../features/KTFeature";
import { RolesFeature } from "../features/RolesFeature";
import { StaffingFeature } from "../features/StaffingFeature";
import { FeatureStory } from "./FeatureStory";

/* Six feature sections over one still. The background does not change between them. */
export function Story() {
  return (
    <FeatureStory>
      <ChatToTaskFeature />
      <StaffingFeature />
      <KTFeature />
      <AskFeature />
      <DecisionsFeature />
      <RolesFeature />
    </FeatureStory>
  );
}
