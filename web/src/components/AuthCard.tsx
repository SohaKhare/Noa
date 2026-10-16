import { useId, type ReactNode } from "react";
import { BrandMark } from "./BrandMark";

/* The card every signed-out page uses: login, invite, reset password. */
export function AuthCard({ title, sub, children, footer }: { title: string; sub?: ReactNode; children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="grid min-h-screen place-items-center p-4 mist-wash">
      <div className="w-full max-w-sm">
        <div className="rounded-[28px] bg-surface p-8 card-shadow">
          <div className="flex items-center gap-2 text-[17px] font-semibold">
            <BrandMark size={28} /> Noa
          </div>
          <h1 className="mt-6 text-[24px] leading-tight font-semibold tracking-[-0.03em]">{title}</h1>
          {sub && <p className="mt-1.5 text-[13.5px] leading-relaxed text-muted">{sub}</p>}
          <div className="mt-6">{children}</div>
        </div>
        {footer && <p className="mt-5 text-center text-[12.5px] text-muted">{footer}</p>}
      </div>
    </div>
  );
}

export function Field({
  label,
  hint,
  error,
  ...props
}: React.ComponentProps<"input"> & { label: string; hint?: string; error?: string }) {
  const id = useId();
  const note = error ?? hint;
  return (
    <div>
      <label htmlFor={id} className="text-[12px] text-muted">
        {label}
      </label>
      <input
        {...props}
        id={id}
        aria-invalid={error ? true : undefined}
        aria-describedby={note ? `${id}-note` : undefined}
        className="mt-1 w-full rounded-xl bg-bg px-3.5 py-2.5 text-[14px] ring-1 ring-transparent focus:ring-2 focus:ring-accent/30 focus:outline-none aria-invalid:ring-bad/40"
      />
      {note && (
        <span id={`${id}-note`} className={`mt-1 block text-[11.5px] ${error ? "text-bad" : "text-muted"}`}>
          {note}
        </span>
      )}
    </div>
  );
}

export function FormError({ children }: { children?: ReactNode }) {
  if (!children) return null;
  return (
    <p role="alert" className="rounded-xl bg-bad/8 px-3.5 py-2.5 text-[13px] text-bad">
      {children}
    </p>
  );
}

export function Notice({ children }: { children: ReactNode }) {
  return <p className="rounded-xl bg-mist/70 px-3.5 py-2.5 text-[13px] text-ink/80">{children}</p>;
}
