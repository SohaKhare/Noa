import { notFound } from "next/navigation";
import { project, projects } from "@/lib/mock";
import { ProjectView } from "./ProjectView";

export function generateStaticParams() {
  return projects.map((p) => ({ id: p.id }));
}

export default async function ProjectPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const p = project(id);
  if (!p) notFound();
  return <ProjectView id={p.id} />;
}
