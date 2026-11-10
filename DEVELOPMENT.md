# 개발

## 시작하기

```bash
brew install xcodegen
xcodegen generate
open Simplify.xcodeproj
```

`Simplify.xcodeproj`는 `project.yml`에서 만들어지므로 커밋하지 않아요. 타깃이나 설정은 `project.yml`에서 바꾼 뒤 `xcodegen generate`를 다시 실행해요.

위젯과 App Group은 서명이 필요해요. Xcode › Settings › Accounts에 Apple ID가 있어야 하고, `project.yml`의 `DEVELOPMENT_TEAM`에는 개인 팀 ID가 들어 있어요. 다른 팀으로 빌드할 때만 바꿔요.

Google 캘린더를 쓰려면 `Config/Secrets.example.xcconfig`를 `Config/Secrets.xcconfig`로 복사하고 OAuth 클라이언트 ID를 넣어요. 이 파일은 git에 올라가지 않아요.

## 설치

```bash
scripts/install.sh
```

Release로 빌드해 `/Applications/Simplify.app`에 설치하고 다시 열어요. 빌드 결과는 `build/release.noindex`에 두고 앱 목록 등록을 해제해서, Launchpad·Spotlight·위젯 목록에 Simplify가 하나만 보여요.

개발 빌드도 같은 이유로 `.noindex`로 끝나는 폴더에 만들어요(예: `-derivedDataPath build/dev.noindex`). 그 밖의 폴더에 만든 앱을 실행하면 macOS가 앱으로 등록해서 목록에 하나 더 생겨요.

Debug 빌드에는 위젯을 넣지 않아요. 위젯이 들어 있는 개발 빌드를 실행하면 같은 번들 ID라서 설치된 앱의 위젯을 가로채고, 바탕화면에 놓아 둔 위젯이 사라져요. 위젯 자체를 시험할 때만 `SIMPLIFY_DEBUG_WIDGETS=YES`를 붙여 빌드하고, 끝나면 `scripts/install.sh`로 다시 설치해요.

## 구조

| 경로 | 내용 |
| --- | --- |
| `Apps/macOS` | 메인 앱 (SwiftUI, macOS 26+) |
| `Widgets` | WidgetKit 확장 |
| `Packages/SimplifyKit` | 앱·위젯·나중의 iOS 앱이 함께 쓰는 코드 |
| `design` | 디자인 토큰(`tokens.json`)과 앱 아이콘 원본 |

제품 방향과 원칙은 [PRODUCT.md](PRODUCT.md), 디자인 기준은 [DESIGN.md](DESIGN.md)에 있어요.

## 테스트

```bash
swift test --package-path Packages/SimplifyKit
```
