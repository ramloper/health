#!/usr/bin/env python3
"""Exercise library validator / merger / reporter (stdlib only).

Usage:
  python3 scripts/validate-library.py [validate] [--require-summaries] [--require-variants]
  python3 scripts/validate-library.py --report
  python3 scripts/validate-library.py merge [--dry-run]
  python3 scripts/validate-library.py release      # add current ids to released-ids.txt (add-only)

Rules: scripts/exercise-data/RULES.md
"""
import glob
import json
import os
import re
import sys
import unicodedata
from collections import Counter, OrderedDict, defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
EX_DIR = os.path.join(ROOT, "Health", "Resources", "Exercises")
PROG_DIR = os.path.join(ROOT, "Health", "Resources", "Programs")
DATA_DIR = os.path.join(ROOT, "scripts", "exercise-data")
DRAFT_DIR = os.path.join(ROOT, ".omc", "drafts", "library")
EXERCISES = os.path.join(EX_DIR, "exercises.json")
VARIANTS = os.path.join(EX_DIR, "variants.json")
BRANDS = os.path.join(EX_DIR, "brands.json")
SLOTS = os.path.join(DATA_DIR, "program-slots.json")
LEGACY = os.path.join(DATA_DIR, "legacy-guides.json")
RELEASED = os.path.join(DATA_DIR, "released-ids.txt")

GROUPS = ["chest", "back", "legs", "shoulders", "arms", "core", "fullbody"]
GROUP_LABEL = {"chest": "가슴", "back": "등", "legs": "하체", "shoulders": "어깨",
               "arms": "팔", "core": "코어", "fullbody": "전신"}
EQUIPMENT = ["barbell", "dumbbell", "cable", "smith", "machine", "bodyweight", "kettlebell", "band"]
PREFIX = {"dumbbell": "db-", "cable": "cable-", "smith": "smith-", "machine": "machine-",
          "kettlebell": "kb-", "band": "band-"}
VARIANT_EQUIPMENT = {"machine", "cable", "smith"}
GROUP_TARGET = {"chest": 34, "back": 44, "legs": 60, "shoulders": 32, "arms": 40, "core": 26, "fullbody": 18}
GROUP_MIN = {"chest": 25, "back": 35, "legs": 45, "shoulders": 25, "arms": 30, "core": 20, "fullbody": 10}
EQUIP_TARGET = {"bodyweight": 34, "kettlebell": 18, "band": 18}
EQUIP_MIN = {"bodyweight": 30, "kettlebell": 15, "band": 15}
TOTAL_MIN = 250
MACHINE_LIKE_MIN = 40
MACHINE_LIKE_TARGET = 60
BRAND_IDS = ["hammer", "technogym", "lifefitness", "cybex", "matrix", "panatta",
             "gym80", "prime", "nautilus", "hoist", "drax", "newtech"]
VARIANTS_PER_BRAND_MIN = 20
VARIANTS_TOTAL_MIN = 240
RESERVED_BARBELL = ["squat", "bench", "deadlift", "ohp"]
RESERVED_OTHER = ["power-clean", "close-grip-bench", "front-squat", "incline-bench"]
FORBIDDEN_IDS = {"other"}
TAGS = {"a", "b", "t1", "t2", "heavy", "volume", "light"}
UNTAGGED_PROGRAMS = {"ss-novice-lp"}
EXPECTED_SLOTS = 135
EXPECTED_NAMES = 57
# §3a TM slot mapping table: (programId, slotId) -> (exerciseId, tag)
TM_MAPPING = {
    ("531-bbb", "squat"): ("squat", None), ("531-bbb", "bench"): ("bench", None),
    ("531-bbb", "deadlift"): ("deadlift", None), ("531-bbb", "ohp"): ("ohp", None),
    ("nsuns-5day", "squat"): ("squat", "t1"), ("nsuns-5day", "squat-t2"): ("squat", "t2"),
    ("nsuns-5day", "bench"): ("bench", "t1"), ("nsuns-5day", "bench-t2"): ("bench", "t2"),
    ("nsuns-5day", "deadlift"): ("deadlift", "t1"), ("nsuns-5day", "dead-t2"): ("deadlift", "t2"),
    ("nsuns-5day", "ohp"): ("ohp", "t1"), ("nsuns-5day", "ohp-t2"): ("ohp", "t2"),
    ("nsuns-5day", "cap"): ("close-grip-bench", "t1"), ("nsuns-5day", "cap-t2"): ("close-grip-bench", "t2"),
    ("ss-novice-lp", "squat"): ("squat", None), ("ss-novice-lp", "bench"): ("bench", None),
    ("ss-novice-lp", "deadlift"): ("deadlift", None), ("ss-novice-lp", "ohp"): ("ohp", None),
    ("ss-novice-lp", "power-clean"): ("power-clean", None),
}
REVIEW_NAMES = ["복근", "카프", "카프 레이즈", "트라이셉스", "인클라인 프레스", "인클라인 벤치",
                "T2 데드", "T2 벤치", "프레스", "컬"]

