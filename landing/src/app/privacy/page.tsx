import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import { LEGAL_CONTACT } from "@/lib/links";

export const metadata: Metadata = { title: "Privacy policy · Noa", description: "What Noa reads, what it keeps, who it shares it with, and how to get it deleted." };

export default function Privacy() {
  return (
    <LegalPage title="Privacy policy" updated="18 October 2026">
      <p>
        Noa is a company brain built by NotYourIdea. A workspace connects its team chat and Noa turns what people say into tasks, owners, deadlines and decisions. This page
        says what Noa reads, what it keeps, who else sees it, and how to have it removed. The workspace that uses Noa (your employer or team) decides what Noa reads; we
        process that data on its behalf.
      </p>

      <h2>What Noa reads</h2>
      <ul>
        <li>Messages in the chat channels a workspace admin maps to a project. Nothing else in the server or workspace.</li>
        <li>Never direct messages between people. Noa ignores them at the door, before anything is stored.</li>
        <li>When someone edits a message, Noa keeps the new text. When they delete it, Noa erases its text too.</li>
        <li>WhatsApp messages you send to Noa&rsquo;s own number. These are commands and questions to Noa, not team chat, and are not turned into work.</li>
      </ul>

      <h2>What Noa keeps</h2>
      <ul>
        <li>Your account: name, work email, role, and a password hash if you set a password.</li>
        <li>The workspace&rsquo;s org map: projects, people, who works on what, chat handles used to recognise people.</li>
        <li>Messages from mapped channels, with author and time, and what Noa derived from them: tasks, decisions, status and deadline changes, and a link from each back to its message.</li>
        <li>A history of changes to shared work (who changed what, when and why), and a log of those events so the company graph can be rebuilt.</li>
        <li>Your notification choices: channel, WhatsApp number if you give one, digest time and quiet hours, and the messages Noa sent you.</li>
        <li>Counts of AI calls (how many, how large) so admins can see costs. Not what was sent.</li>
      </ul>

      <h2>Who else processes it</h2>
      <p>Noa uses these services to run. Each sees only what its job needs.</p>
      <ul>
        <li>OpenAI, to extract work from messages and to answer questions, when the workspace turns this on. Message text from mapped channels is sent for that purpose.</li>
        <li>Kapso and Meta (WhatsApp Business Platform), to send and receive WhatsApp messages, for people who choose WhatsApp.</li>
        <li>Discord, to read mapped channels and send direct messages, for workspaces that connect it.</li>
        <li>Resend, to send email (invites, sign-in links, notifications).</li>
        <li>Our hosting and database providers, where the data is stored.</li>
      </ul>
      <p>We do not sell personal data or use it for advertising.</p>

      <h2>Who can see what inside a workspace</h2>
      <p>
        People see only the workspace they belong to. Noa&rsquo;s answers cite only what the person asking is allowed to see. Workspace admins manage members, channels and
        roles. NotYourIdea staff access workspace data only to run, secure and support the service.
      </p>

      <h2>How long we keep it</h2>
      <p>
        For as long as the workspace uses Noa. When a workspace is deleted, its data, including its graph, is deleted within 30 days, except where we must keep something
        by law. Backups roll over within the same period.
      </p>

      <h2>Your choices</h2>
      <ul>
        <li>Choose how Noa reaches you, or turn notifications to in-app only, in Settings.</li>
        <li>Ask your workspace admin to stop reading a channel; they can turn it off in Settings.</li>
        <li>Ask for a copy of your data, a correction, or deletion. Write to us; for workspace data we will work with your workspace admin.</li>
      </ul>

      <h2>Security</h2>
      <p>
        Traffic is encrypted in transit. Sessions use secure, http-only cookies. Every request is checked against the workspace&rsquo;s permissions. Webhooks from chat
        providers are verified by signature.
      </p>

      <h2>Contact</h2>
      <p>
        Questions or requests: <a className="underline" href={`mailto:${LEGAL_CONTACT}`}>{LEGAL_CONTACT}</a>. We will update this page when Noa changes what it does with
        data, and change the date above.
      </p>
    </LegalPage>
  );
}
