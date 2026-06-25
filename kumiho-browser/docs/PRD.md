# 🦊 Kumiho Browser — PRD (Product Requirements Document) v1.0

---

**Graph-native AI Output Browser & Lineage Explorer**

---

## 📌 1. Background (배경)

AI Creator, ComfyUI, A1111 사용자들은 매일 수백–수천 장의 이미지를 생성한다.

그러나 생성된 이미지들은 다음과 같은 문제를 가진다:

- 폴더 기반 정리의 한계 (혼란·중복·검색 불가)
- 어떤 모델/LoRA/ControlNet을 사용했는지 기억나지 않음
- 프롬프트/Seed/설정 재현 어려움
- Output → Input → Model 간 관계(lineage)가 사라짐
- 하나의 Workflow로 생성된 이미지들 간 버전·의존성 파악 불가
- 커뮤니티 공유 시 필요한 카드/텍스트 자동 생성 기능 부족

**Kumiho Browser는 이러한 문제를 해결하기 위해 설계된
AI Output 전용 그래프 기반 브라우징·Lineage 탐색·검색 플랫폼이다.**

Kumiho Cloud의 그래프 DB 기반 원장(Ledger) 인프라 위에서 동작하며,

AI Creator의 모든 생성물, 모델, 인풋 리소스를 자동으로 연결해준다.

---

## 🎯 2. Product Vision (제품 비전)

> “AI Creator의 모든 이미지·모델·프롬프트·리소스를 자동 정리하고,
그래프 기반 lineage로 탐색하며, 강력한 검색으로 재활용을 극대화하는
세계 최초의 Lightweight Graph-native AI Browser.”
> 

핵심 가치:

- 파일 업로드 없이 로컬/NAS 그대로 사용 (BYO-Storage)
- ComfyUI/A1111 플러그인이 모든 메타데이터 자동 수집
- 갤러리·그래프·검색 중심의 탐색 경험
- 크리에이터 친화적 공유 기능 → 바이럴 성장 구조
- 무료 티어 + 광고 + 리퍼럴로 성장 Flywheel 구축

---

## 🧩 3. Goals & Non-Goals

### 🎯 Goals

- 자동 이미지 브라우징 + 썸네일 기반 탐색
- Output–Input–Model–Prompt–Workflow 간 **Lineage Graph** 자동 생성
- 프롬프트·모델명·LoRA·인풋 기반 **강력한 검색(Search)**
- 디테일 패널에서 모든 메타데이터 확인
- 소셜 공유 기능 (카드/프롬프트 자동 삽입)
- 로컬 캐시 기반 초고속 브라우징
- Free Tier + AdMob + Referral 성장 구조 구현
- Flutter 기반 설치형 앱(Desktop/Web) + kumiho-dart SDK 연동
- ComfyUI 전용 Kumiho Logger Node 제공 (API Key 기반 인증)

### 🚫 Non-Goals

- 이미지 생성 기능 자체는 제공하지 않음
- A1111/ComfyUI 대체 UI를 만드는 것이 목적 아님
- 클라우드 스토리지 업로드 목적의 DAM 아님
- 인터넷 없는 완전 오프라인 환경 전용 솔루션 아님

---

## 🏗 4. Overall Architecture

```
ComfyUI Plugin (Kumiho Logger Node)
       ↓
Metadata Extract (Prompt/Model/Input/Seed/Workflow)
       ↓ gRPC
Kumiho Server (Rust)
       ↓
Neo4j Graph DB (Tenant-specific)
       ↓
Kumiho Browser (Flutter Desktop/Web)
       ↓
Graph API + Search API + Thumbnail Loader

```

---

## 🔌 5. ComfyUI Plugin — Kumiho Logger Node

### 기능 요약

- Output Node에 배치하면 **자동으로 전체 Workflow 메타데이터 수집**
- 수집 내용:
    - 체크포인트 / LoRA / ControlNet / VAE
    - Prompt / Negative Prompt
    - Seed / CFG / Steps / Sampler
    - Input 이미지/마스크/비디오 경로
    - 전체 workflow JSON
- 서버에 ingest → Graph Lineage 자동 생성

### 인증 방식

- **Firebase Authentication 팝업 로그인 (MVP)**
- Google / GitHub / Email 로그인 지원
- Firebase ID Token → Kumiho Server gRPC 인증
- 토큰 자동 갱신 (kumiho-dart SDK 내장)

### Firebase 설정 (Embedded)

```
Project ID: kumiho-server
Auth Domain: kumiho-server.firebaseapp.com
```

### 주요 UX

- Node 파라미터:
    - API Key (ComfyUI 플러그인 전용 - 브라우저와 별도)
    - Project 선택
    - "Upload Outputs Automatically" 토글
- Workflow JSON에 민감 정보 저장 없음 (API Key 암호화 처리)

> **Note:** ComfyUI 플러그인은 API Key 방식 유지, 브라우저는 Firebase 팝업 로그인 사용

---

## 🖼 6. Kumiho Browser — UX Overview

Kumiho Browser는 **이미지 갤러리 기반의 탐색 UI + 그래프 기반 Lineage Explorer**로 구성된다.

### 핵심 UX 5요소

1. 갤러리 기반 브라우징 (Grid ListView) + List View for Non-viewable (image / video) data
2. 디테일 패널에서 모든 정보 확인
3. 그래프(Lineage Graph) 탐색
4. 모든 요소 기반 검색(Search)
5. 소셜 공유 기능

---

## 🟦 7. Gallery View (Explore)

### 레이아웃

