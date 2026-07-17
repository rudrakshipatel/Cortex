#!/usr/bin/env python3
"""Convert a case written in the Notes long-form format into bulk-import JSON.

Usage:
    python3 scripts/notes_to_case_json.py case.txt > case.json
    pbpaste | python3 scripts/notes_to_case_json.py - > case.json

Reads the "Investigation Menu", "Investigation Results", "Treatment", diagnosis
("Why didn't other diagnosis fit" / "The Differential Diagnosis") and "Clinical
Pearls" sections. Investigations are paired with their results by number, so each
test carries its status, tag, clinical logic and result card; treatments and
diagnoses carry status, tag and clinical logic (they have no result card); each
pearl becomes a title and the note its button opens. Everything it can't place is
reported on stderr rather than dropped silently — paste the output into the admin
app's Bulk Import.

Expected shape (indentation and the <span> wrappers are optional):

    Section 4: The Investigation Menu
    Subsection 1: Pulmonary Physiology & Functional Tests
    1. Spirometry with Bronchodilator Reversibility (Pre- & Post-Albuterol)
       Status: <span style="color:green">CORRECT (Definitive / Segregation Test)</span>
       Clinical Logic: This is the gold standard. ...

    The Investigation Results
    Subsection 1: Pulmonary Physiology & Functional Tests
    1. Spirometry with Bronchodilator Reversibility (Pre- & Post-Albuterol)
       Result Card:
         Baseline FEV1/FVC: 64% (indicative of obstructive defect)
         Post-Bronchodilator FEV1: +15% change (Absolute volume increase of 280 mL)

    Treatment
    Subsection 1: First-Line Controller & Reliever Inhalers
    1. Low-Dose Inhaled Corticosteroid (ICS)-Formoterol (As-Needed / AIR Therapy)
       Status: <span style="color:green">CORRECT (Preferred First-Line)</span>
       Clinical Logic: Under current GINA guidelines, this is the preferred ...

    Post-Case Section 2: Clinical Pearls
    Pearl 1: The "Silent Chest" is a Severe Emergency
       The Pearl: A silent chest in a patient with a severe asthma exacerbation ...
       Clinical Significance: Wheezing is caused by turbulent air rushing ...
       The Game Trap: A player might reassess a struggling patient, note that ...
"""

import json
import re
import sys

# Notes exports bullets as various glyphs; strip them and any <span> markup.
BULLET = re.compile(r"^[\s ]*(?:[•·◦▪\-\*]\s*)*")
TAGS = re.compile(r"<[^>]+>")
NUMBERED = re.compile(r"^(\d+)\.\s+(.*\S)\s*$")
SUBSECTION = re.compile(r"^Subsection\s+\d+:\s*(.+?)\s*$", re.I)
# Pearls are titled rather than numbered like the option lists.
PEARL_ITEM = re.compile(r"^Pearl\s+(\d+)\s*:\s*(.*\S)\s*$", re.I)
PEARL_HEAD = re.compile(r"^(?:Post-Case\s+)?(?:Section\s+\d+:\s*)?(?:The\s+)?Clinical\s+Pearls\s*$", re.I)
# Any "Section N:" / "Post-Case Section N:" heading — ends whichever part we're in.
NUMBERED_HEAD = re.compile(r"^(?:Post-Case\s+)?Section\s+\d+\s*:", re.I)
FIELD = re.compile(r"^(Status|Clinical Logic|Result Card|Mentor|Result)\s*:\s*(.*)$", re.I)
STATUS = re.compile(r"^(CORRECT|INCORRECT)\b\s*(?:\((.*?)\)\s*)?$", re.I)
MENU_HEAD = re.compile(r"^(?:Section\s+\d+:\s*)?(?:The\s+)?Investigations?(?:\s+Menu)?\s*$", re.I)
RESULTS_HEAD = re.compile(r"^(?:Section\s+\d+:\s*)?(?:The\s+)?Investigations?\s+Results\s*$", re.I)
# "Name Status: CORRECT (tag) Clinical Logic: why" all on one line.
INLINE = re.compile(r"^(.*?)\s+Status\s*:\s*(.*?)(?:\s+Clinical\s+Logic\s*:\s*(.*))?$", re.I)
# The vitals table's own header row, under either wording.
VITALS_HEADER = {"metric", "vital sign", "vital", "measurement", "sign"}
META_HEAD = re.compile(r"^(?:Section\s+\d+:\s*)?Patient\s+Information.*$", re.I)
HISTORY_HEAD = re.compile(r"^(?:Section\s+\d+:\s*)?(?:The\s+)?History\s*$", re.I)
EXAM_HEAD = re.compile(r"^(?:Section\s+\d+:\s*)?(?:The\s+)?Physical\s+Examination\s*$", re.I)
INSIGHT_HEAD = re.compile(r"^(?:Post-Case\s+)?(?:Section\s+\d+:\s*)?Core\s+Clinical\s+Insights?\s*$", re.I)
MENTOR_HEAD = re.compile(r"^\W*Mentor\s+Insight\s*$", re.I)
# "Key: value" in the metadata block.
META_FIELD = re.compile(r"^([A-Za-z][A-Za-z /&-]*?)\s*:\s*(.*\S)\s*$")
# The vitals table is tab-separated: "Blood Pressure\t118/76 mmHg".
VITALS_ROW = re.compile(r"^([^\t]+?)\t+(.*\S)\s*$")
VITALS_KEYS = {
    "temperature": "temperature", "blood pressure": "bp", "heart rate": "pr",
    "pulse": "pr", "respiratory rate": "rr", "spo2": "spo2", "spo₂": "spo2",
    "oxygen saturation": "spo2", "bmi": "bmi",
}
TREATMENT_HEAD = re.compile(
    r"^(?:Section\s+\d+:\s*)?(?:The\s+)?(?:Comprehensive\s+)?Treatments?"
    r"(?:\s+(?:Menu|Options?|Plan|Matrix))?\s*$", re.I)
