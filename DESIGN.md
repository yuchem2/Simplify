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
  title-bar: "6px"
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
  title-bar:
    backgroundColor: "{colors.paper}"
  title-bar-control:
    rounded: "{rounded.title-bar}"
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
- 직각 모서리, 둥근 것은 미리알림 고리·현재 시각 점·위젯, 그리고 제목 막대 컨트롤(6px)뿐
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
- **벽** (`wall`): 종이 바깥의 책상이에요. 제목 막대는 벽이 아니라 종이색이에요(아래 Title bar).
- **종이** (`paper`): 한 장의 메인 종이(격자 + 패널), 제목 막대, 팝오버, 메뉴, 설정 상자, 버튼과 입력 칸의 기본 면.
- **한 단계 위 면** (`raised`): 월·주 격자의 주말 열, 일반 안내(`NoticeBar` info) 바탕.
- **보조 잉크** (`ink-soft`): 시간, 요일 이름, 캘린더 이름, 할 일 출처, 하루 띠 시각 글자, 빈 상태 문장.
- **흐린 잉크** (`ink-faint`): 다른 달 날짜, 자리표시 글자, 꺼진 컨트롤, 다른 날 열의 현재 시각 점선. 3:1만 보장해서 읽어야 하는 글자에는 쓰지 않아요.
- **그늘** (`shade`): 종이가 벽과 만나는 실선, 주 보기의 시간 가로선과 날짜 세로선, 하루 띠의 바탕 줄, 칸 위 포인터 상자, 라이트의 떠 있는 그림자.
- **옅은 그늘** (`shade-soft`): 비활성 입력 칸, 메모 코드 블록과 줄 안 코드의 바탕.
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