- **상단 글로벌 검색바**
- 좌측 사이드바:
    - All Images
    - By Project
    - By Model (Checkpoint/LoRA)
    - By Input Image
    - Favorites
    - Trash
- 메인 영역:
    - Masonry/Grid 뷰
    - Clip(썸네일) 크기 조절
    - 정렬 옵션 (Newest, Model, Seed, Project 등)

### Clip(썸네일) 구성 요소

- 썸네일 이미지
- 모델명 축약 표시
- 프롬프트 앞 1줄
- Seed 아이콘
- LoRA 사용 여부
- 워크플로우 아이콘
- Hover 시:
    - Quick Detail
    - ⭐ Favorite
    - Graph View 바로가기

---

## 🟪 8. Detail Panel

이미지 클릭 시 오른쪽에 표시되는 정보:

### 1) 이미지 미리보기

- 확대/축소
- 16:9 카드 변환 버튼

### 2) Prompt 탭

- Prompt
- Negative Prompt

### 3) Settings 탭

- Seed, Steps, CFG, Sampler, Resolution

### 4) Model 탭

- Checkpoint
- LoRA
- VAE, ControlNet
- 각각 클릭 시 Model Detail로 이동

### 5) Input Resources

- Input 이미지 썸네일
- “이 인풋으로 생성된 이미지 모두 보기”

### 6) Graph View 버튼

- 클릭 시 Lineage Graph로 전환

---

## 🟧 9. Lineage Graph View

### 노드 타입

- Output
- Input Resource
- Model
- Prompt
- Version
- Workflow

### 기능

- 드래그, 줌
- Node 클릭 시 Detail Panel 자동 전환
- Layout:
    - Force-directed
    - Hierarchical
    - Radial

### 핵심 가치

> “이 이미지는 무엇으로부터 만들어졌는가?”
> 
> 
> → 모든 의존성이 시각적으로 펼쳐짐.
> 

---

## 🟩 10. Search & Filter

### 검색 가능 요소

- Prompt Text
- Model 이름
- LoRA 이름
- Input 이미지 파일명
- Seed 범위
- Date Range
- Resolution
- Favorites
- Project / Category

### UX

- 실시간 필터링
- 적용된 필터는 Chips 형태로 상단에 표시
- 필터 제거 = Chip 클릭

---

## 🟦 11. Social Sharing (무료 성장엔진)

### 지원 플랫폼

- Twitter(X)
- Reddit
- Instagram
- TikTok
- Discord
- Link Copy

### 공유 카드 자동 생성

- 이미지
- Prompt 앞 1~2줄
- Model, LoRA, Seed
- “Generated with Kumiho Browser” 워터마크(옵션)

### 기대 효과

- 커뮤니티 자발적 바이럴 생성
- 유저 유입 비용을 0원에 가깝게 유지

---

## 🟨 12. Free Tier + AdMob Strategy

### 무료 제공

- 1000 Nodes (약 700장의 이미지 커버)

### AdMob 배치 위치

- 썸네일 클립 사이
- Detail Panel 하단
- Graph 뷰 하단

광고는 최소 간섭·최대 자연스럽게 배치.

### 광고 제거 옵션

- 유료 구독 시 전체 광고 제거
- 무료 사용자에게 자연스러운 업그레이드 경로 제공

---

## 🟫 13. Referral System (바이럴 성장 구조)

### 보상 구조

- **소개한 사람:** $10 크레딧
- **가입한 사람:** $10 크레딧

### 사용 용도

- 노드 확장
- Pro 기능 unlock
- 광고 제거

### 왜 잘 작동하는가?

- 이미지 공유와 리퍼럴이 자연스럽게 결합
- ComfyUI/Twitter/Reddit의 커뮤니티 구조와 완벽하게 맞음

---

## 🧱 14. Tech Stack & Strategy

### Kumiho Browser

- Flutter (Desktop/Web)
- kumiho-dart SDK
- 로컬 SQLite 캐싱
- GPU 없이 빠르게 작동

### Backend

- Rust (tonic + Axum gRPC)
- Neo4j Aura
- Supabase(Admin DB)
- Firebase Auth

---

## 🧪 15. MVP Scope

1. ComfyUI Logger Node
2. 이미지 메타 ingest
3. 갤러리 UI + 썸네일 캐시
4. Detail Panel
5. Graph View
6. Prompt/Model/Search
7. 소셜 공유 기본
8. Free Tier + AdMob
9. Referral 기본 시스템

---

## 📈 16. Growth Loop

```
AI Creator → ComfyUI Plugin 사용
       ↓
자동 Lineage 정리 + 아름다운 브라우저 UX 경험
       ↓
이미지 공유(SNS)
       ↓
신규 유저 유입
       ↓
무료 1000 노드 → 지속 사용
       ↓
노드 부족/광고 → 유료 전환 or 리퍼럴
       ↓
또다시 공유 & 추천

```

**→ 자발적 성장 Flywheel 생성**

---

## 🧭 17. Open Questions / Future Work

- Kumiho Browser 모바일 버전 출시?
- A1111 Logger Extension 연동?
- Team Shared Browsing 지원?
- Cloud 버전 브라우저 제공 여부?
- Workflow Diff/Comparison 기능 추가?

---

## ⭐ 18. Appendix / Citations

- 본 브라우저 PRD는 기존 **Kumiho Cloud 전체 PRD 구조**를 기반으로 작성됨.

---

필요하면:

- **Figma 프레임 구조**
- **UI 컴포넌트 설계**
- **API/Graph 스키마 매핑**
- **브라우저 온보딩 플로우**
- **Pitch Deck 버전**

까지도 생성해줄게!