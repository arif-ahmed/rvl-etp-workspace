# এই turn-এর deliverable

প্রম্পট রিভিউ + রিলাইট করা প্রম্পট উপরের মেসেজে দেওয়া হয়েছে — এটাই চূড়ান্ত আউটপুট, চাইলে অন্য কোথাও কপি করে ব্যবহার করা যাবে।

# Approve করলে পরের ধাপ

আমি এই রিলাইট করা প্রম্পটটাই এই workspace-এ execute করব:

1. Read-only exploration — Explore agent দিয়ে ৫টা submodule ঘেঁটে feature list বের করা (controllers, DTOs, workers, Angular/Flutter service calls), `docs/architecture/gobcb-aws-architecture.md`-কে reference ধরা
2. `docs/handover/gobcb-feature-documentation-en.md` তৈরি — trigger-source grouping (Admin Portal / User Portal / User App / Checker App / System-initiated / Cross-cutting) + per-feature template, সব তথ্য আসল কোড থেকে grounded, unverifiable জিনিস `[UNCONFIRMED]`
3. `docs/handover/gobcb-feature-documentation-bn.md` — একই content-structure Bangla-তে (technical term English)
4. শেষে প্রতিটা submodule-এ `git status --porcelain` clean কিনা verify করা

নোট: পুরো প্ল্যাটফর্মের ডক বড় কাজ, তাই source-group ধরে ধরে পর্যায়ক্রমে build করব (আগে Admin Portal group, তারপর বাকিগুলো), দুই ভাষার ফাইল parallel আপডেট হবে।