<script setup lang="ts">
// A box to sign in with a finger (or a mouse). `signed` turns true once something
// is drawn; `toBlob()` gives the signature as a PNG.
const signed = defineModel<boolean>("signed", { default: false });

const canvas = ref<HTMLCanvasElement | null>(null);
let drawing = false;
let last: { x: number; y: number } | null = null;
const { t } = useI18n();

function ctx() {
  return canvas.value?.getContext("2d") ?? null;
}

// keep the drawing sharp on high-density screens and when the box is resized
function fit() {
  const el = canvas.value;
  if (!el) return;
  const ratio = window.devicePixelRatio || 1;
  const { width, height } = el.getBoundingClientRect();
  if (!width || !height) return;
  el.width = Math.round(width * ratio);
  el.height = Math.round(height * ratio);
  const c = ctx();
  if (!c) return;
  c.scale(ratio, ratio);
  c.lineWidth = 2.5;
  c.lineCap = "round";
  c.lineJoin = "round";
  c.strokeStyle = "#111827";
  signed.value = false;
}
// also when the box first gets a size (it may start hidden); never wipe a drawn signature
let observer: ResizeObserver | null = null;
onMounted(() => {
  fit();
  if (canvas.value) {
    observer = new ResizeObserver(() => {
      if (!signed.value) fit();
    });
    observer.observe(canvas.value);
  }
});
onBeforeUnmount(() => observer?.disconnect());

function point(e: PointerEvent) {
  const r = canvas.value!.getBoundingClientRect();
  return { x: e.clientX - r.left, y: e.clientY - r.top };
}
function down(e: PointerEvent) {
  const c = ctx();
  if (!c) return;
  canvas.value?.setPointerCapture(e.pointerId);
  drawing = true;
  last = point(e);
  // a tap leaves a dot
  c.beginPath();
  c.arc(last.x, last.y, 1.2, 0, Math.PI * 2);
  c.fillStyle = "#111827";
  c.fill();
  signed.value = true;
}
function move(e: PointerEvent) {
  if (!drawing || !last) return;
  const c = ctx();
  if (!c) return;
  const p = point(e);
  c.beginPath();
  c.moveTo(last.x, last.y);
  c.lineTo(p.x, p.y);
  c.stroke();
  last = p;
}
function up() {
  drawing = false;
  last = null;
}

function clear() {
  const el = canvas.value;
  const c = ctx();
  if (!el || !c) return;
  c.save();
  c.setTransform(1, 0, 0, 1, 0, 0);
  c.clearRect(0, 0, el.width, el.height);
  c.restore();
  signed.value = false;
}

// the signature on a white background, as a PNG
function toBlob(): Promise<Blob | null> {
  const el = canvas.value;
  if (!el) return Promise.resolve(null);
  const out = document.createElement("canvas");
  out.width = el.width;
  out.height = el.height;
  const c = out.getContext("2d")!;
  c.fillStyle = "#ffffff";
  c.fillRect(0, 0, out.width, out.height);
  c.drawImage(el, 0, 0);
  return new Promise((resolve) => out.toBlob((b) => resolve(b), "image/png"));
}

defineExpose({ toBlob, clear });
</script>

<template>
  <div class="space-y-2">
    <div class="relative overflow-hidden rounded-[10px] border border-dashed border-default bg-white">
      <canvas
        ref="canvas"
        class="block h-40 w-full cursor-crosshair"
        style="touch-action: none"
        @pointerdown.prevent="down"
        @pointermove.prevent="move"
        @pointerup="up"
        @pointercancel="up"
        @pointerleave="up"
      />
      <span v-if="!signed" class="pointer-events-none absolute inset-0 flex items-center justify-center text-sm text-gray-400">{{ t("cs.maintenance.signHere") }}</span>
    </div>
    <UButton v-if="signed" icon="i-lucide-eraser" color="neutral" variant="ghost" size="xs" :label="t('cs.maintenance.clearSignature')" @click="clear" />
  </div>
</template>
