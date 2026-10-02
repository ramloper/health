# 운동 라이브러리 데이터 규칙

대상 파일은 `Health/Resources/Exercises/{exercises,variants,brands}.json`, `scripts/exercise-data/program-slots.json`, `scripts/exercise-data/legacy-guides.json`, `scripts/exercise-data/released-ids.txt`예요.
검증은 `python3 scripts/validate-library.py`로 해요. exit 0이 아니면 커밋하지 않아요. 같은 규칙을 Swift `LibraryTests`도 검사해요.

## 1. 파일 스키마

모든 파일의 최상위에 `"version": 1`을 둬요. 배열은 한 줄에 객체 하나씩 써요(diff 검토용, `merge`가 이 형식으로 다시 써요).

`exercises.json`

```json
{ "version": 1, "exercises": [
  { "id": "db-incline-press", "name": "인클라인 덤벨 프레스", "aliases": ["Incline Dumbbell Press", "인클라인 DB 프레스"],
    "group": "chest", "equipment": "dumbbell", "plane": "upper", "isCompound": true, "summary": "" }
] }
```

| 필드 | 규칙 |
|---|---|
| `id` | 영문 kebab-case(`^[a-z0-9]+(-[a-z0-9]+)*$`), 아래 2절 |
| `name` | 한글 이름, NFC, 앞뒤 공백·개행 없음 |
| `aliases` | 1개 이상. 영문 이름, 흔한 한글 표기, 약칭(DB·BB·KB 등) |
| `group` | `chest` `back` `legs` `shoulders` `arms` `core` `fullbody` |
| `equipment` | `barbell` `dumbbell` `cable` `smith` `machine` `bodyweight` `kettlebell` `band` |
| `plane` | `upper` 또는 `lower` |
| `isCompound` | bool |
| `summary` | 한 줄, 60자 이하, 개행 없음. 뼈대 단계에선 `""` 허용, 0b 이후 `--require-summaries`로 필수 |

`brands.json`: `{ "id", "name", "englishName" }` 12개, 순서·id 고정(`hammer` `technogym` `lifefitness` `cybex` `matrix` `panatta` `gym80` `prime` `nautilus` `hoist` `drax` `newtech`).

`variants.json`: `{ "id", "exerciseId", "brandId", "name", "aliases" }`. `exerciseId`·`brandId`는 존재해야 하고, `aliases`는 1개 이상이에요.

## 2. id 규칙

- 기본 운동 id는 영문 kebab-case에 장비 접두사를 붙여요.

  | 장비 | 접두사 | 예 |
  |---|---|---|
  | dumbbell | `db-` | `db-bench-press` |
  | cable | `cable-` | `cable-lat-pulldown` |
  | smith | `smith-` | `smith-squat` |
  | machine | `machine-` | `machine-leg-press` |
  | kettlebell | `kb-` | `kb-swing` |
  | band | `band-` | `band-pull-apart` |
  | barbell | 없음 | `bench`, `bent-over-row`, `curl` |
  | bodyweight | 없음 | `push-up`, `pull-up` |

  바벨과 맨몸이 같은 동작 이름을 쓰면 맨몸 쪽에 다른 통용 이름을 줘요(예 바벨 `squat` / 맨몸 `air-squat`).
- 예약 id(바벨): `squat` `bench` `deadlift` `ohp`. TM 키와 같아야 해서 바꾸지 않아요. 그 밖에 고정 id: `power-clean` `close-grip-bench` `front-squat` `incline-bench`.
- `other`는 JSON 행이 아니에요(앱 코드의 "기타" 특수 경로). `exercises.json`에 넣지 않아요.
- 변형 id: `<exerciseId>/<brandId>-<의미 슬러그>`. 예 `machine-chest-press/hammer-plate-loaded`. 서수·번호 접미사(`-2`, `-v2`, `-new`, `-alt`)는 금지예요.
- 사용자 변형 id: `<exerciseId>/u-<UUID>`(앱이 만들어요). 번들 변형은 슬러그를 `u-`로 시작하지 않아요.
- 일반 변형 id = 기본 운동 id(암묵적, `variants.json`에 쓰지 않아요).
- **출시된 id는 바꾸거나 지우지 않아요.** `released-ids.txt`에 있는 id는 계속 존재해야 해요(추가만 가능). 새 id를 확정하면 `python3 scripts/validate-library.py release`로 잠금 파일에 추가해요.

## 3. 경계 규칙(기본 운동 vs 변형)

- 장비(바벨·덤벨·케이블·스미스·머신·맨몸·케틀벨·밴드), 각도(인클라인·디클라인), 그립(와이드·클로즈·뉴트럴·리버스), 자세(라잉·시티드·스탠딩)가 다르면 **별도 기본 운동**이에요.
  - 예 `bench` / `db-bench-press` / `incline-bench` / `close-grip-bench`, `machine-lying-leg-curl` / `machine-seated-leg-curl`, `cable-lat-pulldown` / `cable-neutral-pulldown`.
- **변형**은 같은 기본 운동을 하는 특정 브랜드·모델·사용자 별명만 가리켜요. "덤벨 벤치프레스"는 변형이 아니에요.
- 선탑재 변형의 기본 운동 장비는 `machine`, `cable`, `smith` 중 하나여야 해요.