창 맨 위는 macOS의 진짜 제목 막대예요. 신호등 옆에 `+ 새 일정`(주 버튼), 가운데에 `주 · 월 · 년` 세그먼트, 오른쪽에 맞춤 상태와 패널 토글이 있고, 모두 우리 잉크 컨트롤이라 시스템 유리 배경은 꺼요. 빈 곳 끌기·이중 클릭(채우기 포함)·채운 창 끌어 원래 크기로는 시스템이 처리해요. 제목 막대 바탕도 종이(`paper`)이고, 그 아래 종이 한 장이 창 가장자리까지 차며 제목 막대와는 `shade` 1px 실선 하나로 나뉘어요. 라이트·다크 모두 같아요. 종이 안 왼쪽은 달력 영역으로, 머리(고운바탕 제목 + 오른쪽 `‹ 오늘 ›`) 아래 월간 격자, 주 보기, 년 보기 중 하나예요. 오른쪽은 하루 패널이고, 둘 사이는 1.75px 잉크 등줄 하나예요. 패널은 숨기기 · 보통 · 넓게 세 상태예요(아래 "Day Panel States"). 창 최소 크기는 790×600px로 11인치 iPad 너비(834)보다 좁아요. 설정은 창 전체(제목 막대 포함)를 옅게 어둡게 깐 위에 뜬 상자예요(최대 760×540px, 창 가장자리에서 32px 이상 띄움). 머리는 `설정` 제목과 ×, 메뉴와 내용 사이는 잉크 등줄이고, 설정이 열린 동안 제목 막대의 컨트롤은 숨어요. ×, esc, 상자 바깥 클릭으로 닫혀요. 캘린더 메뉴에서는 계정 이름을 눌러 그 계정의 캘린더를 접어요. 테마는 설정 › 일반에서 시스템 · 흰 벽 · 흑연. 패널은 `⌘\`로 접히며 0.2초 easeOut으로 오른쪽으로 빠지고, 동작 줄이기가 켜져 있으면 투명도만 바뀌어요. 보통 ↔ 넓게도 같은 0.2초 easeOut이고, 달력과 작은 달력은 투명도로 바뀌어요.

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

**예외 하나: 제목 막대 컨트롤은 6px 둥근 모서리예요.** 창의 신호등·시스템 컨트롤과 나란히 놓이는 자리라 macOS 컨트롤 크기에 맞춰요. 대상은 `+ 새 일정`, `주 | 월 | 년`, 맞춤 상태·보내기 대기 단추, 패널 세 칸뿐이고, 환경값 `controlCornerRadius`(`MainToolbar.titleBarRadius` = 6)로 그 자리에서만 켜요. 같은 스타일을 쓰는 다른 곳(종이 위 `‹ 오늘 ›`, 패널의 `오늘 | 이번 주 | 이번 달`, 메모 탭, 서식 막대, 팝오버)은 직각 그대로예요. 둥글 때는 테두리·hover 면·포커스 링이 같은 모서리를 따라요. 제목 막대에서 열리는 팝은 직각으로 되돌려요.

선 굵기는 네 단계예요: `line` 1px(주 가로줄, 컨트롤 윤곽, 팝오버 테두리, 실선), `line-mark` 1.2px(14pt 미만 표식·상자), `line-box` 1.5px(체크 상자, 미리알림 고리, 현재 시각 선, 오류 입력 칸), `line-spine` 1.75px(등줄, 요일 줄 아래). 포커스 링은 2px 틈 + 2px 잉크예요. 이어지는 띠는 이어지는 쪽 끝 선을 열어 두어 여러 칸에 걸친 한 덩어리로 읽혀요.

## Components

### Buttons
잉크 1px 선으로 그은 직각 상자예요. 포인터에는 면으로, 키보드에는 링으로 답해요.
- **Shape:** 직각, 1px `ink` 테두리, 최소 28×28px, 좌우 12px (`DrawnButtonStyle`).
- **Primary (`.primary`):** `ink` 바탕, `on-ink` 글자 13px 600. 화면에 하나(메인 창은 `새 일정`). 포인터·눌림은 잉크 86%.
- **Plain (`.plain`):** `paper` 바탕, `ink` 글자. 포인터 `hover`, 눌림 `row-active`.
- **Toggled (`.toggled`):** 켜진 토글. `row-active` 바탕에 1.5px 잉크 테두리라 hover(채움만)와 모양으로 구분돼요. 잉크로 채우지 않아요.
- **Bare (`.bare`):** 테두리도 바탕도 없는 13px 글자·아이콘. 포인터 `hover`, 눌림 `row-active` 면만 있어요. 제목 막대 오른쪽의 `캘린더 연결`(+) 하나에만 써요.
- **Text (`.text`):** 12px 밑줄 글자, 포인터 `hover`, 눌림 불투명도 0.6. 히트 영역은 사방 4px 더 넓어요.
- **Danger (`.danger`, `.dangerText`):** `danger` 빨강 글자와 테두리, `paper` 바탕(밑줄 글자형은 빨강 밑줄 글자). 되돌릴 수 없는 동작에만: 삭제, 고친 내용·보내지 못한 변경 버리기, 계정 연결 해제.
- **Disabled:** 글자와 테두리 모두 `ink-faint`, 바탕 `paper`.
- **Focus:** 모든 종류가 `focusRing`(종이 2px 틈 + 잉크 2px 링)을 가져요. 자기 모양을 그리는 버튼은 `FocusOnlyStyle`로 링만 받아요. 버튼은 시스템의 키보드 탐색(전체 키보드 접근)이 켜져 있을 때만 스스로 포커스를 받으므로 링도 그때만 보여요(`ownsFocus`). 포커스를 받는 칸을 감싼 컨테이너 때문에 안의 버튼이 모두 링을 그리는 일을 막아요.

### Segmented Tabs
- **Style:** 1px `ink` 선으로 이어 붙인 직각 칸, 높이 28px, 좌우 12px, 13px. 고른 칸은 `ink` 채움 + `on-ink` 600, 포인터 `hover`, 꺼진 칸 `ink-faint`.
- **Variants:** 제목 막대의 `주 | 월 | 년`(내용 폭, 6px 둥근 모서리), 패널의 `하루 | 한 주 | 한 달`(`fillsWidth`, 메모가 있으면 라벨 뒤에 연필 `MemoMark`), 제목 막대의 패널 세 칸(`IconSegments(bare: true)`, 아이콘 칸). 패널 세 칸은 테두리와 칸 사이 줄 없이 2px 간격으로 떨어져 있고, 고른 칸의 잉크 채움과 포인터 `hover` 면만 6px 둥근 모서리로 보여요.

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
- **Title bar:** 종이색(`paper`) macOS 제목 막대 위에 `새 일정`(주 버튼), 가운데 `주 | 월 | 년` 세그먼트, 오른쪽 맞춤 상태(meta, `ink-soft`, 연결된 캘린더가 없으면 테두리 없는 `+ 캘린더 연결`)와 테두리 없는 패널 토글. 컨트롤은 6px 둥근 모서리(위 Shapes의 예외)이고, 종이와는 `shade` 1px 선으로 나뉘어요. 오른쪽 묶음의 끝은 창 가장자리에서 20px 안, 패널 내용의 오른쪽 끝과 같은 선이에요. 명조 30px 제목과 `‹ 오늘 ›`는 종이 위 달력 머리에 있어요.
- **SectionRule:** 섹션 이름(section 12px 600) 뒤로 1px `ink` 줄이 끝까지 이어지고, 끝에 글자 버튼이 붙어요.

### Ink Ledger Sheet (signature)
한 장의 종이에 격자와 패널이 같이 있고, 사이에 1.75px 잉크 등줄 하나가 있어요. 월간 칸: SF 15px 600 등폭 날짜 숫자, 옆에 메모 연필, 오른쪽 끝 `✓N`. 오늘은 칸 위 가로줄 바로 아래 3px 잉크 막대(첫째 주에서도 굵은 요일 줄 밑에 보여요)와 700 숫자, 일요일·공휴일은 `holiday` 숫자, 다른 달은 면을 바꾸지 않고 `ink-faint` 숫자에 일정 줄을 60%로 낮춰요, 주말은 `raised` 면. 종일·여러 날 일정은 `-tint` 띠 + 왼쪽 6px `-ink` 끝 + 1px `ink` 외곽(이어지는 쪽 열림), 미리알림은 고리 + 끝내면 취소선, 고른 일정은 `ink` 바탕 + `on-ink` 글자로 뒤집혀요.

### Week Grid
주 보기 시간 블록은 `-tint` 면, 왼쪽 4px `-ink` 끝, 1px `ink` 외곽 상자, 제목은 600 + 시작 시각 meta. 머리글의 오늘은 위 3px 잉크 막대, 고른 날은 좌·우 1px 잉크 선이에요. 주말 열은 `raised`, 포인터가 올라간 열은 `hover`예요.

### Now Line
현재 시각은 잉크예요. 주 보기 오늘 열은 1.5px 잉크 실선 + 7px 점, 다른 열은 1px `ink-faint` 3/3 점선이에요. 하루 패널 일정 목록에서는 굵은 시각 글자 + 1.5px 잉크 선 + 7px 점이 일정 사이에 끼고, 하루 띠에서는 2px 잉크 세로선이에요.

### Day Panel States (숨기기 · 보통 · 넓게)
- **토글:** 제목 막대 오른쪽의 세 칸 세그먼트(`IconSegments`, 테두리 없음). 아이콘은 18×12 창 모양(1.2px 테두리) 안에 패널이 차지하는 만큼 칠해요: 비움(숨기기) / 오른쪽 6px(보통) / 오른쪽 12px(넓게). 고른 칸은 잉크 채움 + 종이색 아이콘. 칸마다 `.help`와 VoiceOver 이름("패널 숨기기", "패널 보통", "패널 넓게"), 묶음 이름은 "패널".
- **단축키·메뉴:** `⌘\` 숨기기/보이기(다시 보이면 숨기기 전 상태), `⌘⇧\` 보통/넓게(숨겨져 있으면 보이며 바꿔요). 보기 메뉴에 체크 표시가 있는 세 항목.
- **보통:** 처음 폭은 창의 32%(300~460px). 등줄을 끌면 300px부터 달력이 월 칸 최소 폭(64 × 7 + 좌우 20)을 지키는 데까지 바뀌고, 고른 폭을 기억해요.
- **넓게:** 달력이 왼쪽 작은 달력 칸(`WideCalendar`, 기본 248px, 248~360px)으로 접히고 패널이 나머지를 모두 써요. 패널은 일정 섹션 없이 하루 띠 · 할 일 · 메모예요(일정은 작은 달력 아래 목록에만). 넓게에서 `주 · 월 · 년`이나 ⌘1~3을 고르면 보통으로 돌아와 그 달력을 보여 줘요.
- **기억:** 상태와 두 폭은 이 Mac의 UserDefaults에만 두고 기기끼리 맞추지 않아요(`isPanelHidden`, `isPanelWide`, `panelWidth`, `miniMonthWidth`).

### Spine Drag (등줄 끌기)
- 등줄 양옆 4px 안에서 포인터가 macOS 좌우 크기 조절 커서(`.columnResize`)로 바뀌어요. 손잡이나 hover 면은 그리지 않아요.
- 보통에서 끌어 달력이 월 칸 최소 폭보다 좁아지고, 달력 최소 폭과 작은 달력 최대 폭의 가운데에서 24px를 더 넘기면 넓게로 접혀요. 넓게에서 가운데에서 24px를 넘겨 오른쪽으로 끌면 보통으로 펼쳐져요(그 사이는 상태가 그대로라 떨리지 않아요, `PanelLayout`). 두 번 클릭하면 그 상태의 기본 폭으로 돌아가요.
- 마우스 전용이라, 같은 일을 세 칸 버튼과 단축키로 할 수 있어요. VoiceOver에서는 숨겨요.
- 월 칸이 68px보다 좁으면(등줄을 끌었거나 가장 작은 창) 시각 일정과 미리알림을 한 줄의 색 표식으로 모으고, 종일 띠는 제목 없이 색만 남겨요(공휴일은 글자 그대로). 그 위에서는 제목이 줄임표로 줄어요. 칸 최소 크기 64×72는 그대로예요.

### Mini Month (작은 달력)
머리에 고운바탕 subheading "2026년 11월"과 `‹ ›`(이전·다음 달). 요일 줄(meta, 일요일 `holiday`) 아래 1.75px 잉크, 칸 높이 28px에 small 등폭 숫자. 오늘은 잉크 채움 + `on-ink` 600, 고른 날은 안쪽 2px 1.5px 잉크 테두리, 일요일·공휴일 `holiday`, 다른 달 `ink-faint`, 메모 있는 날은 숫자 아래 3px `ink-soft` 점. 패널이 한 주면 그 주, 한 달이면 그 달의 날이 `raised` 면이에요. 날짜를 누르거나 화살표로 고른 날을 옮겨요. 아래에 "N월 N일 일정" 섹션 줄과 패널과 같은 일정 줄(누르면 일정 팝오버)이 와요. 패널이 한 주면 "11월 1주차 일정", 한 달이면 "11월 일정"으로 그 기간 일정을 날짜별로 묶어 보여 줘요(날짜 머리 + 일정 줄, 패널의 주간 목록과 같은 모양). 한 달은 일정 있는 날만 두고, 하나도 없으면 "11월은 일정이 없어요."예요.

### Memo (상자 없이 종이에, C2)
- 메모는 상자 없이 "메모" 섹션 줄 아래 종이에 바로 써요. 글 시작선은 섹션 줄·할 일 줄의 왼쪽 선과 같고, 줄은 패널 폭을 끝까지 써요. 패널의 남은 높이를 모두 채우고(최소 170px) 그 안에서 스크롤해요. 일정·할 일이 많아 170px도 안 남으면 패널 전체가 스크롤돼요.
- **포커스:** 왼쪽 줄·테두리·hover 면이 없어요. 쓰는 동안 잉크 커서가 보이고 "메모" 섹션 줄이 1px에서 등줄 굵기 1.75px로 바뀌어요. 이것이 키보드 포커스 표시예요. 빈 메모는 자리 글(`ink-faint`)을 두고 그 영역 아무 곳이나 누르면 쓰기 시작해요.
- **구분선:** 같은 선 글자(─ ━ ═ - = _ ~ ― — –)가 4개 이상 한 줄로 이어지고 그 밖에 공백만 있는 줄은 폭에 맞춘 1px 잉크 가로줄로 그려요. 커서가 그 줄에 들어가면 원래 글자를 보여 줘서 그대로 고칠 수 있어요. 코드 블록 줄은 그대로예요.
- **시각 줄:** `MM.dd HH:mm` 또는 `MM.dd HH:mm-HH:mm`로 시작하는 줄은 시각을 등폭 숫자 + `ink-soft`로 그리고, 시각 뒤 글은 그 메모의 시각 칸(범위가 하나라도 있으면 범위 폭) 끝에서 시작해 꺾인 줄도 거기에 맞춰요. `⌃⌘T`·서식 막대의 "시각"·우클릭 "시각 넣기"·서식 메뉴로 넣어요(하루 메모는 그날, 주간·월간 메모는 오늘, 오늘이 기간 밖이면 고른 날).
- **목록:** `• `(글머리), `- `(대시), `1. `(번호)로 시작하는 줄이에요. 앞의 탭 수가 단계(깊이 제한 없음, 모양은 세 단계마다 되풀이)이고, 첫 단계부터 12px(`MemoLineStyler.listInset`) 들여 쓴 뒤 단계마다 22px 더 들여 써요. 인용문 안·시각 줄 하위 줄 안의 목록도 그 자리에서 12px 들어가요. 이 여백은 메모의 그리기일 뿐이라 메모 앱 거울에는 보내지 않아요(메모 앱이 목록을 스스로 들여 써요). 기호 뒤 글은 22px(번호는 26px) 칸 끝에서 시작하고 꺾인 줄도 거기에 매달려요. 글머리는 단계마다 ● ○ ■(글자의 절반 크기), 대시는 –, 번호는 1. → a. → i.로 저장 글자를 고쳐 다시 매겨요. 줄 앞에서 `- `·`* `·`1. `·`> `를 치면 시작되고(`* `는 `• `로 저장, 바로 ⌘Z 하면 `*`), Return·Tab·⇧Tab·Delete·⌘]·⌘[로 다뤄요. 코드 블록 줄은 그대로예요.
- **인용문:** `> `로 시작하는 줄은 1.75px 잉크 세로줄과 `ink-soft` 글자로 그려요. 세로줄 뒤 12px부터 글이 오고, 인용문 안에도 목록(`> • `)과 제목·머리말을 쓸 수 있어요.
- **제목·머리말·부머리말:** 줄 전체 서식이에요. 제목은 `title`(고운바탕 30/36), 머리말은 `heading`(22/28), 부머리말은 메모 글자 15/26에 600 굵기예요. 제목 줄 끝에서 Return을 치면 다음 줄은 본문이에요.
- **Aa 단추:** "메모" 섹션 줄 끝의 작은 잉크 테두리 단추예요. 포인터를 올리면 0.3초 뒤 단축키 카드(종이, 잉크 1px, 그림자 없음: 제목·머리말·부·본문 ⌥⌘1 2 3 0, 왼쪽·가운데·오른쪽 ⌘⇧L E R, 글머리·대시·번호 ⌘⇧7 8 9, 인용문 ⌘', 첨부 ⌘⇧A, 링크 ⌘K, 굵게·기울임·밑줄 ⌘B I U)가 단추 바로 아래 오른쪽 끝에 맞춰 뜨고 포인터가 떠나면 사라져요. 누르면 카드 대신 문단 막대가 같은 자리(단추 바로 아래, 오른쪽 끝 맞춤, 떠 있는 그림자)에 떠요. 막대는 단추에 붙어 있어서 하나씩 보기의 탭 줄이나 모아 보기의 머리에 밀리지 않아요.
- **문단 막대:** 세 줄이에요. 문단(제목·머리말·부·본문 글자 단추, 오른쪽 끝에 핀), 정렬(SF Symbols `text.alignleft`·`text.aligncenter`·`text.alignright`), 목록(`list.bullet`·`list.dash`·`list.number`·`text.quote`, 구분선, `tablecells`·`paperclip`·`link`). 단추마다 이름과 단축키는 `.help`로만 보여요. 하나를 골라도 닫히지 않아 제목 + 가운데처럼 이어서 고를 수 있고, 고른 뒤 커서는 메모로 돌아가요. Esc, 메모에 글자 입력, 막대·Aa 바깥 클릭, Aa 다시 누르기로 닫혀요. 목록·인용·표·코드 블록·시각 줄과 그 하위 줄·구분선 줄에서는 정렬 단추가 꺼져요(`ink-faint`).
- **고정 도구 막대:** 핀을 누르면 막대가 "메모" 섹션 줄 바로 아래 한 줄 도구 막대(`MemoFormatStrip`)로 붙어요. 왼쪽부터 `본문 ▾`(문단 InkMenu, 단축키 표시), 정렬 셋, 목록 넷과 표·첨부·링크, 핀은 오른쪽 끝(켜짐: 잉크 채움)이고, 아래에 `shade` 1px 선이에요. 단추는 20px 높이예요. 패널에 하나만 있고 모아 보기에서도 지금 쓰는 메모에 적용돼요. 고정된 동안 Aa는 켜진 채 흐리게(50%) 꺼져 있고 포인터를 올리면 단축키 카드만 보여요. 핀을 다시 누르면 떠 있는 막대로 돌아가요. 서식 메뉴 "서식 막대 늘 보이기"와 설정 › 일반 › 메모의 같은 항목도 같은 값이고, 이 Mac에 기억해요(기본 꺼짐, 단축키 없음).
- **정렬:** 왼쪽(기본)·가운데·오른쪽은 줄 전체 서식이에요(저장 `al`: `center`·`right`). 제목·머리말과 함께 쓸 수 있고(제목 줄에서 Return을 쳐도 다음 줄로 이어져요), 목록·인용·표·코드 블록·시각 줄과 그 하위 줄·구분선 줄에는 들어가지 않아요. 빈 줄의 정렬은 그 줄바꿈 글자에 들어가요. ⌘⇧L·⌘⇧E·⌘⇧R(문서 앱에서 흔한 키, ⌘|는 보기 › 패널 넓게 ⌘⇧\와 같은 키라 쓰지 않아요), 서식 메뉴, 막대에서 바꿔요. 메모 앱 거울은 `<div style="text-align: …">`예요.
- **코드:** `{ }`(⌘⇧C)는 한 줄 안의 일부를 골랐으면 고른 글자만 줄 안 코드(13px 고정폭, 제목·머리말 줄에서는 그 크기, `shade-soft` 바탕, 저장 `kc`)로 만들고, 아무것도 고르지 않았거나 여러 줄·줄 전체를 골랐으면 줄 단위 코드 블록이에요. 줄 안 코드는 줄 전체로 넓어지지 않고 형광펜이 없어요. 줄 안 코드 끝에서 Return을 치면 다음 줄은 보통 글자이고, 캐럿만 있을 때 `{ }`는 줄 안 코드 쓰기를 끝내요. 메모 앱 거울은 둘 다 `<tt>`예요.
- **표:** 한 행이 메모 한 줄이고 칸은 탭 글자로 나눠요. 표의 줄마다 표 id(`tl`)가 붙어요. 1px 잉크 격자, 칸 안 여백 좌우 10px, 첫 행은 600 굵기, 숫자만 있는 칸은 오른쪽에 맞춰요. 열은 가장 긴 칸만큼 넓어지되(최소 64px) 표 전체는 메모 폭을 넘지 않아요. 넘치면 좁은 열은 그대로 두고 나머지가 남은 폭을 똑같이 나눠요. 열보다 긴 칸 글은 `…`(`ink-soft`)로 잘라 그리고(커서가 있는 칸은 커서 앞 글을 보여요), 저장 글자는 그대로예요. 칸 안에서 글이 감기지 않아요. 커서가 있는 칸은 2px 잉크 테두리예요. Tab·⇧Tab은 다음·앞 칸, 마지막 칸 Tab은 새 행, Return은 다음 행 같은 칸(마지막 행이면 표 아래 줄)이에요. 칸이나 행 맨 앞의 Delete는 칸을 합치지 않고, 표 다음 줄 맨 앞의 Delete는 표를 지우지 않고 마지막 칸으로 가요. 표는 2열 이상이에요. 넣기는 서식 메뉴·Aa 막대·우클릭의 "표 넣기"(단축키 없음, ⌥⌘T는 보기 메뉴 도구 막대), 표 안 우클릭은 행·열 넣고 지우기, 표를 글로 바꾸기, 표 지우기예요. 칸 안 수식은 LaTeX 글자로만 보여요. 메모 앱 거울은 `<table>`이에요.
- **표 복사·붙여넣기:** 표 행이 든 글을 복사하면 클립보드에 탭으로 나눈 글(스프레드시트용), `<table>` HTML(메모 앱·Pages·웹용), Simplify 전용 형식(`dev.yoom.simplify.memo`, 메모 글자 그대로)을 같이 써요. 붙여넣기는 앞에서부터 맞는 것 하나예요: Simplify 전용 형식(표 id만 새로) → HTML·RTF 안의 표(메모 앱, 엑셀, 숫자 앱, 구글 시트, 워드, 웹) → Markdown 표(머리 행 + `|---|`) → 탭으로만 나뉜 격자(두 줄 이상, 칸 수가 2개 이상으로 같고, 탭·목록 기호·시각으로 시작하는 줄이 없을 때) → 그냥 글. 칸 안 줄바꿈은 공백, 병합 칸은 첫 칸에 글자, 가장자리의 빈 행·열은 빼고, 1열은 줄로 넣어요. 바깥 칸 서식은 굵게·기울임·밑줄·취소선과 http·https·mailto 링크만 남아요. 캐럿 줄에 글이 있으면 표는 다음 줄부터예요. 표 칸 안에 표를 붙이면 그 칸부터 오른쪽·아래로 채우고 모자라면 행·열을 늘려요. 200행이나 20열을 넘으면 캐럿 자리의 잉크 메뉴로 한 번 물어요. 붙여넣기 한 번이 실행 취소 한 번이에요.
- **링크:** 글자에 주소를 거는 서식이에요(저장 `ln`, 형식 버전은 그대로라 옛 빌드는 평범한 글자로 보이고 그 빌드가 저장하면 링크가 빠져요). http·https·mailto만 받고 `www.…`에는 https를 붙여요. 글자는 잉크색 그대로, 아래에 `link`(= 잉크) 1px 밑줄을 `MemoLineStyler`가 그려요(모아 보기의 읽기 전용 메모·표 칸도 같고, …로 잘린 칸은 보이는 글자까지만). 넣기: 글을 고르고 ⌘K·Aa 막대와 고정 도구 막대의 `link` 단추·서식 메뉴 "링크…" → 고른 글 바로 아래 패널 팝(잉크 테두리)에 주소 칸, `넣기`(링크 안이면 `고치기`·`링크 지우기`), Return 넣기·Esc 취소. 아무것도 안 골랐으면 주소 글자를 링크로 넣어요. 한 줄·한 칸 안의 글자만 받아서 줄이나 칸을 넘는 선택에서는 단추가 꺼져요. 고른 글 위에 주소 하나만 든 클립보드를 ⌘V 하면 글자는 두고 링크만 걸려요(⌥⇧⌘V는 글자 그대로). 주소를 치고 스페이스·Return을 누르면 자동 링크(코드 안 제외, 문장 끝 `.`·`)` 등은 빼요). 마우스를 올리면 주소와 "⌘-클릭으로 열기" 툴팁, ⌘-클릭으로 열고 그냥 클릭은 커서만 놓아요. 링크 끝에서 이어 친 글자는 링크가 아니에요. 복사하면 HTML `<a href>`·RTF 링크·Simplify 전용 형식이 같이 가고, 웹·문서에서 붙인 링크도 남아요. 메모 앱 거울은 `<a href>`예요.
- **자동 서식 ⌘Z:** 줄 앞에서 `1. `·`- `·`> `(인용 안 목록 포함)를 쳐서 목록·인용이 된 바로 뒤 ⌘Z는 글자를 두고 서식만 풀어요(한 번 더 누르면 지금처럼 방금 친 글자가 스페이스와 함께 지워져요). 줄 앞(인용 안 목록이면 `> ` 뒤)의 보이지 않는 U+2060(`MemoLists.plainMark`)으로 기억하고, 그 줄은 Return·Tab·번호 다시 매기기에서 빠지며 옛 빌드·메모 앱에서도 평범한 줄이에요. 서식 메뉴·⌘⇧7/8/9로 목록을 만들면 그 글자를 빼요. 복사에는 넣지 않고, ←·→·Delete는 그 글자에서 한 번 더 멈추지 않아요. `* `→`• `와 자동 링크도 ⌘Z 한 번에 서식만 풀려요.
- **메모 순서:** 메모가 둘 이상이면 하나씩의 탭을 4pt 넘게 끌어 옮겨요(탭이 여러 줄이어도 놓을 줄의 자리에, `+ 새 메모` 뒤는 안 돼요). 끄는 탭은 종이 조각처럼 들려(종이 + 잉크 1px + 떠 있는 그림자, -2°) 포인터를 따라오고 원래 자리는 흐려지며, 놓을 자리에 2px 잉크 세로선이 서요. 모아 보기에서는 머리글을 위아래로 끌고 놓을 자리에 동그란 끝이 달린 2px 가로 잉크선이에요(본문은 접지 않아요). 한 번 클릭 열기·두 번 클릭 이름 바꾸기는 그대로이고, 이름을 바꾸는 중·메모 하나·읽을 수 없는 메모는 끌지 않아요. 오른쪽 클릭 메뉴와 접근성 동작에 앞으로 옮기기·뒤로 옮기기가 있어요. 동작 줄이기에서는 들린 조각 없이 선만 보여요. 저장은 `DiaryNote.order`(처음 옮길 때 기간의 메모 전부에 0, 1, 2…, 그 뒤엔 앞뒤 중간값)이고 동기화는 이름처럼 새로 바꾼 쪽을 따라요.
- 구분선·시각 줄·목록·인용문·표는 화면 표시만 바꿔요(TextKit 2의 문단 표시와 그리기 조각, `MemoLineStyler`). 저장되는 글자, 기기 동기화, 메모 앱 거울은 원래 글자예요.

### Day Strip (하루 띠)
하루 패널 제목 아래, 9시부터 24시까지를 한 줄(높이 34px)로 보여 줘요. 2px `shade` 바탕 줄 위에 일정은 높이 18px의 `-tint` 블록 + 1px `ink` 외곽 + 왼쪽 3px `-ink` 끝, 미리알림은 9px 고리, 오늘이면 2px 잉크 현재 시각 선. 아래에 3시간마다 `9시 … 24시`(meta, `ink-soft`). 빈 시간이 어디인지 한눈에 보이게 하는 장치예요(`DayStrip`).

### Widget C "불 끈 갤러리" (준비됨)
선 없이 면의 밝기로 액자를 만드는 위젯이에요. `widget-surface` 바탕 + 18px 연속 곡선 마스크(`widgetSurface()`), 날짜는 `widget-nest` 타원(76×62px) 속 big-date 명조 숫자(`DateOval`), 아래 meta 글자. `Mark`는 테두리 없이(`outlined: false`). 토큰과 컴포넌트만 Kit에 있고 위젯 화면은 7단계예요.

### Dark D1 "흑연"
다크는 검정이 아니라 따뜻한 회갈색이에요. 벽 `wall-dark`, 종이 `paper-dark`, 주말 `raised-dark`에 밝은 잉크 `ink-dark`. 같은 규칙(등줄, 주 가로줄, 잉크 채움 선택)이 그대로 뒤집혀요. 고른 세그먼트와 주 버튼은 밝은 잉크 채움 + 흑연색 글자예요.

## App Icon (I4 "잉크 장부")

- **구성:** 왼쪽에 월 달력 한 장, 오른쪽에 등줄 자리에 선 연필 한 자루. 요일 표식 7개(일요일만 공휴일 빨강), 요일 줄은 등줄 굵기, 다섯 주 잉크 가로줄, 일·토 주말 면, 둘째 주 수요일 칸 위쪽의 오늘 막대. 글자는 없어요. 824 그리드 좌표를 1024 정사각에 꽉 채워 그리고, 둥근 모서리는 시스템이 깎아요. 시트의 그림은 좌우 여백이 96·130으로 왼쪽에 치우쳐 있어서, 앱 아이콘은 모양은 그대로 두고 전체를 오른쪽으로 17 옮겨 가운데에 맞췄어요(1024px에서 좌우 140px).
- **색:** 라이트 종이 `#FBFAF7` · 잉크 `#1A1A1A` · 주말 면 `#EAE8E2` · 빨강 `#B3332A`. 다크(흑연) 종이 `#2A2927` · 잉크 `#ECEBE6` · 주말 면 `#33312E` · 빨강 `#FF8A7A`. 다크와 잉크는 토큰(`paper`/`ink`/`raised`)과 같고, 라이트 종이·주말 면은 시안 시트 값 그대로라 토큰(`#FFFFFF`/`#F7F7F5`)보다 한 단계 짙게 썼어요. 빨강은 `red-ink`.
- **레이어:** Icon Composer 문서 `Apps/macOS/AppIcon.icon`. 바탕(종이)은 문서 fill, 그 위에 `Faces` 그룹(주말 면, 유리 없음), 맨 앞 `Ink` 그룹(`ink` 줄·오늘 막대·연필, 연필의 종이색 줄은 구멍 / `red` 일요일 표식, 둘 다 Liquid Glass). 라이트·다크는 레이어 그림을 따로 넣고, 클리어·틴트에서는 주말 면을 숨겨 잉크만 유리로 보여요.
- **작은 크기:** `.icon`은 크기별 그림을 받지 않아서 시스템이 같은 그림을 줄여요. 16pt에서는 주 가로줄이 옅은 회색이 되고 연필·오늘 막대·요일 줄이 남아요. 시안 렌더러의 작은 크기 단순화(detail 0·1)는 시트에서만 쓰여요.
- **원본:** `design/icon/make-icon.swift`가 레이어 PNG와 `icon.json`을 다시 만들어요(`swift design/icon/make-icon.swift .`). `AppIcon.icon` 폴더를 통째로 다시 쓰니, Icon Composer에서 직접 고치지 말고 이 스크립트를 고쳐요. `--check <폴더>`는 가운데 맞춤 이동을 뺀 레이어를 겹쳐 시안 렌더러 `design/icon/render5.swift`의 I4 그림(`icon-I4-{light,dark}-fullbleed.png`)과 같은지 봐요. 그 PNG는 `~/Dev/personal/mockup/simplify/icon/`에 있고, `swift design/icon/render5.swift <폴더> <GowunBatang-Bold.ttf>`로 다시 만들 수 있어요. 디자인 철학은 `design/icon/philosophy.md`.

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
- **Don't** 모서리를 둥글게 만들지 마세요. 미리알림 고리, 현재 시각 점, 위젯, 제목 막대 컨트롤(6px) 말고는 직각이에요.
- **Don't** 시스템 세그먼트 컨트롤이나 둥근 시스템 버튼 스타일을 쓰지 마세요.