BASE_ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
BRAND_ID_RE = re.compile(r"^[a-z0-9]+$")
SLUG_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
ORDINAL_RE = re.compile(r"-(v)?\d+$|-(first|second|third|alt|new|old)$")
YEAR_RE = re.compile(r"(?<!\d)(19|20)\d\d(?!\d)")
MODEL_RE = re.compile(r"(?<![A-Za-z])[A-Z]{1,3}-?\d{2,}")
SERIES_ONLY_IN_ALIASES = ["iso-lateral", "isolateral", "selectorized"]
DOT_CHARS = set("-·_‐‑–—・ㆍ‧•")
EXERCISE_KEYS = ["id", "name", "aliases", "group", "equipment", "plane", "isCompound", "summary"]
VARIANT_KEYS = ["id", "exerciseId", "brandId", "name", "aliases"]
BRAND_KEYS = ["id", "name", "englishName"]
SLOT_KEYS = {"programId", "dayId", "slotId", "name", "exerciseId", "progressionTag", "label"}


def norm(s):
    """NFC + casefold + diacritic/width fold + strip whitespace, hyphens, middle dots."""
    s = unicodedata.normalize("NFC", s).casefold()
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    s = unicodedata.normalize("NFKC", s)
    return "".join(c for c in s if not c.isspace() and c not in DOT_CHARS)


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f, object_pairs_hook=OrderedDict)


def dump_list(path, key, items, version=1):
    if items:
        body = ",\n".join("    " + json.dumps(i, ensure_ascii=False) for i in items)
        text = '{\n  "version": %d,\n  "%s": [\n%s\n  ]\n}\n' % (version, key, body)
    else:
        text = '{\n  "version": %d,\n  "%s": []\n}\n' % (version, key)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def walk_strings(obj, path=""):
    if isinstance(obj, str):
        yield path, obj
    elif isinstance(obj, dict):
        for k, v in obj.items():
            yield from walk_strings(k, f"{path}.<key>")
            yield from walk_strings(v, f"{path}.{k}")
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from walk_strings(v, f"{path}[{i}]")


class Checker:
    def __init__(self):
        self.errors = []
        self.warnings = []

    def err(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)


def load_programs():
    programs = OrderedDict()
    for path in sorted(glob.glob(os.path.join(PROG_DIR, "*.json"))):
        p = load(path)
        programs[p["id"]] = p
    return programs


def check_name_tokens(c, owner, name):
    if YEAR_RE.search(name):
        c.err(f"{owner}: name has year-like token: {name!r}")
    if MODEL_RE.search(name):
        c.err(f"{owner}: name has model-number token: {name!r}")
    low = name.casefold()
    for t in SERIES_ONLY_IN_ALIASES:
        if t in low.replace(" ", ""):
            c.err(f"{owner}: series/marketing term {t!r} allowed only in aliases: {name!r}")


def check_text(c, owner, field, value, allow_empty=False):
    if not isinstance(value, str):
        c.err(f"{owner}: {field} must be a string")
        return False
    if "\n" in value or "\r" in value:
        c.err(f"{owner}: {field} contains newline")
    if value != value.strip():
        c.err(f"{owner}: {field} has leading/trailing whitespace: {value!r}")
    if not allow_empty and not value.strip():
        c.err(f"{owner}: {field} is empty")
    return True


