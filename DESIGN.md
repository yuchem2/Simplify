---
name: Simplify
description: 한 장의 종이에 잉크로 그은 장부 같은 macOS 캘린더·다이어리
colors:
  wall: "#f4f4f2"
  paper: "#ffffff"
  raised: "#f7f7f5"
  ink: "#1a1a1a"
  ink-soft: "#575755"
  ink-faint: "#80807d"
  shade: "#d8d8d5"
  shade-soft: "#ececea"
  chip: "#e4e4e1"
  on-ink: "#ffffff"
  hover: "#f0f0ee"
  row-active: "#e4e4e1"
  error-tint: "#faf0c4"
  shadow-float: "#d8d8d5"
  widget-surface: "#fbfbfa"
  widget-nest: "#f0efec"
  wall-dark: "#1f1e1c"
  paper-dark: "#2a2927"
  raised-dark: "#33312e"
  ink-dark: "#ecebe6"
  ink-soft-dark: "#bab8b1"
  ink-faint-dark: "#8d8b85"
  shade-dark: "#4a4844"
  shade-soft-dark: "#35332f"
  chip-dark: "#4d4b47"
  on-ink-dark: "#2a2927"
  hover-dark: "#383633"
  row-active-dark: "#4d4b47"
  error-tint-dark: "#4a4331"
  shadow-float-dark: "#121110"
  widget-surface-dark: "#272624"
  widget-nest-dark: "#32302d"
  red-ink: "#b3332a"
  red-tint: "#fbe3df"
  orange-ink: "#9a4c00"
  orange-tint: "#fce9d6"
  yellow-ink: "#7a6000"
  yellow-tint: "#faf0c4"
  green-ink: "#28702c"
  green-tint: "#e1f1e0"
  teal-ink: "#00776a"
  teal-tint: "#dcf0ed"
  blue-ink: "#2a5fc4"
  blue-tint: "#e1e9fb"
  purple-ink: "#7a44bf"
  purple-tint: "#ece2f8"
  pink-ink: "#b5325f"
  pink-tint: "#f9e0e9"
  grey-ink: "#5e5e5b"
  grey-tint: "#e9e9e6"
typography:
  title:
    fontFamily: "Gowun Batang, Nanum Myeongjo, AppleMyungjo, serif"
    fontSize: "30px"
    fontWeight: 700
    lineHeight: "36px"
  heading:
    fontFamily: "Gowun Batang, Nanum Myeongjo, AppleMyungjo, serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: "28px"
  subheading:
    fontFamily: "Gowun Batang, Nanum Myeongjo, AppleMyungjo, serif"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: "26px"
  big-date:
    fontFamily: "Gowun Batang, Nanum Myeongjo, AppleMyungjo, serif"
    fontSize: "36px"
    fontWeight: 700
    lineHeight: "36px"
    fontFeature: "tnum"
  date:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: "20px"
    fontFeature: "tnum"
  item:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "20px"
  memo:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: "26px"
  body:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: "18px"
  small:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "16px"
  section:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: "16px"
    letterSpacing: "0em"
  cell:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: "15px"
  meta:
    fontFamily: "-apple-system, SF Pro Text, Apple SD Gothic Neo, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 500
    lineHeight: "14px"
    fontFeature: "tnum"
rounded:
  none: "0px"
  widget: "18px"
  full: "9999px"
spacing:
  space-xxs: "2px"
  space-xs: "4px"
  space-s: "6px"
  space-m: "8px"
  space-l: "12px"
  space-xl: "16px"
  space-xxl: "20px"
  space-xxxl: "24px"
components:
  button-plain:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "0 12px"
    height: "28px"
  button-plain-hover:
    backgroundColor: "{colors.hover}"
  button-plain-pressed:
    backgroundColor: "{colors.row-active}"
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "0 12px"
    height: "28px"
  button-toggled:
    backgroundColor: "{colors.row-active}"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "0 12px"
    height: "28px"
  button-toggled-pressed:
    backgroundColor: "{colors.row-active}"
  button-text:
    textColor: "{colors.ink}"
    typography: "{typography.small}"
  button-danger:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.red-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "0 12px"
    height: "28px"
  button-disabled:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink-faint}"
  segment:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "0 12px"
    height: "28px"
  segment-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-ink}"
  field-box:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.none}"
    padding: "0 8px"
    height: "28px"
  field-box-error:
    backgroundColor: "{colors.error-tint}"
  field-box-disabled:
    backgroundColor: "{colors.shade-soft}"
    textColor: "{colors.ink-faint}"
  field-inline-active:
    backgroundColor: "{colors.row-active}"
    textColor: "{colors.ink}"
    padding: "0 4px"
  field-title:
    textColor: "{colors.ink}"
    typography: "{typography.subheading}"
  row-chosen:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-ink}"
  row-active:
    backgroundColor: "{colors.row-active}"
    textColor: "{colors.ink}"
  row-hover:
    backgroundColor: "{colors.hover}"
  checkbox:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.none}"
    size: "16px"
  checkbox-done:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.on-ink}"
  tag:
    textColor: "{colors.ink}"
    typography: "{typography.meta}"
    rounded: "{rounded.none}"
    padding: "1px 6px"
  notice-warning:
    backgroundColor: "{colors.error-tint}"
    textColor: "{colors.ink}"
    typography: "{typography.small}"
    rounded: "{rounded.none}"
  notice-info:
    backgroundColor: "{colors.raised}"
    textColor: "{colors.ink}"
    typography: "{typography.small}"
  memo-chip:
    backgroundColor: "{colors.chip}"
    textColor: "{colors.ink}"
    typography: "{typography.memo}"
  sheet:
    backgroundColor: "{colors.paper}"
    rounded: "{rounded.none}"
  weekend-cell:
    backgroundColor: "{colors.raised}"
  widget:
    backgroundColor: "{colors.widget-surface}"
    rounded: "{rounded.widget}"
  widget-date-oval:
    backgroundColor: "{colors.widget-nest}"
    textColor: "{colors.ink}"
    typography: "{typography.big-date}"
    rounded: "{rounded.full}"
