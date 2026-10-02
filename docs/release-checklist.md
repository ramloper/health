# 출시 체크리스트

## 0. 준비된 것 (이 저장소)

- [x] 앱 이름 쇠질, 아이콘(라이트/다크/틴트), 번들 ID `com.wooram.health`
- [x] 아이폰 전용, 세로 모드, iOS 17 이상
- [x] PrivacyInfo.xcprivacy (UserDefaults 사유 CA92.1)
- [x] 암호화 미사용 선언 (ITSAppUsesNonExemptEncryption = NO)
- [x] 유닛 테스트 42개, 스크린샷·5/3/1 세션 완료 UI 테스트
- [x] 스토어 문구: docs/app-store-metadata.md
- [x] 개인정보 처리방침, 지원 페이지: docs/privacy-policy.md, docs/support.md

## 1. 웹에 올려야 하는 것 (한 번만)

App Store는 개인정보 처리방침 URL과 지원 URL을 요구합니다. 가장 빠른 방법:

1. GitHub에 이 저장소(또는 `docs/`만 담은 공개 저장소)를 올린다.
2. Settings → Pages → Source: `main` 브랜치 `/docs` 폴더로 켠다.
3. 주소가 `https://<계정>.github.io/<저장소>/privacy-policy` 와 `/support` 로 생긴다.
4. 그 두 주소를 App Store Connect에 입력한다.

Notion 공개 페이지나 어떤 정적 호스팅이든 상관없습니다. 내용은 docs 파일 그대로 붙이면 됩니다.

## 2. Apple Developer / App Store Connect (한 번만)

1. developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `+` → App IDs → Bundle ID `com.wooram.health` (Explicit), Capabilities는 아무것도 켜지 않음.
   - Xcode 자동 서명이 이미 만들어 두었으면 이 단계는 건너뜀.
2. appstoreconnect.apple.com → 나의 앱 → `+` → 신규 앱
   - 플랫폼 iOS, 이름 쇠질, 기본 언어 한국어, 번들 ID 위 항목, SKU `soejil-ios`, 사용자 액세스 전체
3. 앱 정보: 카테고리 건강 및 피트니스, 개인정보 처리방침 URL 입력
4. 가격 및 사용 가능 여부: 무료, 모든 국가(또는 대한민국)
5. 앱 개인정보: "데이터를 수집하지 않음" 선택 후 게시
6. 연령 등급: 모든 항목 "없음" → 4+

## 3. 빌드 올리기 (버전마다)

```bash
# 1) 스크린샷 (처음 한 번, 이후 화면 바뀔 때)
./scripts/screenshots.sh

# 2) 서명된 IPA 생성 (빌드 번호 자동 +1)
./scripts/release.sh
```

- `Health-buildN.ipa` 가 저장소 루트에 생깁니다.
- Mac App Store에서 **Transporter** 설치 → Apple ID 로그인 → IPA 드래그 → 전달.
- 10~30분 뒤 App Store Connect → TestFlight 탭에 빌드가 나타납니다. "규정 준수 누락" 경고는 뜨지 않아야 정상입니다(Info.plist에 선언됨).

## 4. 버전 페이지 채우기

App Store Connect → 앱 → iOS 앱 → 1.0 준비 중

- 스크린샷: 6.9" 탭에 `build/screenshots/*.png` 7장 (순서는 metadata 문서 참고)
- 홍보 문구, 설명, 키워드, 지원 URL: docs/app-store-metadata.md 복사
- 빌드: TestFlight에 올라온 빌드 선택
- 앱 심사 정보: 연락처 이름/전화/이메일, 메모는 metadata 문서의 "심사 메모"
- 버전 출시: "심사 승인 후 자동 출시" 또는 수동

"심사를 위해 제출" 클릭. 보통 24~48시간.

## 5. 제출 전 마지막 확인

- [ ] 실기기에 설치해서 온보딩 → 오늘 → 운동 시작 → 세트 체크 → 휴식 알림 → 세션 완료 → 기록 탭 한 바퀴
- [ ] 화면 잠근 상태에서 휴식 타이머 알림이 오는지
- [ ] 앱 강제 종료 후 재실행 시 진행 중 세션이 복원되는지
- [ ] 프로필 → 기록 내보내기가 공유 시트를 띄우는지
- [ ] 라이트 모드 전환 후 모든 탭 한 번씩

## 6. 다음 버전

- `project.yml`의 `MARKETING_VERSION` 올리기 (1.0.0 → 1.1.0)
- `./scripts/release.sh` → Transporter → App Store Connect에서 "+ 버전" → "이 버전의 새로운 기능" 작성 → 제출
