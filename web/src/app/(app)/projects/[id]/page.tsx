import { ProjectView } from "./ProjectView";

/* Projects are addressed by their key, e.g. /projects/veriq. */
export default async function ProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ProjectView projectKey={decodeURIComponent(id)} />;
}