---

# Design System: Simplify

> 이 파일은 v5 "잉크 장부"가 **실제로 그려지는 코드에서 읽어 낸** 시스템이에요. 기준은 `design/tokens.json`(v5) → `scripts/gen-tokens.py` → `Packages/SimplifyKit/Sources/SimplifyKit/Design/`(`Tokens.generated.swift`, `Components.swift`, `Fonts.swift`)과 `Apps/macOS/*.swift`이고, 렌더 확인은 `reviews/design-v5-shots/`(`snapshot-components.png` 상태 모음 포함)로 했어요. 프런트매터의 `-dark` 키는 다크 D1 "흑연" 값이에요. 사용자 팔레트의 다크 값은 `.impeccable/design.json`의 `colorMeta`에 있어요. 아직 시스템을 따르지 못하는 곳은 맨 끝 「남은 차이」에 모아 뒀어요.

## Overview

**Creative North Star: "잉크 장부"**

Simplify는 한 장의 종이에 잉크로 줄을 그은 장부처럼 보이는 캘린더·다이어리예요. 창 바탕(`wall`)은 책상이고, 그 위에 종이(`paper`) 한 장이 놓여 있어요. 월·주 격자와 하루 패널은 따로 떨어진 두 장이 아니라 같은 종이이고, 둘 사이에 굵은 잉크 등줄(spine) 하나만 그어요. 종이 자체는 테두리도 그림자도 없이 `shade` 실선 하나로 책상과 만나요. 그림자는 종이 위에 떠 있는 것(팝오버, 메뉴, 설정 상자)만 가져요.

틀은 흑백이고 색은 내용의 것이에요. 툴바, 버튼, 세그먼트, 체크 상자, 고른 상태는 모두 `ink`와 `paper`, 회색 단계로만 그려요. 색은 사용자 캘린더와 라벨의 9색 팔레트에만 들어가고, 빨강은 공휴일과 되돌릴 수 없는 동작(삭제·버리기·연결 해제)에만 남아요. 날짜와 시각은 SF Pro 등폭 숫자로 장부의 숫자 칸처럼 읽히고, 고운바탕 명조는 제목에만 나와요. 밀도는 데스크톱 캘린더답게 촘촘하지만(칸 안 글자 11px), 주마다 그은 잉크 가로줄과 한 단계 다른 주말 면이 질서를 잡아 줘요.

모든 컨트롤은 포인터(`hover` 면)와 키보드(종이 2px 틈 + 잉크 2px 링)에 답해요. 다크 D1 "흑연"은 검정이 아니라 따뜻한 회갈색 종이에 밝은 잉크예요. 위젯 C "불 끈 갤러리"는 선 없이 면의 밝기와 둥근 마스크로만 액자를 만들어요(토큰과 컴포넌트만 준비돼 있고 위젯 화면은 7단계예요).

**Key Characteristics:**
- 한 장의 종이: 격자와 패널이 한 면이고, 사이에 1.75px 잉크 등줄 하나
- 주 가로줄: 월간 격자는 주마다 1px 잉크 줄, 요일 줄 아래는 1.75px
- 주말은 `raised` 한 단계 다른 면, 오늘은 칸 위 3px 잉크 막대
- 하루 띠: 9시부터 24시까지 한 줄에 일정 블록과 현재 시각
- 현재 시각 선은 잉크(빨강 아님)
- 고른 것은 잉크 채움 + `on-ink` 글자, 고치는 중은 회색, 포인터는 `hover`
- 직각 모서리, 둥근 것은 미리알림 고리·현재 시각 점·위젯뿐
- 라이트(흰 벽)와 다크 D1 "흑연"을 모든 토큰이 같이 가져요

## Colors

흑백 단계의 틀 위에, 내용에만 쓰는 9색 팔레트를 얹고, 빨강은 공휴일과 되돌릴 수 없는 동작(삭제·버리기·연결 해제)에만 남긴 구조예요.

### Primary
- **잉크** (`ink`): 본문 글자, 등줄, 주 가로줄, 컨트롤 윤곽선, 그리고 "고른 것"의 채움이에요. `Tokens.selection`, `focusRing`, `now`, `error`, `link`가 모두 이 색의 별칭이에요. 흑연 다크에서는 밝은 잉크(`ink-dark`)로 뒤집혀요.
- **잉크 위 글자** (`on-ink`): 잉크로 채운 면(주 버튼, 고른 세그먼트, 고른 일정·메뉴 줄, 끝낸 체크 상자) 위의 글자와 체크 표시. 다크에서는 종이색이에요.

### Secondary
- **사용자 팔레트 9색** (`red` · `orange` · `yellow` · `green` · `teal` · `blue` · `purple` · `pink` · `grey`): 색마다 `-ink`와 `-tint` 한 쌍이에요. `-ink`는 캘린더 네모 표식, 메모 글자색, 할 일 라벨, 띠와 블록의 끝 줄이고, `-tint`는 형광펜, 종일·여러 날 띠, 주 보기 시간 블록, 하루 띠 블록의 면이에요. 코드에서는 `Palette`(`palette.ink` / `palette.tint` / `palette.name`)로 고르고 저장은 이름으로 해서 테마가 바뀌어도 맞는 값이 나와요. 다크 `-tint`는 그 색 잉크 20%를 흑연 종이 위에 얹은 값이에요.

### Tertiary
- **공휴일·되돌릴 수 없는 동작 빨강** (`red-ink`, 의미 별칭 `holiday` · `danger`): 일요일·공휴일 날짜 숫자와 요일 머리글 `일`, 공휴일 이름, 그리고 삭제·버리기·연결 해제 버튼(`DrawnButtonStyle(.danger)`, 밑줄 글자는 `.dangerText`)의 글자와 테두리. 틀에 들어가는 유일한 유채색이고 이 두 뜻 말고는 쓰지 않아요.