# The diagnosis list, under either heading the note has used for it.
DX_HEAD = re.compile(
    r"^(?:Section\s+\d+:\s*)?(?:The\s+)?(?:"
    r"Differential\s+Diagnos\w+"
    r"|Why\s+didn['’]?t\s+other\s+diagnos\w+\s+fit"
    r"|Why\s+other\s+diagnos\w+\s+didn['’]?t\s+fit"
    r")\s*$", re.I)
# A bare "The …" heading (e.g. "The Differential Diagnosis") — ends whichever
# part we were reading. Deliberately narrow: a handful of words, no colon, so
# authored lines like "The Pearl: …" and "The Game Trap: …" are content, not
# headings. "Section N:" headings are handled by NUMBERED_HEAD.
OTHER_HEAD = re.compile(r"^The\s+(?!Investigation\b)\w+(?:\s+\w+){0,4}$", re.I)


def clean(line):
    """Strip HTML span markup, bullet glyphs and NBSPs from one line."""
    return BULLET.sub("", TAGS.sub("", line).replace(" ", " ")).rstrip()


LEADING = re.compile(r"^[ \t]*")
BULLET_MARK = re.compile(r"^[\u2022\u00b7\u25e6\u25aa\-\*]\s")


def indent_of(raw):
    """Indent depth of a raw line, counting a tab as four spaces."""
    return len(LEADING.match(raw).group(0).replace("\t", "    "))


def is_bulleted(raw):
    return bool(BULLET_MARK.match(raw.lstrip(" \t\u00a0")))