## 4. 이름 규칙

- 기본 운동 이름: 한글 통용명. 장비가 이름에 드러나야 구분되면 넣어요(`덤벨 컬`, `케이블 컬`).
- 변형 이름: 한글 범용 형식명(예 "플레이트 로드 체스트 프레스", "선택형 체스트 프레스"). 표시는 앱이 "브랜드명 변형명"으로 붙여요. 이름에 브랜드명을 다시 쓰지 않아요.
  - 연도(`2019`)·모델 번호(`MP-200`, `A12`) 금지. 정규식 `(19|20)\d\d`, `[A-Z]{1,3}-?\d{2,}`로 검사해요.
  - 시리즈·마케팅 이름(`Iso-Lateral`, `Selectorized` 등)은 이름에 쓰지 않고 별칭에만 넣어요.
  - 로고·상표 이미지는 쓰지 않아요.
- 모든 문자열은 NFC로 저장해요.

## 5. 중복 범위

정규화 = NFC → casefold → 발음기호·전각 폴딩 → 공백·하이픈·밑줄·가운뎃점(`·` `ㆍ` `・`) 제거. Swift `SearchNormalizer`와 같아요.

- 기본 운동의 이름과 별칭은 **전역에서** 정규화 후 유일해야 해요(다른 운동과 겹치면 오류, 자기 이름과 같은 별칭도 중복으로 봐요).
- 변형 이름은 `(exerciseId, brandId)` 안에서만 유일하면 돼요. 변형 별칭은 겹쳐도 돼요(시리즈명 공유).

## 6. 프로그램 슬롯 사이드카(`program-slots.json`)

`slots[]` 항목: `{ "programId", "dayId", "slotId", "name", "exerciseId", "progressionTag", "label"? }`. 번들 프로그램 7개의 135슬롯 전부를 1:1로 덮어요. `notes`는 검토용 메모(이름 → 설명)예요. Phase C에서 이 값을 프로그램 JSON에 적용해요.

- `progressionTag` ∈ `a` `b` `t1` `t2` `heavy` `volume` `light` 또는 `null`.
- 한 프로그램 안에서 같은 `exerciseId`가 2슬롯 이상이면 횟수와 무관하게 **모두** 태그를 달아요. 단, 번들 스타팅 스트렝스(`ss-novice-lp`)는 태그 없음.
  - nSuns: 메인 `t1`, T2 슬롯 `t2`. PPL·UL: 날 접미사 `a`/`b`. PHUL: power 날 `heavy`, hypertrophy 날 `volume`. 6일 근비대: 레터럴·푸시다운은 `a`/`b`, 레그프레스·슈러그는 `heavy`/`light`.
- 불변식: 같은 `stateKey`(`exerciseId` 또는 `exerciseId|tag`)면 `repMin/repMax/seedKg`가 같아요. 같은 날 같은 `stateKey` 슬롯은 2개 이상 두지 않아요.
- TM 매핑은 계획 §3a 표 그대로예요(5/3/1·nSuns `squat/bench/deadlift/ohp`, nSuns `cap`·`cap-t2` → `close-grip-bench` `t1`/`t2`, SS `power-clean` → `power-clean`).
- `label`은 표시 접두어예요(`T2`, `라이트`). 표시 이름 = `label + " " + 운동 이름`.

## 7. 병렬 작성(0b)과 merge

- 새 기본 운동 id는 0a 작성자만 만들어요. 0b 작성자는 기존 id만 참조해요.
- 조각 파일: `.omc/drafts/library/<worker>.json`(커밋하지 않아요).

  ```json
  { "version": 1, "author": "worker-1",
    "exercises": [ { "id": "decline-bench", "aliases": ["디클라인 BB 프레스"], "summary": "…" } ],
    "variants":  [ { "id": "machine-chest-press/hammer-plate-loaded", "exerciseId": "machine-chest-press",
                     "brandId": "hammer", "name": "플레이트 로드 체스트 프레스", "aliases": ["Iso-Lateral Chest Press"] } ] }
  ```
- 조각은 기존 운동에 `aliases`를 추가하고 비어 있는 `summary`를 채우는 것, 변형을 추가하는 것만 할 수 있어요. 이미 있는 요약을 바꾸거나 다른 필드를 건드리거나 새 기본 운동 id를 만들면 오류예요.
- 합치기: `python3 scripts/validate-library.py merge --dry-run` → `merge`. 합친 결과가 검증을 통과해야만 파일을 써요.
- 변형 개수: 브랜드에 변형이 하나라도 있으면 그 브랜드는 20개 이상이어야 해요. 0b 이후엔 `--require-variants`(12개 브랜드 전부 20개 이상, 합계 240개 이상)와 `--require-summaries`로 검사해요.

## 8. 명령

```bash
python3 scripts/validate-library.py                     # 기본 검증
python3 scripts/validate-library.py --require-summaries --require-variants   # 0b 이후
python3 scripts/validate-library.py --report > .omc/drafts/library/report.md # 사용자 검토용 표
python3 scripts/validate-library.py merge --dry-run
python3 scripts/validate-library.py release             # released-ids.txt에 현재 id 추가
```