### Neutral
- **벽** (`wall`): 창 바탕과 제목 막대. 종이 바깥의 책상이에요.
- **종이** (`paper`): 한 장의 메인 종이(격자 + 패널), 팝오버, 메뉴, 설정 상자, 버튼과 입력 칸의 기본 면.
- **한 단계 위 면** (`raised`): 월·주 격자의 주말 열, 일반 안내(`NoticeBar` info) 바탕.
- **보조 잉크** (`ink-soft`): 시간, 요일 이름, 캘린더 이름, 할 일 출처, 하루 띠 시각 글자, 빈 상태 문장.
- **흐린 잉크** (`ink-faint`): 다른 달 날짜, 자리표시 글자, 꺼진 컨트롤, 다른 날 열의 현재 시각 점선. 3:1만 보장해서 읽어야 하는 글자에는 쓰지 않아요.
- **그늘** (`shade`): 종이가 벽과 만나는 실선, 주 보기의 시간 가로선과 날짜 세로선, 하루 띠의 바탕 줄, 칸 위 포인터 상자, 라이트의 떠 있는 그림자.
- **옅은 그늘** (`shade-soft`): 비활성 입력 칸, 메모 코드 구간 바탕.
- **포인터 면** (`hover`): 포인터가 올라간 칸·줄·버튼. 종이에서 한 걸음 떨어진 조용한 면이에요.
- **고치는 줄** (`row-active`): 제자리에서 고치는 중이거나 메뉴가 열린 줄, 눌린 버튼. 그 위 글자는 `ink`예요.
- **칩 회색** (`chip`): 메모 속 할 일 칩의 바탕.
- **경고 면** (`error-tint`): 경고 안내와 오류 입력 칸의 바탕. 노란 계열이라 빨강과 겹치지 않아요.
- **떠 있는 그림자** (`shadow-float`): 팝오버·메뉴·모달 밑 4px 그림자의 면.
- **위젯 면 / 위젯 둥지** (`widget-surface` / `widget-nest`): 위젯 C "불 끈 갤러리"의 바탕과 날짜 타원.

### Named Rules
**The Ink-Only Frame Rule.** 툴바, 버튼, 세그먼트, 테두리, 체크 상자, 고른 상태 같은 틀은 `ink` · `paper` · 회색 단계만 써요. 팔레트 색이 틀에 들어가면 사용자의 색과 앱의 색이 구분되지 않아요.

**The Two Reds Rule.** 빨강은 공휴일(`holiday`)과 되돌릴 수 없는 동작(삭제·버리기·연결 해제)(`danger`)에만 써요. 오류·경고는 잉크 글자 + 경고 표시 + `error-tint`, 현재 시각 선은 잉크예요. 오늘 열이나 오늘 칸에 빨강 면을 깔지 않아요.

**The Ink-and-Tint Pair Rule.** 팔레트 색은 늘 쌍으로 써요. 표식과 글자는 `-ink`, 넓은 면은 `-tint`. `-ink`는 넓은 면에 칠하지 않고 띠의 왼쪽 6px, 시간 블록의 왼쪽 4px, 하루 띠 블록의 왼쪽 3px 끝 줄로만 써요.

## Typography

**Display Font:** Gowun Batang Bold (번들, OFL; 대체 Nanum Myeongjo, AppleMyungjo, serif)
**Body Font:** SF Pro Text / Apple SD Gothic Neo (시스템)
**Label/Mono Font:** 따로 없음. 날짜·시각·개수는 SF Pro 등폭 숫자(`monospacedDigit`)로 읽혀요

**Character:** 명조는 장부 표지에 쓴 제목처럼 맨 위에만 나오고, 칸 안의 숫자와 글은 모두 SF Pro로 또박또박 읽혀요. 두 서체가 만나는 곳은 늘 "제목(명조) + 내용(SF)" 관계예요.

### Hierarchy
- **Display · title** (700, 30px, 36px): 달력 머리의 년·월·주 제목.
- **Display · heading** (700, 22px, 28px): 하루 패널 제목.
- **Display · subheading** (700, 20px, 26px): 설정 상자 제목, 팝오버 제목(일정 상세, 할 일 가져오기, 설정 하위 화면), 편집기의 제목 입력 칸.
- **Display · big-date** (700, 36px, 등폭): 위젯 날짜 타원 속 오늘 숫자(`DateOval`). 준비된 스타일이에요.
- **date** (600, 15px, 20px, 등폭): 월간 칸과 주 보기 머리글의 날짜 숫자. 오늘은 700.
- **item** (400, 14px, 20px): 패널의 일정·할 일 제목, 팝오버 목록 줄.
- **memo** (400, 15px, 행 26px): 메모 본문.
- **body** (400, 13px, 18px): 버튼, 세그먼트, 메뉴, 입력 칸, 안내 문장. 주 버튼과 고른 세그먼트는 600.
- **small** (400, 12px, 16px): 글자 버튼(`추가` · `가져오기`), 안내 띠, 입력 칸 아래 도움말.
- **section** (600, 12px, 자간 0): 섹션 이름(`SectionRule`).
- **cell** (400, 11px, 15px): 월간 칸 안의 일정 제목. 설정 › 일반에서 작게 10 · 보통 11 · 크게 13으로 바뀌어요.
- **meta** (500, 11px, 14px, 등폭): 시간, 캘린더 이름, 개수, 요일 이름, 하루 띠 시각, 태그.

### Named Rules
**The Title-Only Display Rule.** 고운바탕은 title · heading · subheading(그리고 위젯 big-date)에만 써요. 날짜 숫자, 이메일, 문장, 숫자 칸에는 쓰지 않아요.

**The Ledger Numerals Rule.** 날짜·시각·개수는 SF Pro 등폭 숫자(`date`, `meta`)로 써서 줄마다 자리가 맞아요.

**The No-Tracking Rule.** 한글에 자간을 주지 않아요. 섹션 이름도 자간 0이에요. 글자 크기는 `.textStyle(…)`로만 정하고 `.font(.system(size:))`는 SF Symbol 크기와 사용자 글자 크기 설정에만 써요. 연필(메모 있음)과 체크(완료·남은 할 일)는 SF Symbol 대신 Kit `Glyph`로 1.2~1.8px 잉크 선을 그어요.

