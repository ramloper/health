import Foundation

/// Step-by-step guide text for the 33 exercises that shipped with 1.0, keyed by library exercise id.
/// Every other exercise only has the one-line library summary (see `GuideContent`).
struct GuideDetail: Equatable {
    /// 1.0 guide title, kept for reference; the sheet shows the library display name.
    var title: String
    var muscle: String
    var summary: String
    var steps: [String]
    var avoid: [String]
    var imageName: String?

    static func detail(forExerciseId exerciseId: String) -> GuideDetail? {
        table[exerciseId]
    }

    static var exerciseIds: [String] { table.keys.sorted() }

    private static let table: [String: GuideDetail] = [
        "bench": GuideDetail(
            title: "벤치프레스",
            muscle: "가슴 · 삼두 · 앞어깨",
            summary: "누워서 바벨을 가슴까지 내렸다가 밀어 올리는 가슴 기본 운동입니다.",
            steps: [
                "벤치에 누워 발바닥을 바닥에 고정하고 엉덩이·등·머리를 벤치에 붙인다.",
                "견갑골을 모아 어깨를 안정시키고, 그립은 내릴 때 팔꿈치가 약 75° 정도 벌어지게.",
                "바를 명치~가슴 중앙으로 천천히 내린 뒤, 발을 밀듯 밀어 올린다."
            ],
            avoid: ["팔꿈치를 90°로 벌려 어깨를 꺾지 않는다.", "엉덩이가 뜨거나 목이 과하게 젖혀지지 않게 한다."],
            imageName: "ex_bench"
        ),
        "incline-bench": GuideDetail(
            title: "인클라인 프레스",
            muscle: "윗가슴 · 앞어깨",
            summary: "벤치를 30~45°로 세워 윗가슴을 더 자극하는 프레스입니다.",
            steps: [
                "벤치 각도는 30~45°. 너무 세우면 어깨 운동이 된다.",
                "바 또는 덤벨을 윗가슴 쪽으로 내리고, 팔꿈치는 몸통보다 약간만 벌린다.",
                "가슴이 먼저 올라가게 밀어 올린다."
            ],
            avoid: ["각도를 60° 이상으로 세우지 않는다.", "덤벨이 앞으로 말리지 않게 손목을 세운다."],
            imageName: "ex_incline"
        ),
        "cable-fly": GuideDetail(
            title: "케이블/펙덱 플라이",
            muscle: "가슴 (고립)",
            summary: "팔을 벌렸다 모으며 가슴만 쓰는 고립 운동입니다.",
            steps: [
                "팔꿈치를 살짝 구부린 채 고정하고, 그 각도를 유지한다.",
                "손끝이 아니라 팔꿈치·가슴으로 모아 준다는 느낌으로 안쪽으로 가져온다.",
                "모은 지점에서 1초 쥐고 천천히 벌린다."
            ],
            avoid: ["팔꿈치를 완전히 펴서 관절에 하중을 주지 않는다.", "무게가 세면 어깨가 앞으로 말린다. 줄인다."],
            imageName: "ex_fly"
        ),
        "db-lateral-raise": GuideDetail(
            title: "사이드 레터럴",
            muscle: "옆어깨 (측면 삼각근)",
            summary: "팔을 옆으로 들어 어깨 옆면을 키우는 운동입니다.",
            steps: [
                "덤벨을 몸 옆에 두고 팔꿈치를 살짝 구부린 채 유지한다.",
                "손끝이 아니라 팔꿈치가 먼저 올라가듯, 어깨 높이까지만 든다.",
                "내릴 때도 통제하며 천천히."
            ],
            avoid: ["어깨 위로 휙 던지지 않는다.", "승모근으로 으쓱하며 들지 않는다. 무게를 낮춘다."],
            imageName: "ex_lateral"
        ),
        "cable-pushdown": GuideDetail(
            title: "트라이셉스 푸시다운",
            muscle: "삼두",
            summary: "케이블을 아래로 눌러 팔 뒷면을 고립하는 운동입니다.",
            steps: [
                "팔꿈치를 옆구리에 고정하고 몸통은 거의 움직이지 않는다.",
                "손만 내려가는 게 아니라 팔꿈치를 축으로 아래까지 편다.",
                "하단에서 삼두를 쥐고 천천히 올린다."
            ],
            avoid: ["팔꿈치가 앞으로 떠서 어깨가 개입하지 않게 한다.", "상체를 크게 숙여 무게를 속이지 않는다."],
            imageName: "ex_pushdown"
        ),
        "cable-overhead-extension": GuideDetail(
            title: "오버헤드 익스텐션",
            muscle: "삼두 (롱헤드)",
            summary: "머리 위로 팔을 뻗어 삼두 긴 머리를 늘리는 운동입니다.",
            steps: [
                "팔꿈치를 귀 옆에 고정하고 머리 뒤로 무게를 내린다.",
                "팔꿈치 위치를 거의 고정한 채 머리 위로 편다.",
                "바벨·케이블·덤벨 모두 허리를 과하게 젖히지 않는다."
            ],
            avoid: ["팔꿈치가 밖으로 크게 벌어지지 않게 한다.", "바벨을 등 뒤로 너무 깊게 넣어 어깨를 꺾지 않는다."],
            imageName: "ex_oh_ext"
        ),
        "cable-lat-pulldown": GuideDetail(
            title: "랫풀다운",
            muscle: "광배근 (등 넓이)",
            summary: "위에서 아래로 당겨 등을 넓히는 기본 수직 당김입니다.",
            steps: [
                "무릎을 패드에 고정하고 가슴을 연 채 허리를 살짝 아치로.",
                "바는 어깨보다 조금 넓게. 팔꿈치로 당긴다는 느낌으로 쇄골~가슴까지.",
                "하단에서 견갑골을 모으고, 천천히 팔을 펴 광배를 늘린다."
            ],
            avoid: ["바를 목 뒤로 내리지 않는다.", "반동으로 상체를 크게 눕히지 않는다. 약수터 동작 금지."],
            imageName: "ex_latpulldown"
        ),
        "machine-chest-supported-row": GuideDetail(
            title: "체스트서포트 로우",
            muscle: "등 (두께) · 허리 부담 적음",
            summary: "가슴을 패드에 기대 허리를 빼고 등만 쓰는 로우입니다. 바벨로우가 허리에 부담이면 이걸로 바꿉니다.",
            steps: [
                "벤치나 머신 패드를 편한 각도로 세우고 가슴을 기댄다.",
                "얼굴은 아래, 덤벨/바를 잡고 팔꿈치를 옆구리에 붙인 채 당긴다.",
                "팔꿈치가 등 뒤로 과하게 나가지 않게 하고 천천히 내린다."
            ],
            avoid: ["어깨로 으쓱하며 당기지 않는다.", "가슴을 패드에서 떼고 허리로 치지 않는다."],
            imageName: "ex_chest_row"
        ),
        "cable-straight-arm-pulldown": GuideDetail(
            title: "스트레이트암 풀다운",
            muscle: "광배 하부 (이두 개입 적음)",
            summary: "팔을 거의 편 채로 케이블을 허벅지까지 눌러 광배만 쓰는 고립입니다.",
            steps: [
                "하이케이블을 마주 보고 한두 걸음 뒤로 서서 케이블이 팽팽하게.",
                "팔꿈치는 살짝만 구부린 채 고정. 바가 허벅지에 닿을 때까지 광배로 누른다.",
                "1초 쥐고 천천히 머리 높이까지 되돌린다."
            ],
            avoid: ["팔꿈치를 접어 푸시다운처럼 만들지 않는다.", "상체를 크게 숙여 무게를 속이지 않는다."],
            imageName: nil  // imageset "ex_straight_arm" was never shipped
        ),
        "cable-face-pull": GuideDetail(
            title: "페이스풀",
            muscle: "후면 삼각근 · 회전근개 · 중승모",
            summary: "로프를 얼굴 쪽으로 당겨 어깨 건강과 등 윗면을 살리는 운동입니다.",
            steps: [
                "케이블을 얼굴~머리 높이. 로프를 잡고 팔을 앞으로 뻗는다.",
                "팔꿈치를 높게 유지한 채 로프를 귀 양옆으로 벌리며 당긴다.",
                "견갑골을 모으고 2초 유지 후 천천히 되돌린다."
            ],
            avoid: ["허리를 과하게 젖히거나 상체를 숙이지 않는다.", "무게가 세면 허리로 친다. 줄인다."],
            imageName: "ex_facepull"
        ),
        "shrug": GuideDetail(
            title: "슈러그",
            muscle: "상부 승모근",
            summary: "어깨를 귀 쪽으로 으쓱해 승모를 키우는 운동입니다.",
            steps: [
                "바벨/덤벨을 몸 옆에 들고 팔은 거의 편다.",
                "어깨만 귀 쪽으로 수직으로 올린다. 1초 유지.",
                "천천히 내린다."
            ],
            avoid: ["목을 앞으로 빼거나 어깨를 돌리지 않는다.", "반동으로 점프하지 않는다."],
            imageName: "ex_shrug"
        ),
        "curl": GuideDetail(
            title: "컬",
            muscle: "이두",
            summary: "팔꿈치를 축으로 무게를 말아 올려 이두를 고립합니다.",
            steps: [
                "팔꿈치를 옆구리에 붙이고 상체는 고정.",
                "손목이 꺾이지 않게 말아 올린 뒤, 천천히 내린다.",
                "하단에서 팔꿈치를 완전히 잠그지 않고 긴장을 유지해도 된다."
            ],
            avoid: ["상체를 뒤로 크게 젖혀 치팅하지 않는다.", "팔꿈치가 앞으로 떠서 어깨가 개입하지 않게."],
            imageName: "ex_curl"
        ),
        "db-hammer-curl": GuideDetail(
            title: "해머컬",
            muscle: "이두 · 전완 · 상완근",
            summary: "손바닥이 마주 보는 뉴트럴 그립 컬입니다. 팔뚝이 두꺼워집니다.",
            steps: [
                "덤벨을 망치 잡듯 세워서 든다.",
                "팔꿈치를 고정하고 어깨 높이 근처까지 올린다.",
                "천천히 내린다."
            ],
            avoid: ["손목을 비틀지 않는다.", "흔들어서 올리지 않는다."],
            imageName: "ex_hammer"
        ),
        "squat": GuideDetail(
            title: "스쿼트",
            muscle: "대퇴사두 · 둔근 · 코어",
            summary: "바를 등에 얹고 앉았다 일어나는 하체 기본입니다.",
            steps: [
                "발은 어깨너비, 발끝은 약간 바깥. 바는 상부 승모(하이바) 또는 후면 삼각(로우바).",
                "가슴을 연 채 힙을 뒤로 보내며 앉는다. 무릎은 발끝 방향.",
                "허벅지가 최소 평행 근처까지 간 뒤, 발바닥 전체로 일어난다."
            ],
            avoid: ["허리가 둥글게 말리지 않게 한다.", "무릎만 앞으로 쏘며 발뒤꿈치가 뜨지 않게."],
            imageName: "ex_squat"
        ),
        "front-squat": GuideDetail(
            title: "프론트 스쿼트",
            muscle: "대퇴사두 · 코어",
            summary: "바를 쇄골 앞에 올려 상체를 세운 채 앉는 스쿼트입니다.",
            steps: [
                "바를 어깨 앞에 올리고 팔꿈치를 높게 유지한다.",
                "상체를 최대한 세운 채 힙을 내려 앉는다.",
                "무릎이 앞으로 가도 되지만 발바닥은 바닥에 붙인다."
            ],
            avoid: ["팔꿈치가 떨어지면 바가 굴러내린다. 팔꿈치를 든다.", "상체가 무너지면 무게를 줄인다."],
            imageName: "ex_front_squat"
        ),
        "machine-leg-press": GuideDetail(
            title: "레그프레스",
            muscle: "대퇴사두 · 둔근",
            summary: "머신에 누워 발판을 미는 하체 운동입니다. 허리 부담이 스쿼트보다 적습니다.",
            steps: [
                "엉덩이와 등을 패드에 밀착. 발은 발판 중앙~약간 위.",
                "잠금장치가 풀린 뒤 무릎을 천천히 굽혀 깊게 가져온다.",
                "발판을 밀되 무릎을 완전히 꺾어 잠그지 않는다."
            ],
            avoid: ["엉덩이가 패드에서 들리면 너무 깊다. 범위를 줄인다.", "무릎을 안쪽으로 모으지 않는다."],
            imageName: "ex_legpress"
        ),
        "machine-leg-extension": GuideDetail(
            title: "레그 익스텐션",
            muscle: "대퇴사두 (고립)",
            summary: "앉아서 무릎만 펴 허벅지 앞을 고립합니다.",
            steps: [
                "패드가 발목 위에 오게 맞춘다.",
                "등받이에 등을 붙이고 무릎을 펴 상단에서 1초 쥐고.",
                "천천히 내린다."
            ],
            avoid: ["반동으로 차 올리지 않는다.", "엉덩이가 들리면 무게를 줄인다."],
            imageName: "ex_legext"
        ),
        "machine-lying-leg-curl": GuideDetail(
            title: "레그컬",
            muscle: "햄스트링",
            summary: "누우거나 앉아 발뒤꿈치를 엉덩이 쪽으로 말아 허벅지 뒤를 씁니다.",
            steps: [
                "패드 위치를 발목 바로 위에 맞춘다.",
                "힙은 패드에 붙인 채 발뒤꿈치를 엉덩이 쪽으로.",
                "상단에서 햄을 쥐고 천천히 편다."
            ],
            avoid: ["허리가 과하게 젖혀지지 않게 한다.", "무게를 떨어뜨리듯 펴지 않는다."],
            imageName: "ex_legcurl"
        ),
        "machine-standing-calf-raise": GuideDetail(
            title: "카프 레이즈",
            muscle: "종아리",
            summary: "발끝으로 몸을 올려 종아리를 자극합니다. 서서 하면 비복근, 앉아서 하면 가자미근.",
            steps: [
                "발볼로 딛고 발뒤꿈치를 아래로 Fully 내린 뒤 최대로 올린다.",
                "상단에서 1초 쥐고 천천히 내린다.",
                "무릎은 서서 할 때 거의 펴고, 앉아서 할 때는 90°."
            ],
            avoid: ["반동으로 튕기지 않는다.", "발목이 아프면 가동범위를 줄인다."],
            imageName: "ex_calf"
        ),
        "crunch": GuideDetail(
            title: "복근",
            muscle: "복부",
            summary: "크런치·레그레이즈 등 코어 마무리입니다.",
            steps: [
                "허리를 바닥에 붙인 채 갈비뼈를 골반 쪽으로 말아 올린다.",
                "목만 당기지 말고 복부로 든다.",
                "호흡을 참지 않는다."
            ],
            avoid: ["목만 잡아당겨 올리지 않는다.", "허리가 바닥에서 뜨면 멈춘다."],
            imageName: "ex_abs"
        ),
        "ohp": GuideDetail(
            title: "오버헤드 프레스 (OHP)",
            muscle: "어깨 · 삼두 · 코어",
            summary: "바벨을 머리 위로 미는 어깨 기본입니다.",
            steps: [
                "바를 쇄골 앞에 두고 팔꿈치는 살짝 앞. 코어를 단단히.",
                "머리를 살짝 빼며 바를 위로 밀고, 귀가 팔 사이에 오게 선다.",
                "내릴 때도 코 앞을 지나 쇄골로."
            ],
            avoid: ["허리를 과하게 젖혀 벤치프레스처럼 만들지 않는다.", "바가 앞으로 나가면 코어가 풀린 것이다."],
            imageName: "ex_ohp"
        ),
        "db-bench-press": GuideDetail(
            title: "라이트 플랫 덤벨 프레스",
            muscle: "가슴",
            summary: "가벼운 덤벨로 플랫 벤치에서 가슴을 채우는 보조 프레스입니다.",
            steps: [
                "벤치에 누워 덤벨을 가슴 옆에 둔다.",
                "팔꿈치를 약 75°로 내리고 가슴으로 밀어 올린다.",
                "상단에서 덤벨이 부딪히지 않게 살짝만 모은다."
            ],
            avoid: ["어깨가 앞으로 말리지 않게 견갑골을 모아 둔다."],
            imageName: nil  // imageset "ex_flat_db" was never shipped
        ),
        "dips": GuideDetail(
            title: "딥스",
            muscle: "가슴 하부 · 삼두",
            summary: "평행봉에 몸을 매달고 내려갔다 올라오는 운동입니다.",
            steps: [
                "손잡이를 잡고 어깨를 귀에서 멀리(아래로) 내린다.",
                "상체를 조금 숙이면 가슴, 세우면 삼두 비중이 커진다.",
                "어깨가 아픈 깊이까지만 내리고 밀어 올린다."
            ],
            avoid: ["어깨가 귀 쪽으로 으쓱하며 내려가지 않는다.", "통증 있으면 머신 딥스나 푸시다운으로 바꾼다."],
            imageName: "ex_dips"
        ),
        "bent-over-row": GuideDetail(
            title: "바벨로우",
            muscle: "등 두께 · 광배 · 후면 삼각",
            summary: "상체를 숙인 채 바벨을 배로 당기는 수평 당김입니다.",
            steps: [
                "상체를 대략 30~45° 숙이고 허리는 중립(둥글게 말리지 않게).",
                "바는 발 위에. 팔꿈치로 상복부까지 당긴다.",
                "바가 몸에 가깝게, 천천히 내린다."
            ],
            avoid: ["허리가 둥글게 말리면 즉시 무게를 줄이거나 체스트서포트 로우로 교체.", "상체를 세워 슈러그처럼 만들지 않는다."],
            imageName: "ex_barbell_row"
        ),
        "cable-seated-row": GuideDetail(
            title: "시티드 케이블 로우",
            muscle: "등 중부 · 광배",
            summary: "앉아서 핸들을 배 쪽으로 당기는 머신 로우입니다.",
            steps: [
                "무릎을 살짝 굽히고 가슴을 연다.",
                "팔꿈치가 옆구리를 스치듯 배꼽 높이로 당긴다.",
                "당긴 뒤 견갑골을 모으고 천천히 팔을 편다."
            ],
            avoid: ["당길 때 상체를 크게 뒤로 눕히지 않는다.", "출발에서 허리가 말리지 않게 한다."],
            imageName: "ex_seated_row"
        ),
        "db-rear-delt-fly": GuideDetail(
            title: "리어델트 플라이",
            muscle: "후면 삼각근",
            summary: "팔을 옆으로 벌려 어깨 뒷면을 고립합니다.",
            steps: [
                "상체를 숙이거나 머신에 앉아 팔꿈치를 살짝 구부린 채 고정.",
                "손보다 팔꿈치가 바깥으로 나가게 벌린다.",
                "어깨 높이 근처에서 쥐고 천천히 모은다."
            ],
            avoid: ["승모로 으쓱하지 않는다.", "반동으로 흔들지 않는다."],
            imageName: "ex_rear_delt"
        ),
        "preacher-curl": GuideDetail(
            title: "프리처 컬",
            muscle: "이두 (특히 하단)",
            summary: "패드에 팔을 올려 치팅을 막고 이두만 쓰는 컬입니다.",
            steps: [
                "겨드랑이가 패드 위에 오게 팔을 올린다.",
                "천천히 말아 올리고, 내릴 때 팔꿈치를 완전히 잠그지 않아도 된다.",
                "상단에서 이두를 쥐고 2초."
            ],
            avoid: ["엉덩이를 들며 치팅하지 않는다.", "하단에서 팔을 과신전하지 않는다."],
            imageName: "ex_preacher"
        ),
        "deadlift": GuideDetail(
            title: "데드리프트",
            muscle: "후면사슬 · 등 · 둔근 · 햄",
            summary: "바닥의 바벨을 힙 힌지로 들어 올리는 전신 운동입니다.",
            steps: [
                "바가 발등 중앙, 정강이가 바에 거의 닿게. 발은 힙 너비.",
                "힙을 낮추고 가슴을 연 채 바를 잡고, 등은 중립.",
                "바닥을 발로 밀며 무릎을 펴고, 바가 무릎을 지나면 힙을 앞으로 밀어 선다."
            ],
            avoid: ["허리가 둥글게 말린 채 들지 않는다.", "바를 몸에서 멀리 떨어뜨리지 않는다."],
            imageName: "ex_deadlift"
        ),
        "romanian-deadlift": GuideDetail(
            title: "RDL (루마니안 데드)",
            muscle: "햄스트링 · 둔근",
            summary: "무릎을 조금 굽힌 채 힙만 뒤로 빼 허벅지 뒤를 늘리는 데드입니다. 바닥까지 안 내려도 됩니다.",
            steps: [
                "바를 들고 선 뒤 무릎을 살짝만 굽힌다.",
                "힙을 뒤로 보내 바가 다리를 스치듯 내려간다.",
                "햄이 팽팽해지는 지점에서 힙을 앞으로 밀어 일어난다."
            ],
            avoid: ["무릎을 많이 굽혀 스쿼트처럼 만들지 않는다.", "허리가 말리면 더 내리지 않는다."],
            imageName: "ex_rdl"
        ),
        "hip-thrust": GuideDetail(
            title: "힙 쓰러스트",
            muscle: "둔근",
            summary: "등에 벤치를 대고 힙을 위로 밀어 엉덩이를 고립합니다.",
            steps: [
                "벤치에 어깨뼈 아래를 기대고 바는 힙 주름에.",
                "턱을 살짝 당긴 채 힙을 천장으로 민다. 상단에서 엉덩이를 쥐고.",
                "천천히 내린다."
            ],
            avoid: ["허리를 과하게 젖혀 허리가 아프게 하지 않는다.", "목이 뒤로 꺾이지 않게 한다."],
            imageName: "ex_hip_thrust"
        ),
        "db-lunge": GuideDetail(
            title: "런지",
            muscle: "대퇴 · 둔근",
            summary: "한 다리로 앞으로 앉아 단측 하체를 자극합니다.",
            steps: [
                "한 발을 앞으로 크게 내딛고 뒷무릎을 바닥 가까이 내린다.",
                "앞무릎은 발끝 방향, 상체는 세운다.",
                "앞발로 밀어 일어난다. 좌우를 번갈아."
            ],
            avoid: ["앞무릎이 안쪽으로 무너지지 않게 한다.", "상체가 과하게 숙으면 보폭을 조절한다."],
            imageName: "ex_lunge"
        ),
        "close-grip-bench": GuideDetail(
            title: "클로즈그립 벤치",
            muscle: "삼두 · 가슴 안쪽",
            summary: "손을 좁게 잡고 미는 벤치입니다. nSuns의 캡 데이가 이 계열입니다.",
            steps: [
                "그립은 어깨너비 또는 조금 안. 너무 좁히면 손목이 아프다.",
                "팔꿈치를 몸통에 가깝게 유지한 채 내린다.",
                "삼두로 밀어 올린다."
            ],
            avoid: ["손을 주먹 하나 간격까지 붙이지 않는다.", "손목이 꺾이면 그립을 조금 넓힌다."],
            imageName: "ex_closegrip"
        ),
        "power-clean": GuideDetail(
            title: "파워클린 (대체: 펜들레이 로우)",
            muscle: "전신 폭발력 · 등",
            summary: "바를 바닥에서 어깨 앞까지 한 번에 올리는 올림픽 리프트입니다. 어려우면 펜들레이 로우(상체 숙인 채 매 회 바닥에서 당김)로 바꿉니다.",
            steps: [
                "데드와 비슷하게 세팅 후, 바가 허벅지를 지날 때 힙을 폭발적으로 펴며 어깨 으쓱.",
                "팔꿈치를 돌려 바를 쇄골 앞에 받는다.",
                "대체 펜들레이: 상체 수평에 가깝게, 매 회 바가 바닥에 닿은 뒤 배로 당긴다."
            ],
            avoid: ["허리로 낚아채지 않는다. 어색하면 바로 펜들레이/바벨로우로.", "받을 때 무릎이 안쪽으로 무너지지 않게."],
            imageName: "ex_powerclean"
        )
    ]
}