def parse(text):
    tests = {}          # number -> dict
    order = []          # numbers, in the order the menu introduced them
    treatments = {}     # number -> dict (numbered independently of the tests)
    tx_order = []
    diagnoses = {}      # number -> dict
    dx_order = []
    pearls = []         # [{title, body}], in authored order
    meta = {}           # Section 1 "Key: value" lines
    vitals = {}
    # History / Physical Examination: each "* Heading" with sub-bullets becomes a
    # group; the note's Mentor Insight block becomes that card's mentor hint.
    cards = {"presentation": {"groups": [], "bullets": [], "mentor": []},
             "history": {"groups": [], "bullets": [], "mentor": []},
             "exam": {"groups": [], "bullets": [], "mentor": []}}
    insight = []        # Post-Case "Core Clinical Insight" lines
    meta_mode = None    # inside Section 1: None | "vitals"
    in_mentor = False   # inside a history/exam Mentor Insight block
    dropped = []        # headings with nowhere to go, reported at the end
    part = None         # menu|results|treatment|diagnosis|pearls|meta|history|exam|insight
    category = ""
    # Authored numbers restart per subsection in some notes and run straight
    # through in others, so items are keyed by their own order instead.
    seq = {"menu": 0, "results": 0, "treatment": 0, "diagnosis": 0}
    pending = None      # a history/exam bullet held back until we know if it heads a group
    current = None      # sequence number being filled
    field = None        # multi-line field currently collecting
    problems = []

    for raw in text.splitlines():
        line = clean(raw)
        if not line.strip():
            continue
        raw_indent, bulleted = indent_of(raw), is_bulleted(raw)

        head = line.strip()
        if META_HEAD.match(head):
            part, meta_mode, in_mentor = "meta", None, False
            continue
        if HISTORY_HEAD.match(head) or EXAM_HEAD.match(head):
            part = "history" if HISTORY_HEAD.match(head) else "exam"
            in_mentor, pending = False, None
            card = cards[part]
            # The section appearing twice means the note was revised — the later
            # copy wins rather than doubling up.
            if card["groups"] or card["bullets"] or card["mentor"]:
                problems.append(f"'{head}' appears twice — using the later one")
                card["groups"], card["bullets"], card["mentor"] = [], [], []
            continue
        if INSIGHT_HEAD.match(head):
            part, in_mentor = "insight", False
            continue
        if MENU_HEAD.match(head):
            part, current, field, category = "menu", None, None, ""
            seq["menu"] = 0
            continue
        if RESULTS_HEAD.match(head):
            part, current, field, category = "results", None, None, ""
            seq["results"] = 0
            continue
        if TREATMENT_HEAD.match(line.strip()):
            part, current, field, category = "treatment", None, None, ""
            seq["treatment"] = 0
            continue
        if DX_HEAD.match(line.strip()):
            part, current, field, category = "diagnosis", None, None, ""
            seq["diagnosis"] = 0
            continue
        if PEARL_HEAD.match(line.strip()):
            part, current, field, category = "pearls", None, None, ""
            continue
        if part and NUMBERED_HEAD.match(line.strip()):
            part = None  # a new numbered section we don't read (e.g. Post-Case Section 1)
            continue
        if part and OTHER_HEAD.match(line.strip()) and not SUBSECTION.match(line.strip()):
            part = None  # left for another part (the differential, say)
            continue
        if part is None:
            continue
        if part not in ("history", "exam") and pending is not None:
            pending = None

        # Section 1 — metadata, demographics, chief complaint and the vitals table.
        if part == "meta":
            if head.lower().startswith("vital"):
                meta_mode = "vitals"
                continue
            if meta_mode == "vitals":
                row = VITALS_ROW.match(raw.rstrip())
                if row:
                    label, value = row.group(1).strip().lower(), row.group(2).strip()
                    if label in VITALS_HEADER:      # the table's own header row
                        continue
                    key = VITALS_KEYS.get(label)
                    if key:
                        vitals[key] = value
                    else:
                        dropped.append(f"vital sign '{row.group(1).strip()}' has no field in the app")
                    continue
            f = META_FIELD.match(head)
            if f:
                meta[f.group(1).strip().lower()] = f.group(2).strip()
            continue

        # Sections 2 & 3 — "* Heading" + indented findings, then a Mentor Insight
        # block. Unbulleted headings (e.g. "General Examination") only organise
        # the note; the app's card has no place for them.
        if part in ("history", "exam"):
            card = cards[part]
            if MENTOR_HEAD.match(head):
                pending = flush(card, pending)
                in_mentor = True
                continue
            if in_mentor:
                if bulleted:
                    card["mentor"].append(head)
                continue
            if not bulleted:
                pending = flush(card, pending)
                dropped.append(f"{part} line '{head[:60]}' (the card has no place for it)")
                continue
            if raw_indent == 0:
                # Held back: a top-level bullet is a heading only if findings are
                # nested under it, otherwise it's a bullet in its own right.
                pending = flush(card, pending)
                pending = head
            elif pending is not None:
                card["groups"].append({"system": pending, "findings": [head]})
                pending = None
            elif card["groups"]:
                card["groups"][-1]["findings"].append(head)
            else:
                card["bullets"].append(head)
            continue

        # Post-Case Core Clinical Insight — kept verbatim, line for line.
        if part == "insight":
            insight.append(head)
            continue

        # Pearls: a "Pearl N: Title" line opens one, every line under it is the
        # note its button opens (the authored "The Pearl / Clinical Significance
        # / The Game Trap" lines are kept verbatim).
        if part == "pearls":
            p = PEARL_ITEM.match(line.strip())
            if p:
                pearls.append({"title": p.group(2), "body": ""})
            elif pearls:
                pearls[-1]["body"] = (pearls[-1]["body"] + "\n" + line.strip()).strip()
            continue

        sub = SUBSECTION.match(line.strip())
        if sub:
            category, current, field = sub.group(1), None, None
            continue

        num = NUMBERED.match(line.strip())
        if num:
            name = num.group(2)
            # Status / Clinical Logic may sit on this same line rather than under it.
            inline = INLINE.match(name)
            status_value = rationale_value = None
            if inline:
                name, status_value, rationale_value = inline.group(1).strip(), inline.group(2).strip(), (inline.group(3) or "").strip()
            seq[part] += 1
            n = seq[part]
            current, field = n, None
            bag = {"treatment": treatments, "diagnosis": diagnoses}.get(part, tests)
            keys = {"treatment": tx_order, "diagnosis": dx_order}.get(part, order)
            if part == "results":
                # Whatever follows the name is the result card, with or without
                # an explicit "Result Card:" label.
                field = "result"
                # Results are matched to the menu by position: the note numbers
                # them straight through while the menu restarts each subsection.
                if n not in tests:
                    problems.append(f"result {n} ({name}) has no matching investigation")
                    tests[n] = blank(); tests[n]["name"] = name; order.append(n)
                elif norm_name(tests[n]["name"]) != norm_name(name):
                    problems.append(
                        f"investigation {n} is '{tests[n]['name']}' in the menu but "
                        f"'{name}' in the results — matched by position")
            else:
                bag.setdefault(n, blank())
                bag[n]["name"] = name
                if part != "diagnosis":
                    bag[n]["category"] = category
                keys.append(n)
                if status_value is not None:
                    st = STATUS.match(status_value)
                    if st:
                        bag[n]["helpful"] = st.group(1).upper() == "CORRECT"
                        bag[n]["tag"] = (st.group(2) or "").strip()
                    else:
                        what = {"treatment": "treatment", "diagnosis": "diagnosis"}.get(part, "test")
                        problems.append(f"{what} {n}: unreadable status {status_value!r}")
                if rationale_value:
                    bag[n]["rationale"] = rationale_value
                    field = "rationale"
            continue

        if current is None:
            continue

        bag = {"treatment": treatments, "diagnosis": diagnoses}.get(part, tests)
        f = FIELD.match(line.strip())
        if f:
            key, value = f.group(1).lower(), f.group(2).strip()
            t = bag[current]
            if key == "status":
                st = STATUS.match(value)
                if st:
                    t["helpful"] = st.group(1).upper() == "CORRECT"
                    t["tag"] = (st.group(2) or "").strip()
                else:
                    what = {"treatment": "treatment", "diagnosis": "diagnosis"}.get(part, "test")
                    problems.append(f"{what} {current}: unreadable status {value!r}")
                field = None
            elif key == "clinical logic":
                t["rationale"] = value
                field = "rationale"
            elif key == "mentor":
                t["mentor"] = value
                field = "mentor"
            else:  # Result Card / Result — the card's lines follow beneath it
                t["result"] = value
                field = "result"
            continue

        # A continuation line of whatever field we're inside.
        if field:
            t = bag[current]
            t[field] = (t[field] + "\n" + line.strip()).strip()

    for key in ("history", "exam"):
        if pending is not None:
            pending = flush(cards[key], pending)

    def check(bag, keys, what):
        for n in keys:
            t = bag[n]
            if t["helpful"] is None:
                problems.append(f"{what} {n} ({t['name']}) has no Status — defaulting to incorrect")
                t["helpful"] = False
            if not t["rationale"]:
                problems.append(f"{what} {n} ({t['name']}) has no Clinical Logic — its bubble won't open")

    check(tests, order, "test")
    check(treatments, tx_order, "treatment")
    check(diagnoses, dx_order, "diagnosis")

    for p in pearls:
        if not p["body"]:
            problems.append(f"pearl '{p['title']}' has no text — its bubble won't open")

    dx = [diagnoses[n] for n in dx_order]
    if dx:
        right = [d["name"] for d in dx if d["helpful"]]
        if len(right) != 1:
            problems.append(
                f"the diagnosis list needs exactly one CORRECT answer, found {len(right)}"
                + (f": {', '.join(right)}" if right else "")
            )
        if len(dx) < 2:
            problems.append("a case needs at least 2 diagnoses to choose between")

    return {
        "tests": [tests[n] for n in order],
        "treatments": [treatments[n] for n in tx_order],
        "diagnoses": dx,
        "pearls": pearls,
        "meta": meta,
        "vitals": vitals,
        "cards": cards,
        "insight": "\n".join(insight),
        "dropped": dropped,
        "problems": problems,
    }


