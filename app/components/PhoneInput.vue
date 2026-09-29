<script setup lang="ts">
interface Country {
  code: string;
  name: string;
  dial: string;
  flag: string;
}

// Gulf/Levant first (this business's actual customer base), Egypt default.
const countries: Country[] = [
  { code: "EG", name: "Egypt", dial: "20", flag: "🇪🇬" },
  { code: "SA", name: "Saudi Arabia", dial: "966", flag: "🇸🇦" },
  { code: "AE", name: "United Arab Emirates", dial: "971", flag: "🇦🇪" },
  { code: "KW", name: "Kuwait", dial: "965", flag: "🇰🇼" },
  { code: "QA", name: "Qatar", dial: "974", flag: "🇶🇦" },
  { code: "BH", name: "Bahrain", dial: "973", flag: "🇧🇭" },
  { code: "OM", name: "Oman", dial: "968", flag: "🇴🇲" },
  { code: "JO", name: "Jordan", dial: "962", flag: "🇯🇴" },
  { code: "LB", name: "Lebanon", dial: "961", flag: "🇱🇧" },
  { code: "IQ", name: "Iraq", dial: "964", flag: "🇮🇶" },
  { code: "LY", name: "Libya", dial: "218", flag: "🇱🇾" },
  { code: "SD", name: "Sudan", dial: "249", flag: "🇸🇩" },
  { code: "PS", name: "Palestine", dial: "970", flag: "🇵🇸" },
  { code: "YE", name: "Yemen", dial: "967", flag: "🇾🇪" },
  { code: "MA", name: "Morocco", dial: "212", flag: "🇲🇦" },
  { code: "DZ", name: "Algeria", dial: "213", flag: "🇩🇿" },
  { code: "TN", name: "Tunisia", dial: "216", flag: "🇹🇳" },
  { code: "TR", name: "Turkey", dial: "90", flag: "🇹🇷" },
  { code: "GB", name: "United Kingdom", dial: "44", flag: "🇬🇧" },
  { code: "US", name: "United States", dial: "1", flag: "🇺🇸" },
];
const countryItems = countries.map((c) => ({ ...c, label: `${c.flag} +${c.dial} ${c.name}` }));
const countryByCode = new Map(countries.map((c) => [c.code, c]));
// Longest dial code first so e.g. "966" isn't shadowed by a shorter prefix.
const byDialLengthDesc = [...countries].sort((a, b) => b.dial.length - a.dial.length);

const props = withDefaults(
  defineProps<{
    modelValue?: string | null;
    placeholder?: string;
    size?: "xs" | "sm" | "md" | "lg" | "xl";
    disabled?: boolean;
  }>(),
  { modelValue: null, placeholder: undefined, size: undefined, disabled: false },
);
// Emits "" rather than null when cleared — every caller already runs the
// saved value through trimOrNull()/.trim(), so an empty string is the
// simplest common type across the string and string|null fields this binds to.
const emit = defineEmits<{ "update:modelValue": [value: string] }>();

function parseValue(value: string | null | undefined) {
  const raw = value?.trim() ?? "";
  const digits = raw.replace(/[^\d+]/g, "");
  let rest = digits;
  if (rest.startsWith("+")) rest = rest.slice(1);
  else if (rest.startsWith("00")) rest = rest.slice(2);
  else {
    // No recognizable country code — legacy data entered in local format.
    return { code: "EG", national: raw.replace(/^0+/, "") };
  }
  const match = byDialLengthDesc.find((c) => rest.startsWith(c.dial));
  if (!match) return { code: "EG", national: raw.replace(/^0+/, "") };
  return { code: match.code, national: rest.slice(match.dial.length) };
}

const initial = parseValue(props.modelValue);
const selectedCode = ref(initial.code);
const nationalNumber = ref(initial.national);

// Guards against the value we just emitted bouncing back through the parent
// and re-parsing itself (which would be a no-op, but avoids the round trip).
let suppressNextParentSync = false;
watch(
  () => props.modelValue,
  (value) => {
    if (suppressNextParentSync) {
      suppressNextParentSync = false;
      return;
    }
    const parsed = parseValue(value);
    selectedCode.value = parsed.code;
    nationalNumber.value = parsed.national;
  },
);

watch([selectedCode, nationalNumber], () => {
  const dial = countryByCode.get(selectedCode.value)?.dial ?? "20";
  // A leading 0 is the local trunk prefix people type out of habit (e.g.
  // "01012345678") — drop it since the country code already replaces it.
  const digits = nationalNumber.value.replace(/\D/g, "").replace(/^0+/, "");
  suppressNextParentSync = true;
  emit("update:modelValue", digits ? `+${dial}${digits}` : "");
});
</script>

<template>
  <UFieldGroup class="w-full">
    <USelectMenu
      v-model="selectedCode"
      :items="countryItems"
      value-key="code"
      searchable
      :disabled="disabled"
      class="w-28 shrink-0"
      :size="size"
    >
      <template #default>
        <span>{{ countryByCode.get(selectedCode)?.flag }} +{{ countryByCode.get(selectedCode)?.dial }}</span>
      </template>
    </USelectMenu>
    <UInput
      v-model="nationalNumber"
      type="tel"
      class="min-w-0 flex-1"
      :placeholder="placeholder"
      :size="size"
      :disabled="disabled"
    />
  </UFieldGroup>
</template>