## Layout

창 맨 위는 macOS의 진짜 제목 막대예요. 신호등 옆에 `+ 새 일정`(주 버튼), 가운데에 `주 · 월 · 년` 세그먼트, 오른쪽에 맞춤 상태와 패널 토글이 있고, 모두 우리 잉크 컨트롤이라 시스템 유리 배경은 꺼요. 빈 곳 끌기·이중 클릭(채우기 포함)·채운 창 끌어 원래 크기로는 시스템이 처리해요. 그 아래 종이 한 장이 창 가장자리까지 차고, 제목 막대와는 `shade` 실선 하나로 만나요. 종이 안 왼쪽은 달력 영역으로, 머리(고운바탕 제목 + 오른쪽 `‹ 오늘 ›`) 아래 월간 격자, 주 보기, 년 보기 중 하나예요. 오른쪽은 하루 패널(창 너비의 32%, 300~460px)이고, 둘 사이는 1.75px 잉크 등줄 하나예요. 창 최소 크기는 790×600px로 11인치 iPad 너비(834)보다 좁아요. 설정은 창 전체(제목 막대 포함)를 옅게 어둡게 깐 위에 뜬 상자예요(최대 760×540px, 창 가장자리에서 32px 이상 띄움). 머리는 `설정` 제목과 ×, 메뉴와 내용 사이는 잉크 등줄이고, 설정이 열린 동안 제목 막대의 컨트롤은 숨어요. ×, esc, 상자 바깥 클릭으로 닫혀요. 캘린더 메뉴에서는 계정 이름을 눌러 그 계정의 캘린더를 접어요. 테마는 설정 › 일반에서 시스템 · 흰 벽 · 흑연. 패널은 `⌘\`로 접히며 0.2초 easeOut으로 오른쪽으로 빠지고, 동작 줄이기가 켜져 있으면 투명도만 바뀌어요.

월간 격자는 일요일부터 7칸이에요. 세로 격자선은 없고 주마다 1px 잉크 가로줄(`WeekRules`), 요일 머리글 아래 1.75px 잉크 줄이에요. 칸 최소 크기 64×72px(칸이 96px보다 좁으면 시작 시각을 빼고 제목만), 날짜 숫자 안쪽 여백 위·아래 4 · 좌우 8px, 격자 안쪽 여백 좌우 20 · 위 16 · 아래 20px이에요. 칸에는 시간 일정이 `Mark` + `09:30` + 제목 한 줄로 들어가고, 넘치면 마지막 줄이 `+N개 더`가 돼요.

년 보기는 열두 달을 4열(좁으면 3열)로, 달마다 이름 + 잉크 줄 + 요일 + 6줄 날짜(meta 등폭), 일정 있는 날은 숫자 아래 3px 점, 오늘은 굵은 숫자 아래 2px 잉크 줄, 고른 날은 잉크 채움이에요. 날짜를 누르면 고르고, 두 번 누르거나 달 이름을 누르면 그 달 월 보기로 가요.

주 보기는 시간당 44px, 왼쪽 시간 거터 56px, 종일 띠 줄 20px(최대 4줄, 위에 고정), 최소 블록 높이 20px이에요. 시간 가로선과 날짜 세로선은 `shade`, 머리글 아래는 1.75px 잉크 줄이에요.

하루 패널은 안쪽 좌우·위 20px, 섹션 사이 20px, 섹션 이름과 첫 줄 사이 8px이에요. 일정 팝오버 340px, 패널 팝 316px, 서식 막대 312px, 오프라인 대기 팝 320px, 설정 상자 최대 760×540px(왼쪽 메뉴 184px), 확인 대화 420px이에요.

간격은 4px 기반에 반걸음 두 개(2 · 6)를 더한 여덟 단계(`space-xxs`부터 `space-xxxl`까지)이고, 뷰는 `Metrics.space…` 상수로 써요. 컨트롤 높이 28px, 표식 크기 같은 치수는 숫자 그대로 둬요.

### Named Rules
**The One Paper Rule.** 메인 종이는 `MainView`가 `paperSheet()`로 한 번만 그려요. 격자와 패널 뷰는 자기 배경이나 테두리를 그리지 않고, 둘 사이에는 1.75px 잉크 등줄 하나만 있어요.

**The Week Rule.** 월간 격자의 구조선은 주마다 그은 1px 잉크 가로줄이에요. 날 사이는 선이 아니라 주말 `raised` 면과 여백으로 나눠요.

## Elevation & Depth

메인 종이는 납작해요. 깊이는 면의 명도 차(`wall` < `paper`, 주말 `raised`)와 `shade` 실선으로만 나타내요. 그림자는 종이 위에 떠 있는 것(일정 팝오버, 패널 팝, 서식 막대, 설정 상자, 확인 대화)만 가지며, 블러 없는 4px 단색 오프셋 하나예요. 부드러운 그림자, 그라데이션, 이중선(몰딩)은 없어요.

### Shadow Vocabulary
- **떠 있는 그림자** (`box-shadow: 4px 4px 0 #d8d8d5`, 다크 `4px 4px 0 #121110`): 팝오버, 메뉴, 서식 막대, 설정 상자. SwiftUI는 `floatingFrame()`(종이 + 1px 잉크 + `Metrics.shadowOffset` 4pt)이에요.
- **어두운 막 위 그림자** (`floatingFrame(shadow:)`): 어둡게 깐 창 위의 설정 상자와 확인 대화. 막이 `shade`보다 어두워서 더 진한 그림자를 넘겨요.

### Named Rules
**The Flat Paper Rule.** 메인 종이 위의 것은 그림자를 갖지 않아요. 그림자는 떠 있는 것의 표시이고, 오른쪽 아래 4px · 블러 0 · 단색 하나뿐이에요. 상태(hover 등)에 따라 키우지 않아요.

## Shapes

