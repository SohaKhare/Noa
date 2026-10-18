import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import { LEGAL_CONTACT } from "@/lib/links";

export const metadata: Metadata = { title: "Terms · Noa", description: "The terms for using Noa." };

export default function Terms() {
  return (
    <LegalPage title="Terms of use" updated="18 October 2026">
      <p>
        These terms cover your use of Noa, a service run by NotYourIdea. By using Noa you agree to them. If you use Noa for a team or company, you confirm you may agree on
        its behalf.
      </p>

      <h2>The service</h2>
      <p>
        Noa reads the chat channels your workspace maps to projects and turns them into tasks, owners, deadlines and decisions, answers questions about your team&rsquo;s
        work, and sends notifications. Noa is in early access: features change, and we may add, change or remove them.
      </p>

      <h2>Your workspace and your data</h2>
      <ul>
        <li>Your workspace owns the content it brings to Noa. We use it only to provide the service, as described in the privacy policy.</li>
        <li>Workspace admins are responsible for choosing which channels Noa reads and for telling their team that Noa is in use.</li>
        <li>Keep your sign-in details and agent tokens to yourself, and tell us if you think one has leaked.</li>
      </ul>

      <h2>Acceptable use</h2>
      <ul>
        <li>Don&rsquo;t use Noa to break the law or the rules of the chat platforms you connect.</li>
        <li>Don&rsquo;t try to get into workspaces you don&rsquo;t belong to, or to overload or probe the service.</li>
        <li>Don&rsquo;t connect channels whose members have not been told that Noa reads them.</li>
      </ul>

      <h2>AI output</h2>
      <p>
        Noa proposes work and answers questions using AI. It cites where its answers come from, but it can be wrong. Check proposals before you approve them; you remain
        responsible for decisions you make with Noa.
      </p>

      <h2>Availability and liability</h2>
      <p>
        We work to keep Noa available and your data safe, but we provide it as is, without warranties. To the extent the law allows, NotYourIdea is not liable for indirect
        or consequential losses, and our total liability is limited to what you paid us for Noa in the three months before the claim.
      </p>

      <h2>Ending</h2>
      <p>
        You can stop using Noa at any time and ask us to delete your workspace. We may suspend access that breaks these terms. We will tell you before we change these terms
        in a way that matters, and update the date above.
      </p>

      <h2>Contact</h2>
      <p>
        <a className="underline" href={`mailto:${LEGAL_CONTACT}`}>{LEGAL_CONTACT}</a>
      </p>
    </LegalPage>
  );
}