/// Lower/upper guess for free-text `other` variants only; library exercises carry their own `plane`.
enum PlaneGuess {
    private static let coreKeywords = ["복근", "복부", "코어", "크런치", "플랭크"]
    private static let lowerKeywords = ["대퇴", "둔근", "종아리", "하체", "스쿼트", "데드", "힙", "런지", "레그", "카프", "RDL", "햄스트링"]

    static func guess(_ name: String) -> String {
        if coreKeywords.contains(where: { name.contains($0) }) { return "upper" }
        return lowerKeywords.contains(where: { name.localizedCaseInsensitiveContains($0) }) ? "lower" : "upper"
    }
}

/// What the guide sheet shows for one exercise/variant. Built only from `ExerciseLibrary.info(for:)` and `GuideDetail`.
struct GuideContent: Equatable {
    static let otherSummary = "직접 추가한 운동"

    var exerciseId: String
    var variantId: String
    var title: String
    /// Muscle group and equipment labels; empty for `other`.
    var chips: [String]
    var summary: String
    var detail: GuideDetail?
    var isOther: Bool

    /// `fallbackName` is the stored slot name, used when the variant has no library name (user variants, unknown ids).
    static func make(exerciseId: String, variantId: String, fallbackName: String? = nil) -> GuideContent {
        let library = ExerciseLibrary.shared
        let info = library.info(for: exerciseId)
        let detail = GuideDetail.detail(forExerciseId: exerciseId)
        let stored = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = stored?.isEmpty == false ? stored : nil
        if info?.isOther == true {
            return GuideContent(exerciseId: exerciseId, variantId: variantId, title: named ?? otherSummary,
                                chips: [], summary: otherSummary, detail: nil, isOther: true)
        }
        let title = library.displayName(variantId: variantId) ?? named ?? info?.name ?? variantId
        let chips = [info?.group?.label, info?.equipment?.label].compactMap { $0 }
        let summary = info?.summary ?? detail?.summary ?? ""
        return GuideContent(exerciseId: exerciseId, variantId: variantId, title: title, chips: chips,
                            summary: summary, detail: detail, isOther: false)
    }
}