def validate(opts, data=None):
    c = Checker()
    ex_doc = data["exercises"] if data else load(EXERCISES)
    var_doc = data["variants"] if data else load(VARIANTS)
    brand_doc = load(BRANDS)
    slots_doc = load(SLOTS)
    legacy_doc = load(LEGACY)
    programs = load_programs()

    # NFC everywhere
    for label, doc in [("exercises.json", ex_doc), ("variants.json", var_doc), ("brands.json", brand_doc),
                       ("program-slots.json", slots_doc), ("legacy-guides.json", legacy_doc)]:
        for p, s in walk_strings(doc):
            if s != unicodedata.normalize("NFC", s):
                c.err(f"{label}{p}: string not NFC: {s!r}")
        if doc.get("version") != 1:
            c.err(f"{label}: top-level version must be 1")

    # ---- exercises ----
    exercises = ex_doc.get("exercises")
    if not isinstance(exercises, list):
        c.err("exercises.json: 'exercises' must be a list")
        exercises = []
    by_id = OrderedDict()
    term_owner = {}
    for i, ex in enumerate(exercises):
        owner = f"exercises[{i}]"
        if not isinstance(ex, dict):
            c.err(f"{owner}: not an object")
            continue
        keys = list(ex.keys())
        missing = [k for k in EXERCISE_KEYS if k not in ex]
        extra = [k for k in keys if k not in EXERCISE_KEYS]
        if missing:
            c.err(f"{owner}: missing fields {missing}")
        if extra:
            c.err(f"{owner}: unknown fields {extra}")
        eid = ex.get("id")
        if not isinstance(eid, str) or not BASE_ID_RE.match(eid):
            c.err(f"{owner}: bad id {eid!r} (expect ASCII kebab-case)")
            continue
        owner = eid
        if eid in by_id:
            c.err(f"{eid}: duplicate id")
        if eid in FORBIDDEN_IDS:
            c.err(f"{eid}: reserved for the special 'other' path, must not be a JSON row")
        by_id[eid] = ex
        group, equip = ex.get("group"), ex.get("equipment")
        if group not in GROUPS:
            c.err(f"{eid}: bad group {group!r}")
        if equip not in EQUIPMENT:
            c.err(f"{eid}: bad equipment {equip!r}")
        else:
            want = PREFIX.get(equip)
            have = next((p for p in PREFIX.values() if eid.startswith(p)), None)
            if want and have != want:
                c.err(f"{eid}: equipment {equip} requires id prefix {want!r}")
            if not want and have:
                c.err(f"{eid}: equipment {equip} must not use prefix {have!r}")
        if ex.get("plane") not in ("upper", "lower"):
            c.err(f"{eid}: bad plane {ex.get('plane')!r}")
        if not isinstance(ex.get("isCompound"), bool):
            c.err(f"{eid}: isCompound must be bool")
        if check_text(c, eid, "name", ex.get("name")):
            check_name_tokens(c, eid, ex["name"])
        aliases = ex.get("aliases")
        if not isinstance(aliases, list) or not aliases:
            c.err(f"{eid}: aliases must be a non-empty list")
            aliases = []
        for a in aliases:
            check_text(c, eid, "alias", a)
        summary = ex.get("summary", "")
        if check_text(c, eid, "summary", summary, allow_empty=True):
            if len(summary) > 60:
                c.err(f"{eid}: summary {len(summary)} chars > 60")
            if opts.get("require_summaries") and not summary.strip():
                c.err(f"{eid}: summary empty (--require-summaries)")
        # duplicate names/aliases (global, normalized)
        seen_local = set()
        for term in [ex.get("name", "")] + [a for a in aliases if isinstance(a, str)]:
            k = norm(term)
            if not k:
                continue
            if k in seen_local:
                c.err(f"{eid}: redundant alias {term!r} (same as own name/alias after normalization)")
                continue
            seen_local.add(k)
            if k in term_owner and term_owner[k] != eid:
                c.err(f"duplicate name/alias {term!r} (normalized {k!r}): {term_owner[k]} vs {eid}")
            else:
                term_owner[k] = eid

    for rid in RESERVED_BARBELL:
        if rid not in by_id:
            c.err(f"reserved id {rid!r} missing")
        elif by_id[rid].get("equipment") != "barbell":
            c.err(f"reserved id {rid!r} must be barbell")
    for rid in RESERVED_OTHER:
        if rid not in by_id:
            c.err(f"reserved id {rid!r} missing")

    groups = Counter(e.get("group") for e in by_id.values())
    equips = Counter(e.get("equipment") for e in by_id.values())
    machine_like = sum(equips[k] for k in VARIANT_EQUIPMENT)
    if len(by_id) < TOTAL_MIN:
        c.err(f"exercise count {len(by_id)} < {TOTAL_MIN}")
    for g, m in GROUP_MIN.items():
        if groups[g] < m:
            c.err(f"group {g}: {groups[g]} < {m}")
    for e, m in EQUIP_MIN.items():
        if equips[e] < m:
            c.err(f"equipment {e}: {equips[e]} < {m}")
    if machine_like < MACHINE_LIKE_MIN:
        c.err(f"machine+cable+smith: {machine_like} < {MACHINE_LIKE_MIN}")
    for g, t in GROUP_TARGET.items():
        if groups[g] < t:
            c.warn(f"group {g}: {groups[g]} below target {t}")
    for e, t in EQUIP_TARGET.items():
        if equips[e] < t:
            c.warn(f"equipment {e}: {equips[e]} below target {t}")
    if machine_like < MACHINE_LIKE_TARGET:
        c.warn(f"machine+cable+smith: {machine_like} below target {MACHINE_LIKE_TARGET}")

    # ---- brands ----
    brands = OrderedDict()
    for i, b in enumerate(brand_doc.get("brands", [])):
        missing = [k for k in BRAND_KEYS if k not in b]
        extra = [k for k in b if k not in BRAND_KEYS]
        if missing or extra:
            c.err(f"brands[{i}]: missing {missing} / unknown {extra}")
        bid = b.get("id")
        if not isinstance(bid, str) or not BRAND_ID_RE.match(bid):
            c.err(f"brands[{i}]: bad id {bid!r}")
            continue
        if bid in brands:
            c.err(f"brand {bid}: duplicate id")
        if bid in by_id:
            c.err(f"brand {bid}: collides with an exercise id")
        check_text(c, f"brand {bid}", "name", b.get("name"))
        check_text(c, f"brand {bid}", "englishName", b.get("englishName"))
        brands[bid] = b
    if list(brands) != BRAND_IDS:
        c.err(f"brands must be exactly {BRAND_IDS} in order, got {list(brands)}")

    # ---- variants ----
    variants = var_doc.get("variants")
    if not isinstance(variants, list):
        c.err("variants.json: 'variants' must be a list")
        variants = []
    var_by_id = OrderedDict()
    per_brand = Counter()
    pair_names = set()
    for i, v in enumerate(variants):
        owner = f"variants[{i}]"
        if not isinstance(v, dict):
            c.err(f"{owner}: not an object")
            continue
        missing = [k for k in VARIANT_KEYS if k not in v]
        extra = [k for k in v if k not in VARIANT_KEYS]
        if missing:
            c.err(f"{owner}: missing fields {missing}")
        if extra:
            c.err(f"{owner}: unknown fields {extra}")
        vid, xid, bid = v.get("id"), v.get("exerciseId"), v.get("brandId")
        owner = vid if isinstance(vid, str) else owner
        if xid not in by_id:
            c.err(f"{owner}: exerciseId {xid!r} does not exist")
        elif by_id[xid].get("equipment") not in VARIANT_EQUIPMENT:
            c.err(f"{owner}: base {xid} equipment {by_id[xid].get('equipment')} not in {sorted(VARIANT_EQUIPMENT)}")
        if bid not in brands:
            c.err(f"{owner}: brandId {bid!r} does not exist")
        if not isinstance(vid, str):
            c.err(f"{owner}: id must be a string")
            continue
        prefix = f"{xid}/{bid}-"
        slug = vid[len(prefix):] if vid.startswith(prefix) else None
        if slug is None or not SLUG_RE.match(slug):
            c.err(f"{vid}: id must be '<exerciseId>/<brandId>-<slug>' (got slug {slug!r})")
        elif ORDINAL_RE.search("-" + slug):
            c.err(f"{vid}: ordinal/numbered slug suffix is not allowed")
        if slug and slug.startswith("u-"):
            c.err(f"{vid}: 'u-' is reserved for user variants")
        if vid in var_by_id:
            c.err(f"{vid}: duplicate variant id")
        if vid in by_id or vid in brands:
            c.err(f"{vid}: collides with exercise/brand id")
        var_by_id[vid] = v
        per_brand[bid] += 1
        if check_text(c, vid, "name", v.get("name")):
            check_name_tokens(c, vid, v["name"])
            key = (xid, bid, norm(v["name"]))
            if key in pair_names:
                c.err(f"{vid}: duplicate variant name {v['name']!r} within ({xid}, {bid})")
            pair_names.add(key)
        aliases = v.get("aliases")
        if not isinstance(aliases, list) or not aliases:
            c.err(f"{vid}: aliases must be a non-empty list")
        else:
            for a in aliases:
                check_text(c, vid, "alias", a)
    if opts.get("require_variants"):
        if len(var_by_id) < VARIANTS_TOTAL_MIN:
            c.err(f"variants total {len(var_by_id)} < {VARIANTS_TOTAL_MIN}")
        for b in BRAND_IDS:
            if per_brand[b] < VARIANTS_PER_BRAND_MIN:
                c.err(f"brand {b}: {per_brand[b]} variants < {VARIANTS_PER_BRAND_MIN}")
    else:
        for b in BRAND_IDS:
            if 0 < per_brand[b] < VARIANTS_PER_BRAND_MIN:
                c.err(f"brand {b}: {per_brand[b]} variants < {VARIANTS_PER_BRAND_MIN}")

    # ---- program slots sidecar ----
    slots = slots_doc.get("slots", [])
    sidecar = OrderedDict()
    for i, s in enumerate(slots):
        extra = [k for k in s if k not in SLOT_KEYS]
        if extra:
            c.err(f"slots[{i}]: unknown fields {extra}")
        key = (s.get("programId"), s.get("dayId"), s.get("slotId"))
        if key in sidecar:
            c.err(f"slots[{i}]: duplicate slot {key}")
        sidecar[key] = s
        if s.get("exerciseId") not in by_id:
            c.err(f"slot {key}: exerciseId {s.get('exerciseId')!r} does not exist")
        tag = s.get("progressionTag")
        if tag is not None and tag not in TAGS:
            c.err(f"slot {key}: bad progressionTag {tag!r}")
        if "label" in s and (not isinstance(s["label"], str) or not s["label"].strip()):
            c.err(f"slot {key}: label must be a non-empty string when present")
    program_slots = OrderedDict()
    names = set()
    for pid, p in programs.items():
        for d in p["days"]:
            for ex in d["exercises"]:
                key = (pid, d["id"], ex["id"])
                program_slots[key] = ex
                names.add(ex["name"])
                s = sidecar.get(key)
                if s is None:
                    c.err(f"program slot {key} ({ex['name']}) missing from program-slots.json")
                elif s.get("name") != ex["name"]:
                    c.err(f"slot {key}: name {s.get('name')!r} != program {ex['name']!r}")
    for key in sidecar:
        if key not in program_slots:
            c.err(f"program-slots.json slot {key} not found in program JSON")
    if len(program_slots) != EXPECTED_SLOTS:
        c.err(f"program slot count {len(program_slots)} != {EXPECTED_SLOTS}")
    if len(names) != EXPECTED_NAMES:
        c.err(f"distinct program exercise names {len(names)} != {EXPECTED_NAMES}")
    for name in sorted(names):
        if norm(name) not in term_owner:
            c.warn(f"program name {name!r} is not a name/alias of any exercise (search won't find it)")

    # tag rule + stateKey invariant
    for pid in programs:
        pslots = [(k, sidecar[k]) for k in program_slots if k[0] == pid and k in sidecar]
        counts = Counter(s["exerciseId"] for _, s in pslots)
        for k, s in pslots:
            tag = s.get("progressionTag")
            if pid in UNTAGGED_PROGRAMS:
                if tag is not None:
                    c.err(f"slot {k}: bundled {pid} must have no progressionTag")
                continue
            if counts[s["exerciseId"]] >= 2 and tag is None:
                c.err(f"slot {k}: {s['exerciseId']} repeats {counts[s['exerciseId']]}x in {pid} -> progressionTag required")
            if counts[s["exerciseId"]] < 2 and tag is not None:
                c.warn(f"slot {k}: tagged {tag!r} but {s['exerciseId']} appears once in {pid}")
            if pid == "nsuns-5day" and tag is not None:
                want = "t2" if k[2].endswith("-t2") else "t1"
                if tag != want:
                    c.err(f"slot {k}: nSuns tag must be {want!r}")
        state = {}
        for k, s in pslots:
            sk = s["exerciseId"] + ("|" + s["progressionTag"] if s.get("progressionTag") else "")
            ex = program_slots[k]
            sig = (ex.get("repMin"), ex.get("repMax"), ex.get("seedKg"))
            if sk in state and state[sk][1] != sig:
                c.err(f"{pid}: stateKey {sk!r} has different repMin/repMax/seedKg: {state[sk][0]} {state[sk][1]} vs {k} {sig}")
            state.setdefault(sk, (k, sig))
        per_day = defaultdict(list)
        for k, s in pslots:
            sk = s["exerciseId"] + ("|" + s["progressionTag"] if s.get("progressionTag") else "")
            per_day[(k[1], sk)].append(k)
        for (day, sk), ks in per_day.items():
            if len(ks) > 1:
                c.err(f"{pid} day {day}: stateKey {sk!r} used by {len(ks)} slots {ks}")
    for (pid, slot), (xid, tag) in TM_MAPPING.items():
        hits = [s for k, s in sidecar.items() if k[0] == pid and k[2] == slot]
        if not hits:
            c.err(f"TM mapping: slot {pid}/{slot} missing")
        for s in hits:
            if s.get("exerciseId") != xid or s.get("progressionTag") != tag:
                c.err(f"TM mapping: {pid}/{slot} must be ({xid}, {tag}), got ({s.get('exerciseId')}, {s.get('progressionTag')})")

    # ---- legacy guides ----
    guides = legacy_doc.get("guides", [])
    if len(guides) != 33:
        c.err(f"legacy-guides.json: {len(guides)} guides != 33")
    gids = Counter(g.get("exerciseId") for g in guides)
    for gid, n in gids.items():
        if n > 1:
            c.err(f"legacy guide id {gid} used {n}x (must be 1:1)")
        if gid not in by_id:
            c.err(f"legacy guide id {gid!r} does not exist")
        elif not by_id[gid].get("summary"):
            c.err(f"legacy guide id {gid}: summary must be set from the guide")

    # ---- released ids lock ----
    if os.path.exists(RELEASED):
        known = set(by_id) | set(brands) | set(var_by_id)
        for line in read_released():
            if line not in known:
                c.err(f"released-ids.txt: {line!r} no longer exists (ids are locked: never rename/delete)")

    ctx = dict(by_id=by_id, brands=brands, variants=var_by_id, per_brand=per_brand, groups=groups,
               equips=equips, machine_like=machine_like, sidecar=sidecar, program_slots=program_slots,
               names=names, term_owner=term_owner, guides=guides, notes=slots_doc.get("notes", {}))
    return c, ctx