모든 그려진 물체는 직각(`rounded.none`)이에요. 버튼, 세그먼트, 입력 칸, 체크 상자, 색 표식, 태그, 띠, 시간 블록, 팝오버가 모두 `Rectangle`이에요. 둥근 형태는 뜻이 있을 때만 써요: 미리알림은 사각 일정 표식과 구분되는 원형 고리(`ReminderMark`), 현재 시각 선 머리의 7px 점, 위젯의 18px 연속 곡선 마스크와 날짜 타원.

선 굵기는 네 단계예요: `line` 1px(주 가로줄, 컨트롤 윤곽, 팝오버 테두리, 실선), `line-mark` 1.2px(14pt 미만 표식·상자), `line-box` 1.5px(체크 상자, 미리알림 고리, 현재 시각 선, 오류 입력 칸), `line-spine` 1.75px(등줄, 요일 줄 아래). 포커스 링은 2px 틈 + 2px 잉크예요. 이어지는 띠는 이어지는 쪽 끝 선을 열어 두어 여러 칸에 걸친 한 덩어리로 읽혀요.

## Components

### Buttons
잉크 1px 선으로 그은 직각 상자예요. 포인터에는 면으로, 키보드에는 링으로 답해요.
- **Shape:** 직각, 1px `ink` 테두리, 최소 28×28px, 좌우 12px (`DrawnButtonStyle`).
- **Primary (`.primary`):** `ink` 바탕, `on-ink` 글자 13px 600. 화면에 하나(메인 창은 `새 일정`). 포인터·눌림은 잉크 86%.
- **Plain (`.plain`):** `paper` 바탕, `ink` 글자. 포인터 `hover`, 눌림 `row-active`.
- **Toggled (`.toggled`):** 켜진 토글. `row-active` 바탕에 1.5px 잉크 테두리라 hover(채움만)와 모양으로 구분돼요. 잉크로 채우지 않아요.
- **Text (`.text`):** 12px 밑줄 글자, 포인터 `hover`, 눌림 불투명도 0.6. 히트 영역은 사방 4px 더 넓어요.
- **Danger (`.danger`, `.dangerText`):** `danger` 빨강 글자와 테두리, `paper` 바탕(밑줄 글자형은 빨강 밑줄 글자). 되돌릴 수 없는 동작에만: 삭제, 고친 내용·보내지 못한 변경 버리기, 계정 연결 해제.
- **Disabled:** 글자와 테두리 모두 `ink-faint`, 바탕 `paper`.
- **Focus:** 모든 종류가 `focusRing`(종이 2px 틈 + 잉크 2px 링)을 가져요. 자기 모양을 그리는 버튼은 `FocusOnlyStyle`로 링만 받아요. 버튼은 시스템의 키보드 탐색(전체 키보드 접근)이 켜져 있을 때만 스스로 포커스를 받으므로 링도 그때만 보여요(`ownsFocus`). 포커스를 받는 칸을 감싼 컨테이너 때문에 안의 버튼이 모두 링을 그리는 일을 막아요.

### Segmented Tabs
- **Style:** 1px `ink` 선으로 이어 붙인 직각 칸, 높이 28px, 좌우 12px, 13px. 고른 칸은 `ink` 채움 + `on-ink` 600, 포인터 `hover`, 꺼진 칸 `ink-faint`.
- **Variants:** 제목 막대의 `주 | 월 | 년`(내용 폭), 패널의 `하루 | 한 주 | 한 달`(`fillsWidth`, 메모가 있으면 라벨 뒤에 연필 `MemoMark`).

### Chips
- **메모 속 할 일 칩:** `chip` 바탕, 테두리 없음, 글자색은 팔레트 `-ink`. 끝내면 `ink-soft` 취소선. 형광펜이 걸리면 `-tint`가 칩 회색을 덮어요.
- **Tag:** 11px 600 글자와 같은 색의 1px 테두리, 좌우 6 · 위아래 1px. `오늘`(잉크), `읽기 전용`(`ink-soft`), `다시 연결 필요`.

### Cards / Containers
- **메인 종이:** `paper` + `shade` 1px 실선, 그림자 없음(`paperSheet()`).
- **떠 있는 것:** `paper` + `ink` 1px + 4px 그림자(`floatingFrame()`). 모서리 직각.
- **Internal Padding:** 하루 패널 20px, 팝오버 16px, 설정 상자 내용 24px.
- **NoticeBar:** 한 줄 안내 띠. `.warning`은 `error-tint` 바탕 + `exclamationmark.triangle`, `.info`는 `raised` 바탕 + `info.circle`. 글자는 늘 잉크 12px, 앞말은 600, 테두리 1px `ink`.

### Inputs / Fields
하나의 입력 모양 `drawnField(_:focused:error:active:)`를 세 가지로 써요. 메뉴나 날짜 상자를 여는 `.box`(시각·날짜·드롭다운 칸)는 열린 동안 `active: true`로 `row-active` 바탕이에요.
- **`.box`:** 폼 칸. `paper` 바탕, 1px `ink` 테두리, 높이 28px, 좌우 8px, 13px. 포인터 `hover`.
- **`.inline`:** 목록 줄 안에서 고치기. 바탕 없음, 고치는 중 `row-active` 면 + 아래 1px 잉크 줄.
- **`.title`:** 편집기 맨 위 큰 제목. subheading 명조, 아래 줄 `shade` → 포인터 `ink-faint` → 포커스 1.5px `ink`.
- **Focus:** `.box`는 포커스 링, `.inline`·`.title`은 아래 줄로.
- **Error / Disabled:** 오류는 `error-tint` 바탕 + 1.5px 잉크 테두리, 비활성은 `shade-soft` 바탕 + `ink-faint` 글자·테두리(environment로 자동).