def flush(card, pending):
    """A held-back top-level bullet had nothing nested under it — it's a bullet."""
    if pending is not None:
        card["bullets"].append(pending)
    return None


def norm_name(s):
    """Loose name key — word order and punctuation aside, is this the same test?"""
    return " ".join(sorted(re.sub(r"[^a-z0-9 ]+", " ", s.lower()).split()))


def blank():
    return {"category": "", "name": "", "result": "", "helpful": None,
            "mentor": "", "rationale": "", "tag": ""}


def as_treatment(t):
    """Treatments carry `appropriate` instead of `helpful`, and have no result."""
    return {"category": t["category"], "name": t["name"], "appropriate": t["helpful"],
            "rationale": t["rationale"], "tag": t["tag"]}


def as_diagnosis(d):
    """Diagnoses carry `correct`, and have no category or result."""
    return {"name": d["name"], "correct": d["helpful"], "rationale": d["rationale"], "tag": d["tag"]}


def as_card(card):
    """A history / examination section: groups, any flat bullets, mentor hint."""
    out = {}
    if card["bullets"]:
        out["bullets"] = card["bullets"]
    if card["groups"]:
        out["groups"] = card["groups"]
    if card["mentor"]:
        out["mentor"] = "\n".join(card["mentor"])
    return out


