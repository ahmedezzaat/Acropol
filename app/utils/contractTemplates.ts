// Contract templates: the printed contract (PDF) generated for a contract from what was bought. One template per kind
// of product; the user types the values (the variables) and the system issues the reference number.
// First template: solar water heaters (السخانات الشمسية), for the 200 L and 300 L models (the capacity is a variable).

export interface ContractDocVars {
  /** the contract's date (yyyy-mm-dd) */
  date: string;
  /** الطرف الأول: the owner or whoever acts for them */
  ownerName: string;
  unitAddress: string;
  customerPhone: string;
  /** the person who signs for the company */
  representative: string;
  /** the technical and financial offer number; empty: made from the reference number (2600-<number>) */
  offerNo: string;
  value: number | null;
  /** how many heaters, their size in litres, and anything supplied with them (e.g. a pump) */
  count: number;
  capacity: number;
  extras: string;
  /** the share paid when signing; the rest is paid after installation */
  advancePct: number;
}

export interface ContractBlock {
  heading?: string;
  /** a paragraph; one starting with "- " is a list item; { bold } makes it heavier */
  items: { text: string; bold?: boolean }[];
}

export interface ContractTemplate {
  key: string;
  /** the start of the reference number: "SWH 2026 - 46" */
  prefix: string;
  /** the product categories (by name) this template is made for */
  categoryNames: string[];
  capacities: number[];
  defaults: (ctx: { customerName: string; address: string; phone: string; date: string; value: number | null; count: number }) => ContractDocVars;
  blocks: (v: ContractDocVars, ref: string) => ContractBlock[];
}

export const contractRef = (prefix: string, year: number, seq: number) => `${prefix} ${year} - ${seq}`;

const money = (n: number | null) => (n == null ? "          " : n.toLocaleString("en-US", { maximumFractionDigits: 2 }));
const p = (text: string, bold = false) => ({ text, ...(bold ? { bold: true } : {}) });

const WARRANTY = [
  "-1 جميع أجزاء المنتج تخضع لضمان الشركة خلال فترة الضمان باستثناء الأخطاء والأضرار الناتجة عن أخطاء وسوء الاستعمال والاستخدام المخالف لتعليمات الاستخدام والصيانة في دليل المستخدم (الخدش، الكسر، التمزيق)..",
  "-2 في حالة صيانة المنتج بواسطة أشخاص آخرين غير الخدمة المعتمدة، يلغي ضمان المنتج بالكامل",
  "-3 في حالة عدم سداد الدفعة النهائية محل العقد يعتبر الضمان لاغيا ...",
];