### Selection & Rows
- **고른 것** (`selectableRow(chosen: true)`): 여럿 중 하나를 고른 줄·일정·메뉴 커서는 `ink` 채움 + `on-ink` 글자.
- **고치는 중** (`active: true`): `row-active` 회색 + `ink` 글자.
- **포인터:** `hover` 면, 0.12초 easeOut.
- **고른 날:** 월간 칸은 좌·우·아래 1px 잉크 선이 주 가로줄과 만나 칸 하나를 닫아요. 포인터는 칸 안쪽 4px의 `shade` 상자예요.

### Checkboxes & Marks
- **CheckBox:** 16px 직각 상자, 1.5px `ink` 선(14px 미만 1.2px). 켜면 `ink` 채움 + 굵은 체크(`on-ink`). 포인터는 빈 상자를 `hover`로, 고른(잉크) 줄 위에서는 `on-ink`로 그려요. 할 일·설정·편집기가 모두 이 하나를 써요(`CheckBoxButtonStyle`, `DrawnCheckboxStyle`).
- **Mark:** 일정·라벨 색 네모, 기본 10px. 9px 이하는 1px, 그보다 크면 1.2px `ink` 테두리. 위젯은 테두리 없이.
- **패턴 표식(8단계):** 설정에서 패턴을 켜면(`showsPalettePatterns`) 캘린더 표식이 그 캘린더의 모양이 돼요. 모양은 네모, 세모, 마름모, 십자, 속 빈 네모, 세로 막대, 가로 막대, 반 채운 네모, X 아홉 가지이고, 캘린더마다 고르거나 "자동"이면 색에 맞는 모양(빨강 네모, 주황 세모, 노랑 마름모, 초록 십자, 청록 속 빈 네모, 파랑 세로 막대, 보라 가로 막대, 분홍 반 채운 네모, 회색 X)을 따라요. 잉크 테두리 없이 색만으로 그리고(네모만 평소 표식 그대로), 둥근 모양은 미리알림 고리와 헷갈려서 쓰지 않아요. 종일 띠는 왼쪽 6px 색 막대 대신 띠 앞에 같은 모양 표식을 두고, 주 보기 일정 칸은 색 막대를 두고 제목 앞에 표식을 더해요. 모양은 Kit `Mark(_:shape:)` 한 곳에서 그려요.
- **색·모양 버튼(설정 › 캘린더, 8단계):** 줄 오른쪽에 meta 글자의 작은 상자(`shade` 1px). `파랑`, 자동이면 `자동 · 파랑`, 색상 휠 색이면 `직접 고른 색`, 모양을 고르면 뒤에 `· 세모`. 누르면 버튼 아래 상자(`anchoredPop`)에 "개인 색"(자동 점선 + 팔레트 9색 28px, 다섯 개씩 두 줄, 그 아래 "다른 색…" 줄이 macOS 색상 휠을 열어요)과 "모양"(자동 + 아홉 가지, 그 캘린더 색으로). 쓰는 것은 2px 잉크 상자로 둘러요. 고르고 나도 팝은 열려 있고, 화살표가 두 묶음을 오가며 Return으로 고르고 Esc로 닫아요. 공휴일 캘린더는 버튼 없이 잠가요. 고른 값은 App Group 기본값(`CalendarStyles`)에 두고 캐시 스키마는 건드리지 않아요.
- **ReminderMark:** 같은 크기의 원형 고리(팔레트 `-ink`, 1.4~1.5px), 끝내면 채움 + `on-ink` 체크.
- **TodoCount / MemoMark:** 날짜 줄 끝의 `✓N`(meta, `ink-soft`)과 연필 표식.

### Ink Menu (메뉴 한 벌)
우클릭 메뉴와 드롭다운은 시스템 `NSMenu`가 아니라 Kit `InkMenu`로 그려요. 모델은 `InkMenuEntry`(줄 `.item`, 구역 제목 `.section`, 구분선 `.divider`, 하위 메뉴 `.submenu`)이고, 줄은 `detail`(오른쪽 `ink-soft`: 날짜 `11.4`, 기간 `11월 1주차`, 단축키 `⌘X`), `swatch`(색 견본, 패턴을 켜면 모양), `checked`(✓, 고를 수 있는 값 목록이면 모든 줄에 12px 열을 비워 둬요), `isEnabled`, `isDanger`를 가져요.
- **틀:** `floatingFrame`(종이, 잉크 1px, 흐림 없는 4pt 그림자), 직각, 위아래 4px. 최소 너비 128px, 드롭다운은 버튼 너비 이상.
- **줄:** 높이 26px(body 13px), 왼쪽 10px·오른쪽 12px. 커서 줄은 `selection` 잉크 채움 + `on-ink` 글자, 되돌릴 수 없는 줄은 `danger` 글자이고 커서가 오면 `danger` 채움. 쓸 수 없는 줄은 `ink-faint`이고 커서가 건너뛰어요. 구역 제목은 11px 600 `ink-soft`(높이 22px), 구분선은 `shade` 1px(위아래 4px).
- **자리:** 우클릭은 포인터 자리, 드롭다운은 버튼 아래 1px 겹쳐(공간이 없으면 위), 하위 메뉴는 그 줄 옆에 6px 겹쳐요. 창 밖으로 나가도 되도록 테두리 없는 자식 패널(`InkPanel`)에 띄워요.
- **긴 목록:** `maxItems`(시각 메뉴 9줄)로 높이를 막고 스크롤, 오른쪽 3px `ink-faint` 막대. 열면 고른 값이 가운데예요. 시각 메뉴는 숫자(`14`, `230`)를 치면 가장 가까운 시각으로 커서가 가고, 오전·오후는 지금 시각에 가까운 쪽이에요(`TimeTypeahead`).
- **키보드·닫기:** ↑↓, → 하위 열기, ← 닫기, Return·Space 고르기, Esc 닫기. 열 때 고른 값(없으면 첫 줄)에 커서. 바깥 클릭(그 클릭은 삼켜요)·창 비활성·스크롤·창 이동이면 닫혀요. ⌘ 단축키는 메뉴를 닫고 창으로 가요.
- **VoiceOver:** 패널은 메뉴, 줄은 메뉴 항목으로 읽혀요. 줄의 `.accessibilityAction(.showMenu)`(VO-Shift-M)로도 같은 메뉴가 열려요(`inkContextMenu`, 메모 상자).
- **쓰는 법:** 드롭다운은 버튼 + `.inkMenu(isPresented:)`, 우클릭은 `.inkContextMenu(isEnabled:isOpen:)`(열린 동안 그 줄은 `row-active`), AppKit에서는 `InkMenuPresenter.popUp`.