def read_released():
    with open(RELEASED, encoding="utf-8") as f:
        return [l.strip() for l in f if l.strip() and not l.startswith("#")]


def print_result(c):
    for w in c.warnings:
        print(f"WARN  {w}")
    for e in c.errors:
        print(f"ERROR {e}")
    print(f"{len(c.errors)} error(s), {len(c.warnings)} warning(s)")


def count_table(ctx):
    out = ["| 근육군 | 개수 | 목표 | 하한 |", "|---|---:|---:|---:|"]
    for g in GROUPS:
        out.append(f"| {g} ({GROUP_LABEL[g]}) | {ctx['groups'][g]} | {GROUP_TARGET[g]} | {GROUP_MIN[g]} |")
    out.append(f"| **합계** | **{len(ctx['by_id'])}** | 254 | {TOTAL_MIN} |")
    out += ["", "| 장비 | 개수 | 목표 | 하한 |", "|---|---:|---:|---:|"]
    for e in EQUIPMENT:
        out.append(f"| {e} | {ctx['equips'][e]} | {EQUIP_TARGET.get(e, '')} | {EQUIP_MIN.get(e, '')} |")
    out.append(f"| machine+cable+smith | {ctx['machine_like']} | {MACHINE_LIKE_TARGET} | {MACHINE_LIKE_MIN} |")
    return out