def strip_quotes(v):
    return v.strip().strip('"').strip("“”").strip()


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "-"
    text = sys.stdin.read() if src == "-" else open(src, encoding="utf-8").read()

    r = parse(text)
    tests, treatments, diagnoses, pearls = r["tests"], r["treatments"], r["diagnoses"], r["pearls"]
    meta, problems = r["meta"], r["problems"]
    if not tests and not treatments and not diagnoses and not pearls:
        sys.exit("Found nothing to import. Is this the right part of the note?")

    def m(*keys, default=""):
        for k in keys:
            if meta.get(k):
                return meta[k]
        return default

    # Keys follow the order a case is authored and played: who the patient is,
    # then Chief Complaint → History → Physical Examination → Tests → Diagnosis
    # → Treatment → the answer.
    chief = strip_quotes(m("chief complaint", default="TODO"))
    case = {}
    if m("case title"):
        case["title"] = strip_quotes(m("case title"))
    case["specialty"] = m("specialty", default="TODO")
    case["patientName"] = m("name", "patient name", default="TODO")
    case["gender"] = m("sex", "gender", default="")
    case["age"] = m("age")
    for key, *names in (("difficultyLabel", "difficulty"), ("setting", "setting"),
                        ("occupation", "occupation"), ("duration", "duration"),
                        ("guidelineFocus", "guideline focus", "guidelines")):
        if m(*names):
            case[key] = m(*names)
    if r["vitals"]:
        case["vitals"] = r["vitals"]

    # 1. Chief Complaint — the complaint in the patient's own words, so it's read
    #    inside the case and not only on the home card.
    case["chiefComplaint"] = chief
    presentation = as_card(r["cards"]["presentation"])
    if chief and chief != "TODO":
        presentation.setdefault("bullets", []).insert(0, chief)
    if presentation:
        case["presentation"] = presentation
    # 2. History  3. Physical Examination
    for key, section in (("history", "history"), ("examination", "exam")):
        card = as_card(r["cards"][section])
        if card:
            case[key] = card
    # 4. Tests  5. Diagnosis  6. Treatment
    case["tests"] = tests
    case["diagnosisQuestion"] = "Which diagnosis best fits this presentation?"
    case["diagnoses"] = ([as_diagnosis(d) for d in diagnoses] or
                         [{"name": "TODO", "correct": True}, {"name": "TODO", "correct": False}])
    case["treatments"] = [as_treatment(t) for t in treatments]
    # 7. The answer.
    mi = {}
    if r["insight"]:
        mi["reasoning"] = r["insight"]
    if pearls:
        mi["pearls"] = pearls
    if mi:
        case["mentorInsight"] = mi
    payload = {"clinical": [case]}

    print(json.dumps(payload, indent=2, ensure_ascii=False))

    # Anything the note carries that the app has no field for — reported, never
    # quietly dropped.
    unused = [f"{k}: {v}" for k, v in meta.items()
              if k not in ("case title", "specialty", "name", "patient name", "sex", "gender",
                           "age", "chief complaint", "difficulty", "setting", "occupation",
                           "duration", "guideline focus", "guidelines")]
    if unused or r["dropped"]:
        print("\nIn the note but with no field in the app:", file=sys.stderr)
        for u in unused + r["dropped"]:
            print(f"  • {u}", file=sys.stderr)
    if problems:
        print(f"\n{len(problems)} thing(s) to check:", file=sys.stderr)
        for p in problems:
            print(f"  • {p}", file=sys.stderr)

    def tally(items, what):
        return f"{len(items)} {what} ({sum(1 for i in items if i['helpful'])} correct)"
    print("\nParsed " + ", ".join([tally(tests, "investigations"), tally(treatments, "treatments"),
                                   tally(diagnoses, "diagnoses"), f"{len(pearls)} pearls"]) + ".",
          file=sys.stderr)


if __name__ == "__main__":
    main()
