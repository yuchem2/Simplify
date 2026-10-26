# Simplify

macOS 캘린더 + 다이어리 앱. Google·iCloud 캘린더, 하루·한 주·한 달 메모, 할 일, 위젯.

## 시작하기

```bash
brew install xcodegen
xcodegen generate
open Simplify.xcodeproj
```

`Simplify.xcodeproj`는 `project.yml`에서 만들어지므로 커밋하지 않아요. 타깃이나 설정은 `project.yml`에서 바꾼 뒤 `xcodegen generate`를 다시 실행해요.

위젯과 App Group은 서명이 필요해요. Xcode › Settings › Accounts에 Apple ID가 있어야 하고, `project.yml`의 `DEVELOPMENT_TEAM`에는 개인 팀 ID가 들어 있어요. 다른 팀으로 빌드할 때만 바꿔요.

## 구조

| 경로 | 내용 |
| --- | --- |
| `Apps/macOS` | 메인 앱 (SwiftUI, macOS 26+) |
| `Widgets` | WidgetKit 확장 |
| `Packages/SimplifyKit` | 앱·위젯·나중의 iOS 앱이 함께 쓰는 코드 |

## 테스트

```bash
swift test --package-path Packages/SimplifyKit
```

디자인 시안과 디자인 시스템: `~/Dev/personal/mockup/simplify/`