def report(opts):
    c, ctx = validate(opts)
    by_id = ctx["by_id"]
    out = ["# 운동 라이브러리 검증 리포트", ""]
    out.append(f"- 검증: {len(c.errors)} error(s), {len(c.warnings)} warning(s)")
    out.append(f"- 기본 운동 {len(by_id)} · 브랜드 {len(ctx['brands'])} · 변형 {len(ctx['variants'])}"
               f" · 프로그램 슬롯 {len(ctx['program_slots'])} · 이름 {len(ctx['names'])}")
    out += ["", "## 개수", ""] + count_table(ctx)

    out += ["", "### 근육군 × 장비", ""]
    out.append("| 근육군 | " + " | ".join(EQUIPMENT) + " |")
    out.append("|---|" + "---:|" * len(EQUIPMENT))
    mat = Counter((e["group"], e["equipment"]) for e in by_id.values())
    for g in GROUPS:
        out.append(f"| {g} | " + " | ".join(str(mat[(g, e)]) for e in EQUIPMENT) + " |")

    out += ["", "## 프로그램 이름 57종 → exerciseId", ""]
    out.append("| 이름 | exerciseId (슬롯 수) | 태그 | 별칭 해석 | 메모 |")
    out.append("|---|---|---|---|---|")
    by_name = defaultdict(list)
    for k, s in ctx["sidecar"].items():
        by_name[s["name"]].append((k, s))
    for name in sorted(ctx["names"], key=lambda n: (n not in REVIEW_NAMES, n)):
        rows = by_name.get(name, [])
        ids = Counter(s["exerciseId"] for _, s in rows)
        tags = sorted({f"{k[0]}:{s['progressionTag']}" for k, s in rows if s.get("progressionTag")})
        alias_owner = ctx["term_owner"].get(norm(name), "—")
        mismatch = any(s["exerciseId"] != alias_owner for _, s in rows)
        alias_cell = alias_owner + (" ⚠︎슬롯별 다름" if mismatch else "")
        mark = "**" if name in REVIEW_NAMES else ""
        out.append(f"| {mark}{name}{mark} | " + ", ".join(f"`{i}` ({n})" for i, n in ids.items())
                   + f" | {', '.join(tags) or '—'} | {alias_cell} | {ctx['notes'].get(name, '')} |")

    out += ["", "## 1.0 가이드 33개 → exerciseId", ""]
    out.append("| 가이드 제목 | exerciseId | 이름 | 이미지 | 1.0 별칭 중 다른 곳으로 해석되는 것 |")
    out.append("|---|---|---|---|---|")
    for g in ctx["guides"]:
        img = g["image"] + ("" if g.get("imageAssetExists") else " (자산 없음)")
        name = by_id.get(g["exerciseId"], {}).get("name", "?")
        moved = [f"{a}→{ctx['term_owner'].get(norm(a), '없음')}" for a in g["tableAliases"]
                 if ctx["term_owner"].get(norm(a)) != g["exerciseId"]]
        out.append(f"| {g['title']} | `{g['exerciseId']}` | {name} | {img} | {', '.join(moved) or '—'} |")

    out += ["", "## 브랜드별 변형 수", "", "| 브랜드 | 이름 | 변형 |", "|---|---|---:|"]
    for bid, b in ctx["brands"].items():
        out.append(f"| {bid} | {b['name']} ({b['englishName']}) | {ctx['per_brand'][bid]} |")

    out += ["", "## 기본 운동 목록", "", "| id | 이름 | 근육군 | 장비 | 평면 | 복합 | 별칭 |", "|---|---|---|---|---|---|---|"]
    for e in by_id.values():
        out.append(f"| `{e['id']}` | {e['name']} | {e['group']} | {e['equipment']} | {e['plane']} | "
                   f"{'Y' if e['isCompound'] else ''} | {', '.join(e['aliases'])} |")
    if c.errors or c.warnings:
        out += ["", "## 검증 메시지", ""] + [f"- WARN {w}" for w in c.warnings] + [f"- ERROR {e}" for e in c.errors]
    print("\n".join(out))
    return 1 if c.errors else 0


