#!/usr/bin/env bash
# TC3: multi-file refactor on a seeded Next.js app.
# Drops in 3 components that each inline-format a date with toLocaleDateString.
set -euo pipefail
WORKDIR="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tar xzf "$ROOT/templates/nextjs.tar.gz" -C "$WORKDIR"

mkdir -p "$WORKDIR/components" "$WORKDIR/app/profile"

cat > "$WORKDIR/components/note-card.tsx" <<'TSX'
type Props = { title: string; createdAt: string };

export function NoteCard({ title, createdAt }: Props) {
  const when = new Date(createdAt).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
  return (
    <article className="rounded border p-3">
      <h3 className="font-medium">{title}</h3>
      <p className="text-sm opacity-70">{when}</p>
    </article>
  );
}
TSX

cat > "$WORKDIR/components/activity-row.tsx" <<'TSX'
type Props = { action: string; at: string };

export function ActivityRow({ action, at }: Props) {
  const label = new Date(at).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
  return (
    <li className="flex justify-between text-sm">
      <span>{action}</span>
      <span className="opacity-60">{label}</span>
    </li>
  );
}
TSX

cat > "$WORKDIR/app/profile/page.tsx" <<'TSX'
export default function ProfilePage() {
  const joinedAt = "2024-01-15T10:00:00Z";
  const joined = new Date(joinedAt).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
  return (
    <main className="p-6">
      <h1 className="text-xl">Profile</h1>
      <p>Joined {joined}</p>
    </main>
  );
}
TSX

(cd "$WORKDIR" && git init -q && git add -A && git commit -qm seed)