export const heaterTemplate: ContractTemplate = {
  key: "heater",
  prefix: "SWH",
  categoryNames: ["سخانات"],
  capacities: [200, 300],
  defaults: (c) => ({
    date: c.date,
    ownerName: c.customerName,
    unitAddress: c.address,
    customerPhone: c.phone,
    representative: "",
    offerNo: "",
    value: c.value,
    count: c.count,
    capacity: 200,
    extras: "",
    advancePct: 85,
  }),
  blocks: (v, ref) => {
    const offer = v.offerNo.trim() || `2600-${ref.split("-").pop()?.trim() ?? ""}`;
    const equipment = `(عدد ( ${v.count} ) سخان ${v.capacity} لتر${v.extras.trim() ? ` + ${v.extras.trim()}` : ""} )`;
    return [
      {
        heading: "تمهيد",
        items: [
          p(`عهـد الطـرف الاول الى الطرف الثانـى أعمال تنفـيـــذ أعمــال التسخين الشمسي وذلك طبقا للموضح تفصيلًا بالعرض المالي والفني رقم (\u2066${offer}\u2069) والذي يعتبر جزء لا يتجزأ من هذا العقد والذي بحوزة الطرف الثانى الذى يقر إنه قد اطلع على كافة هذه المستندات قبل تقديم اسعاره عن هذه الاعمال.`),
          p("ولما كان العرض المقدم من الطرف الثاني قد اقترن بقبول الطرف الأول لذا فقد اتفق الطرفان وهما بكامل أهليتهما المعتبرة شرعاً وقانوناً علي ما يلي البنود الاتية :"),
        ],
      },
      {
        heading: "البند الأول: التمهيد",
        items: [p("يعتبر التمهيد السابق وعروض الأسعار المقدمة و الرسومات المرفقة وجميع المواصفات الفنية والبرنامج الزمني للتوريد والتنفيذ يعتبر جزءا لا يتجزأ من هذا العقد ومتمماً ومكملًا لجميع بنوده.")],
      },
      {
        heading: "البند الثاني: المعاينة",
        items: [p("يقوم الطرف الثاني بمعاينه للمشروع القائم المعاينة التامة النافية للجهالة ويتعهد بتنفيذ الاعمال المطلوبة موضوع هذا العقد والإشراف عليها طبقا لما تم الاتفاق عليه مع الطرف الأول ويلتزم الطرف الأول بتسليم الموقع بدون أي إعاقات من خامات مدنية كالطوب والأسمنت وغيره مما يعيق حركة الفريق الفني المسؤول ويكون سببا في تعطيل العمل المطلوب تنفيذة")],
      },
      {
        heading: "البند الثالث: نطاق الأعمال",
        items: [
          p("- يلتزم الطرف الثاني بتنفيذ الاعمال طبقا للرسومات المعتمدة من الطرف الأول والمواصفات الفنية المرفقة بالعقد ولا يقوم بتنفذ أي تعديلات خارج الرسومات المعتمدة أو الاعمال المتفق عليها إلا بمحضر كما يلتزم الطرف الأول عند طلب أي تعديلات أو إضافات لم تكن مذكورة في التعاقد أن تكون بمحضر يتم التوقيع عليه من الطرفين أو من ينوب عنهم."),
          p("- يلتزم الطرف الثاني بتنفيذ كافة الأعمال المتفق عليها وفق الجدول الزمني المتفق عليه."),
          p("- العقد لا يشمل أي خامات مدنية من (رمل – أسمنت) الخاصه بأعمال حماية الشبكات والمواسير وطبقة لياسة المواسير كما لا يشمل تكسير بالخرسانات كما لا يشمل توفير سقالات بالموقع أو ونش لرفع المعدات."),
          p("- يلتزم الطرف الأول بتوفير مصدر للكهرباء وتغذية المياه وعمل صرف للمعدات اللازمة لهذه التجهيزات ."),
          p("- يلتزم الطرف الثاني بتشغيل وتسليم المعدات الموردة بمعرفته مع تسليم العميل شرح لطريقة التشغيل."),
          p("- لا يعتد بأي اتفاقات بالموقع إلا بعمل محضر اجتماع موقع من الطرفين."),
          p("- يلتزم الطرف الاول (العميل) بتوفير الحراسة اللازمة للمعدات والخامات والادوات الموجودة بالموقع والموردة للموقع بواسطة الطرف االثاني وتقع مسئولية الحفاظ عليها علي عاتق الطرف الاول"),
        ],
      },
      {
        heading: "البند الرابع: حماية المعدات",
        items: [p("يلتزم الطرف الأول بعمل حماية للمعدات سواء كان من خلال الطرف الثاني بتكلفة إضافية أومن خلال غيره للحفاظ عليها من العوامل الجوية والخارجية .")],
      },
      {
        heading: "البند الخامس: القيمة المالية",
        items: [p(`- اتفق الطرفان علي أن تكون قيمة العقد ( ${money(v.value)} ) جنيه علي ان يطبق علي باقي الدفعات في يوم السداد`, true)],
      },
      {
        heading: "البند السادس: الدفعات",
        items: [
          p(`اتفق الطرفان علي ان يقوم الطرف الاول بسداد قيمة معدات السخانات الشمسية ${equipment} علي دفعات كالآتي :`),
          p("- يقوم الطرف الأول بسداد نسبة:"),
          p(`- ${v.advancePct} % دفعه مقدمه عند التعاقد قيمة الأعمال وتوريد المعدات مقابل ايصال رسمى من الطرف الثاني`),
          p(`- ${100 - v.advancePct} % دفعه بعد تركيب الأعمال مقابل ايصال رسمى من الطرف الثاني.`),
        ],
      },
      {
        heading: "البند السابع: مدة التنفيذ",
        items: [
          p("- مدة التوريد للمعدات : يتم التوريد خلال أسبوع من استكمال دفعة التوريد السابق ذكرها بالبند السابع وجاهزية الموقع للتوريد بناء على معاينة الطرف الثانى ."),
          p("- مدة التركيب للمعدات : خلال أسبوع عمل من جاهزية الموقع للتركيبات وبعد استكمال دفعة التركيب بناء على معاينة الطرف الثاني."),
          p("- مدة التشغيل للمعدات : ثلاثة أيام عمل من جاهزية الموقع للتشغيل واستكمال كامل الدفعات السابقة للتشغيل ."),
        ],
      },
      {
        heading: "البند الثامن: إيقاف الأعمال أو فسخ العقد",
        items: [
          p("- في حالة تأخر الطرف الأول عن سداد الدفعات المستحقة عليه طبقا للمواعيد المحددة في التعاقد بحد اقصي اسبوعين فأنه يحق للطرف الثاني فسخ العقد وإيقاف الأعمال دون الحاجة إلي اخطار أو إنذار أو الحصول علي حكم قضائي مع أحقيتة الطرف الثاني في المطالبة بالتعويضات الناتجة عن هذا التأخير ."),
          p("- في حالة اخلال الطرف الثاني لأي بند من بنود العقد فإنه يحق للطرف الأول أن يمنحه مهلة أسبوعين من تاريخ الإخلال وإخطاره بوقف هذا الإخلال وفي حالة استمرار هذا الإخلال فإنه يحق للطرف الأول اعتبار هذا العقد مفسوخا وإيقاف الأعمال بدون الحاجة إلي اخطار أو إنذار أو إتخاذ أي إجراء قانوني مع أحقيته في المطالبة بالتعويضات الناتجة عن هذا التأخير"),
          p("- في حالة فسخ التعاقد من جانب الطرف الأول وبسبب لا يرجع للطرف الثاني فإنه يحق للطرف الثاني بالرجوع بقيمة الخسائر التي وقعت علي الطرف الثاني وتقدر طبقا لما تم من أعمال ومعاينات ومصاريف إدارية مع أحقيته في المطالبة بالتعويضات الناتجة عن هذا الفسخ."),
          p("- في حالة إيقاف الأعمال أو التأخير او عدم جاهزية الموقع للعمل من جانب الطرف الأول بسبب لا يرجع للطرف الثاني بحد اقصي سنة ميلادية من تاريخ التعاقد فإنه يحق للطرف الثاني اعتبار هذا العقد مفسوخا وإيقاف الأعمال بدون الحاجه الي او اخطار أو اتخاذ أي اجراء قانوني مع أحقيته في المطالبة بالتعويضات الناتجة عن هذا التاخير"),
          p("- اتفق الطرفان أنه في حالة وجود ظروف قهرية أو كوارث طبيعية تمنع استكمال الأعمال يتم حصر الأعمال وتسوية المستحقات بين الطرفين دون أن يكون للطرفين الحق في المطالبة بأي تعويض أيا كان نوعة ."),
          p("- كافة مراسالات الشركه معتمده للطرف الثاني علي الأيميل الخاص بها (INFO@ACROPOL.COM.EG)"),
        ],
      },
      {
        heading: "البند التاسع: ضمان وصيانة الأعمال",
        items: [
          p("في حالة التعاقد علي انظمة التسخين الشمسي :"),
          p("- تتعهد شركة ACROPOL بتنفيذ بنود التعاقد حسب العرض الموضح أعلاه بشرط عدم حدوث قوة قهرية او قرارات حكومية خاصة بالاستيراد تحول دون توريد المعدات و تحتفظ الشركة بحقها في الغاء التعاقد و ورد المبالغ المحصلة من العميل"),
          p("شروط الضمان", true),
          ...WARRANTY.map((w) => p(w)),
        ],
      },
      {
        heading: "البند العاشر: شروط عامة",
        items: [
          p("- يحكم هذا العقد القوانين واللوائح والتعليمات المعمول بها في محاكم جمهورية مصر العربية ويتم التعامل بها في كافة ما يطرأ من نزاع حول بنود التعاقد"),
          p("- يقر الطرفين من أنه قد اتخذ من العنوان الموضح أعلاه محلا مختارا له ."),
          p("- حرر هذا العقد من نسختين سلمت لكل طرف نسخة للعمل بموجبها عند اللزوم ."),
        ],
      },
    ];
  },
};

export const contractTemplates: ContractTemplate[] = [heaterTemplate];
export const templateByKey = (key: string) => contractTemplates.find((t) => t.key === key) ?? null;
/** the template made for what a contract covers: the first whose product category is among the contract's products */
export const templateForCategories = (names: string[]) => contractTemplates.find((t) => t.categoryNames.some((n) => names.includes(n))) ?? null;

// One piece of a printed contract (a heading, a paragraph, the signatures...), measured and put on A4 pages by the print page.
export interface ContractAtomData {
  t: "title" | "center" | "party" | "line" | "u" | "p" | "h2" | "intro" | "sigTitle" | "sig";
  text?: string;
  label?: string;
  bold?: boolean;
  ltr?: boolean;
  // stays on the same page as the piece after it (headings)
  keep?: boolean;
  owner?: string;
  rep?: string;
}
