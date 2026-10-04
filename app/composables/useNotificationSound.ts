// A short two-note chime generated with the Web Audio API (no audio file to
// ship or cache). Browsers only let a page make sound after the user has
// interacted with it, so the context is created/resumed from real clicks and
// key presses (see unlockAudio) — the "Enable notifications" button counts.
let audioContext: AudioContext | null = null;

export function unlockAudio() {
  if (!import.meta.client) return;
  const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctx) return;
  audioContext ??= new Ctx();
  if (audioContext.state === "suspended") audioContext.resume().catch(() => {});
}

export function playNotificationSound() {
  if (!import.meta.client) return;
  try {
    unlockAudio();
    const ctx = audioContext;
    if (!ctx || ctx.state !== "running") return;

    const start = ctx.currentTime;
    // [frequency Hz, offset s] — a rising "ding-ding".
    for (const [frequency, offset] of [
      [880, 0],
      [1318.5, 0.18],
    ] as const) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = frequency;
      gain.gain.setValueAtTime(0.0001, start + offset);
      gain.gain.exponentialRampToValueAtTime(0.35, start + offset + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, start + offset + 0.55);
      osc.connect(gain).connect(ctx.destination);
      osc.start(start + offset);
      osc.stop(start + offset + 0.6);
    }
  } catch {
    // Sound is a nicety; never let it break notification delivery.
  }
}
