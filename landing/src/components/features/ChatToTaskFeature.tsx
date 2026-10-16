import { FeatureBlock } from "../story/FeatureBlock";
import { ChatToTask } from "../scenes/ChatToTask";

export function ChatToTaskFeature() {
  return (
    <FeatureBlock
      index={1}
      total={6}
      eyebrow="Chat to task"
      title="A reply in chat becomes a task on the board."
      points={[
        "Noa hears it in Discord, Slack, Meet or WhatsApp",
        "It proposes the task with owner, date and the message it came from",
        "Approve once and it lands on the board, live",
      ]}
      scene={<ChatToTask />}
      wide
    />
  );
}