def merge(opts):
    ex_doc, var_doc = load(EXERCISES), load(VARIANTS)
    by_id = OrderedDict((e["id"], e) for e in ex_doc["exercises"])
    var_ids = {v["id"] for v in var_doc["variants"]}
    errors = []
    frags = sorted(glob.glob(os.path.join(DRAFT_DIR, "*.json")))
    if not frags:
        print(f"no fragments in {DRAFT_DIR}")
        return 1
    for path in frags:
        name = os.path.basename(path)
        try:
            frag = load(path)
        except json.JSONDecodeError as exc:
            errors.append(f"{name}: invalid JSON: {exc}")
            continue
        extra = [k for k in frag if k not in ("version", "author", "exercises", "variants")]
        if extra:
            errors.append(f"{name}: unknown top-level keys {extra}")
        for patch in frag.get("exercises", []):
            eid = patch.get("id")
            bad = [k for k in patch if k not in ("id", "aliases", "summary")]
            if bad:
                errors.append(f"{name}: {eid}: fragments may only add aliases/summary, got {bad}")
                continue
            if eid not in by_id:
                errors.append(f"{name}: {eid!r} is not an existing exercise id (new base ids are 0a-only)")
                continue
            ex = by_id[eid]
            for a in patch.get("aliases", []):
                a = unicodedata.normalize("NFC", a)
                if a not in ex["aliases"]:
                    ex["aliases"].append(a)
            if "summary" in patch:
                s = unicodedata.normalize("NFC", patch["summary"])
                if ex["summary"] and ex["summary"] != s:
                    errors.append(f"{name}: {eid}: summary already set; edit exercises.json directly to change it")
                else:
                    ex["summary"] = s
        for v in frag.get("variants", []):
            v = json.loads(unicodedata.normalize("NFC", json.dumps(v, ensure_ascii=False)), object_pairs_hook=OrderedDict)
            if v.get("id") in var_ids:
                errors.append(f"{name}: variant {v.get('id')!r} already exists")
                continue
            var_ids.add(v.get("id"))
            var_doc["variants"].append(OrderedDict([(k, v[k]) for k in VARIANT_KEYS if k in v] + [(k, v[k]) for k in v if k not in VARIANT_KEYS]))
    for e in errors:
        print(f"ERROR {e}")
    if errors:
        print(f"merge aborted: {len(errors)} error(s); nothing written")
        return 1
    var_doc["variants"].sort(key=lambda v: (v.get("exerciseId", ""), BRAND_IDS.index(v["brandId"]) if v.get("brandId") in BRAND_IDS else 99, v.get("id", "")))
    c, _ = validate(opts, data={"exercises": ex_doc, "variants": var_doc})
    print_result(c)
    if c.errors:
        print("merge aborted: merged result does not validate; nothing written")
        return 1
    if opts.get("dry_run"):
        print(f"dry run OK: {len(frags)} fragment(s), {len(var_doc['variants'])} variants")
        return 0
    dump_list(EXERCISES, "exercises", ex_doc["exercises"], ex_doc.get("version", 1))
    dump_list(VARIANTS, "variants", var_doc["variants"], var_doc.get("version", 1))
    print(f"merged {len(frags)} fragment(s) -> exercises.json, variants.json ({len(var_doc['variants'])} variants)")
    return 0