### Anchored Pop (버튼에 붙는 상자, A안)
버튼에서 나오는 상자(오프라인 대기 목록, 색·모양 고르기, 일정 날짜)는 `.anchoredPop(isPresented:)`로 메뉴와 같은 자리·같은 틀에 화살표 없이 띄워요. 키보드를 받아서 안에서 Tab으로 움직이고, 바깥 클릭·Esc로 닫혀요(버튼을 다시 누르면 닫히기만 해요). 버튼은 열린 동안 `row-active`(`DrawnButtonStyle(_:active:)`, `drawnField(active:)`). 일정 팝오버는 달력 칸을 가리키므로 화살표를 그대로 둬요.

### Date Picker (작은 장부)
`InkDatePicker`: 머리에 고운바탕 15px "2026년 11월"과 `‹ 오늘 ›`, 요일 줄(meta, 일요일 `holiday`) 아래 1.75px 잉크, 칸 32×28px에 small 숫자, 주마다 `shade` 가로줄 하나(주말·주 끝에도 잉크 줄 없음), 오늘은 숫자 위 3px 잉크 막대 + 700, 일요일·공휴일 `holiday`, 다른 달 `ink-faint`, 고른 날 `ink` 채움. 아래 "고른 날 · 11월 12일 목요일". 주 시작 요일을 따라요. 화살표 하루·한 주, PageUp/PageDown 한 달, T 오늘, Return 고르기. 일정 날짜 칸(버튼에 붙는 상자 안)과 할 일 넘기기·만들기의 "다른 날짜…"가 같이 써요.

### Navigation
- **Title bar:** macOS 제목 막대 위에 `새 일정`(주 버튼), 가운데 `주 | 월 | 년` 세그먼트, 오른쪽 맞춤 상태(meta, `ink-soft`)와 패널 토글. 명조 30px 제목과 `‹ 오늘 ›`는 종이 위 달력 머리에 있어요.
- **SectionRule:** 섹션 이름(section 12px 600) 뒤로 1px `ink` 줄이 끝까지 이어지고, 끝에 글자 버튼이 붙어요.

### Ink Ledger Sheet (signature)
한 장의 종이에 격자와 패널이 같이 있고, 사이에 1.75px 잉크 등줄 하나가 있어요. 월간 칸: SF 15px 600 등폭 날짜 숫자, 옆에 메모 연필, 오른쪽 끝 `✓N`. 오늘은 칸 위 가로줄 바로 아래 3px 잉크 막대(첫째 주에서도 굵은 요일 줄 밑에 보여요)와 700 숫자, 일요일·공휴일은 `holiday` 숫자, 다른 달은 면을 바꾸지 않고 `ink-faint` 숫자에 일정 줄을 60%로 낮춰요, 주말은 `raised` 면. 종일·여러 날 일정은 `-tint` 띠 + 왼쪽 6px `-ink` 끝 + 1px `ink` 외곽(이어지는 쪽 열림), 미리알림은 고리 + 끝내면 취소선, 고른 일정은 `ink` 바탕 + `on-ink` 글자로 뒤집혀요.

### Week Grid
주 보기 시간 블록은 `-tint` 면, 왼쪽 4px `-ink` 끝, 1px `ink` 외곽 상자, 제목은 600 + 시작 시각 meta. 머리글의 오늘은 위 3px 잉크 막대, 고른 날은 좌·우 1px 잉크 선이에요. 주말 열은 `raised`, 포인터가 올라간 열은 `hover`예요.

### Now Line
현재 시각은 잉크예요. 주 보기 오늘 열은 1.5px 잉크 실선 + 7px 점, 다른 열은 1px `ink-faint` 3/3 점선이에요. 하루 패널 일정 목록에서는 굵은 시각 글자 + 1.5px 잉크 선 + 7px 점이 일정 사이에 끼고, 하루 띠에서는 2px 잉크 세로선이에요.

### Day Strip (하루 띠)
하루 패널 제목 아래, 9시부터 24시까지를 한 줄(높이 34px)로 보여 줘요. 2px `shade` 바탕 줄 위에 일정은 높이 18px의 `-tint` 블록 + 1px `ink` 외곽 + 왼쪽 3px `-ink` 끝, 미리알림은 9px 고리, 오늘이면 2px 잉크 현재 시각 선. 아래에 3시간마다 `9시 … 24시`(meta, `ink-soft`). 빈 시간이 어디인지 한눈에 보이게 하는 장치예요(`DayStrip`).

### Widget C "불 끈 갤러리" (준비됨)
선 없이 면의 밝기로 액자를 만드는 위젯이에요. `widget-surface` 바탕 + 18px 연속 곡선 마스크(`widgetSurface()`), 날짜는 `widget-nest` 타원(76×62px) 속 big-date 명조 숫자(`DateOval`), 아래 meta 글자. `Mark`는 테두리 없이(`outlined: false`). 토큰과 컴포넌트만 Kit에 있고 위젯 화면은 7단계예요.

### Dark D1 "흑연"
다크는 검정이 아니라 따뜻한 회갈색이에요. 벽 `wall-dark`, 종이 `paper-dark`, 주말 `raised-dark`에 밝은 잉크 `ink-dark`. 같은 규칙(등줄, 주 가로줄, 잉크 채움 선택)이 그대로 뒤집혀요. 고른 세그먼트와 주 버튼은 밝은 잉크 채움 + 흑연색 글자예요.

## Do's and Don'ts