## 남은 차이

시스템 규칙이 아니라, 지금 코드가 아직 이 시스템을 다 따르지 못하는 곳이에요. 새 화면이 따라 할 대상이 아니에요.

- **시스템이 그리는 곳:** 메뉴 막대(`CommandMenu`), `.help` 도움말, 색상 휠(`NSColorPanel`), 권한·로그인 창은 시스템 모양 그대로예요. 한 줄 입력 칸(`TextField`)의 우클릭 메뉴와 글자 선택·커서 색도 시스템 강조색이에요. 메모 상자만 잉크 커서와 `row-active` 선택으로 바꿨어요(포커스를 받을 때 그 `NSTextView`에 줘요).
- **메모 맞춤법:** 메모 우클릭은 할 일 항목과 잘라내기·복사·붙여넣기·모두 선택·굵게·기울임·밑줄·취소선·서식 지우기, 문단·목록 하위 메뉴, 표 넣기만 둬요(표 안에서는 맨 위에 표 항목). 붉은 밑줄 검사는 그대로이고, 고치기·대치·말하기·서비스는 메뉴 막대 › 편집에서만 돼요.
- **날짜 고르기의 공휴일:** 지금 달력에 불러온 범위의 공휴일만 빨강이에요. 그 밖의 달로 넘기면 일요일만 빨강이에요.
- **위젯 미구현(7단계):** `Widgets/SimplifyWidgets.swift`는 아직 자리표시예요. `.containerBackground(.background)`, 시스템 serif 44, `.caption`을 써서 `widgetSurface()` · `DateOval` · `big-date`를 쓰지 않아요.
- **투명도:** 설정의 어두운 막(`opacity-scrim`)과 상자 그림자, 주 버튼 hover, 다른 달 일정은 `tokens.json`의 `opacity` 단계(`Metrics.opacity*`)를 써요. 다만 바탕색은 토큰이 아닌 `Color.black`이에요(막은 테마와 상관없이 검정이라서요).
- **패널 시각 자리:** 하루 탭은 시각이 왼쪽, 한 주 탭은 날짜별로 묶어서 시각이 오른쪽이에요. 월 칸은 좁아서 24시간제(`14:00`), 패널은 `오후 2:00`이에요.
- **색 패턴 옵션(8단계):** 설정 › 일반 › 모양의 "색과 함께 패턴도 표시"(기본 꺼짐)는 일정 표식·종일 띠·주 보기 일정 칸·위젯에 모양을 그려요. 패널의 하루 띠(`DayStrip`)와 할 일 줄의 색 라벨은 아직 색만이에요(할 일 메뉴의 색 견본은 모양을 따라요). 메뉴 견본도 이제 `Mark` 한 곳에서 그려요.
- **색상 휠 색:** 팔레트 밖의 색은 대비를 보장하지 않아요(흑연 테마, 노랑 계열). 띠 바탕은 그 색을 종이에 20% 섞어 만들어요. 색상 휠은 시스템 `NSColorPanel`이라 잉크 장부 모양이 아니에요.
- **로그인 항목:** 설정 › 일반 › 시작의 허락 안내는 글자만 있고, 시스템 설정을 여는 버튼은 없어요.