def release(opts):
    c, ctx = validate(opts)
    print_result(c)
    if c.errors:
        print("release aborted: fix errors first")
        return 1
    current = set(ctx["by_id"]) | set(ctx["brands"]) | set(ctx["variants"])
    old = set(read_released()) if os.path.exists(RELEASED) else set()
    ids = sorted(old | current)
    with open(RELEASED, "w", encoding="utf-8") as f:
        f.write("\n".join(ids) + "\n")
    print(f"released-ids.txt: {len(ids)} ids (+{len(ids) - len(old)})")
    return 0


def main(argv):
    opts = {"require_summaries": "--require-summaries" in argv, "require_variants": "--require-variants" in argv,
            "dry_run": "--dry-run" in argv}
    known = {"--require-summaries", "--require-variants", "--dry-run", "--report", "validate", "merge", "release",
             "-h", "--help"}
    unknown = [a for a in argv if a not in known]
    if unknown or "-h" in argv or "--help" in argv:
        print(__doc__)
        return 2 if unknown else 0
    if "--report" in argv:
        return report(opts)
    if "merge" in argv:
        return merge(opts)
    if "release" in argv:
        return release(opts)
    c, ctx = validate(opts)
    print("\n".join(count_table(ctx)))
    print(f"brands {len(ctx['brands'])}, variants {len(ctx['variants'])}, program slots {len(ctx['program_slots'])}, "
          f"names {len(ctx['names'])}, legacy guides {len(ctx['guides'])}")
    print_result(c)
    return 1 if c.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