### Do:
- **Do** 메인 종이는 `MainView`의 `paperSheet()` 한 번으로 두고, 격자와 패널 사이는 `Metrics.lineSpine`(1.75) 잉크 등줄 하나로 나눠요.
- **Do** 떠 있는 것(팝오버, 메뉴, 모달)은 `floatingFrame()`으로, 어두운 막 위에서는 `floatingFrame(shadow:)`로 그려요.
- **Do** 선은 `Metrics.line` 1 / `lineMark` 1.2 / `lineBox` 1.5 / `lineSpine` 1.75 네 단계로만 그어요.
- **Do** 고른 것은 `Tokens.selection`(잉크) + `on-ink`, 고치는 줄은 `row-active`, 포인터는 `hover`로, 줄에는 `selectableRow(chosen:active:)`를 써요.
- **Do** 글자는 `.textStyle(…)`, 간격은 `Metrics.spaceXxs…spaceXxxl`로 써요.
- **Do** 입력 칸은 `drawnField(.box | .inline | .title, focused:, error:)`, 버튼은 `DrawnButtonStyle` 다섯 종류, 체크는 `CheckBox` 하나로 그려요.
- **Do** 키보드로 갈 수 있는 곳은 `focusRing`(종이 2px 틈 + 잉크 2px)을 보여 줘요. 버튼의 링은 전체 키보드 접근이 켜졌을 때만이에요.
- **Do** 오류·경고는 `NoticeBar(tone: .warning)` 또는 잉크 글자 + `exclamationmark.triangle`으로 알려요.
- **Do** 팔레트 색은 `-ink`(표식·글자·끝 줄)와 `-tint`(면)를 쌍으로 꺼내 써요.
- **Do** 미끄러지는 전환은 동작 줄이기가 켜져 있으면 투명도만 바꿔요.

### Don't:
- **Don't** 격자나 패널 뷰에 자기 배경·테두리·그림자를 그리지 마세요. 메인 종이는 한 장이에요.
- **Don't** 이중선(몰딩), 장식선, 블러 있는 그림자, 그라데이션을 쓰지 마세요.
- **Don't** 빨강을 공휴일과 되돌릴 수 없는 동작 말고 쓰지 마세요. 오류, 현재 시각 선, 오늘 표시는 잉크예요.
- **Don't** 팔레트 색을 틀(툴바, 버튼, 테두리, 고른 상태)에 쓰지 마세요.
- **Don't** `ink`로 채운 주 버튼을 화면에 둘 이상 두지 마세요. 켜진 토글은 `row-active` 바탕에 굵은 테두리예요.
- **Don't** 고운바탕을 날짜 숫자, 이메일, 문장, 숫자 칸에 쓰지 마세요. 한글에 자간을 주지 마세요.
- **Don't** `ink-faint`를 읽어야 하는 글자에 쓰지 마세요. 빈 상태 문장은 `ink-soft`예요.
- **Don't** 모서리를 둥글게 만들지 마세요. 미리알림 고리, 현재 시각 점, 위젯 말고는 직각이에요.
- **Don't** 시스템 세그먼트 컨트롤이나 둥근 시스템 버튼 스타일을 쓰지 마세요.

## 남은 차이

시스템 규칙이 아니라, 지금 코드가 아직 이 시스템을 다 따르지 못하는 곳이에요. 새 화면이 따라 할 대상이 아니에요.

- **시스템이 그리는 곳:** 메뉴 막대(`CommandMenu`), `.help` 도움말, 색상 휠(`NSColorPanel`), 권한·로그인 창은 시스템 모양 그대로예요. 한 줄 입력 칸(`TextField`)의 우클릭 메뉴와 글자 선택·커서 색도 시스템 강조색이에요. 메모 상자만 잉크 커서와 `row-active` 선택으로 바꿨어요(포커스를 받을 때 그 `NSTextView`에 줘요).
- **메모 맞춤법:** 메모 우클릭은 할 일 항목과 잘라내기·복사·붙여넣기·모두 선택·굵게·기울임·서식 지우기만 둬요. 붉은 밑줄 검사는 그대로이고, 고치기·대치·말하기·서비스는 메뉴 막대 › 편집에서만 돼요.
- **날짜 고르기의 공휴일:** 지금 달력에 불러온 범위의 공휴일만 빨강이에요. 그 밖의 달로 넘기면 일요일만 빨강이에요.
- **위젯 미구현(7단계):** `Widgets/SimplifyWidgets.swift`는 아직 자리표시예요. `.containerBackground(.background)`, 시스템 serif 44, `.caption`을 써서 `widgetSurface()` · `DateOval` · `big-date`를 쓰지 않아요.
- **투명도:** 설정의 어두운 막(`opacity-scrim`)과 상자 그림자, 주 버튼 hover, 다른 달 일정은 `tokens.json`의 `opacity` 단계(`Metrics.opacity*`)를 써요. 다만 바탕색은 토큰이 아닌 `Color.black`이에요(막은 테마와 상관없이 검정이라서요).
- **패널 시각 자리:** 하루 탭은 시각이 왼쪽, 한 주 탭은 날짜별로 묶어서 시각이 오른쪽이에요. 월 칸은 좁아서 24시간제(`14:00`), 패널은 `오후 2:00`이에요.
- **색 패턴 옵션(8단계):** 설정 › 일반 › 모양의 "색과 함께 패턴도 표시"(기본 꺼짐)는 일정 표식·종일 띠·주 보기 일정 칸·위젯에 모양을 그려요. 패널의 하루 띠(`DayStrip`)와 할 일 줄의 색 라벨은 아직 색만이에요(할 일 메뉴의 색 견본은 모양을 따라요). 메뉴 견본도 이제 `Mark` 한 곳에서 그려요.
- **색상 휠 색:** 팔레트 밖의 색은 대비를 보장하지 않아요(흑연 테마, 노랑 계열). 띠 바탕은 그 색을 종이에 20% 섞어 만들어요. 색상 휠은 시스템 `NSColorPanel`이라 잉크 장부 모양이 아니에요.
- **로그인 항목:** 설정 › 일반 › 시작의 허락 안내는 글자만 있고, 시스템 설정을 여는 버튼은 없어요.
