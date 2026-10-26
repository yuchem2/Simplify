import AuthenticationServices
import SwiftUI
import SimplifyKit

/// Settings as a drawn panel over the main window: a menu on the left (계정 · 캘린더 · 일반),
/// the chosen page on the right. Esc, × or a click outside closes it.
struct SettingsModal: View {
    let model: AppModel
    let calendars: CalendarController
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var page: Page = .accounts
    /// The account kind whose connect page is open, before anything has started.
    @State private var intro: CalendarProviderKind?
    @State private var appleID = ""
    @State private var appPassword = ""
    /// Reconnecting a known iCloud account: its Apple ID stays as it is.
    @State private var reconnectingAppleID: String?
    @State private var confirming: CalendarController.Account?
    @FocusState private var focused: Bool
    @FocusState private var focusedField: FormFieldID?

    enum FormFieldID { case appleID, password }

    /// `intro` opens straight on an account kind's connect page (the snapshot uses it).
    init(model: AppModel, calendars: CalendarController, intro: CalendarProviderKind? = nil) {
        self.model = model
        self.calendars = calendars
        _intro = State(initialValue: intro)
    }

    enum Page { case accounts, calendars, general }

    var body: some View {
        ZStack {
            // Dims the month behind; a little darker on the black wall so the panel still stands out.
            Color.black.opacity(colorScheme == .dark ? 0.6 : 0.38)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                HStack {
                    Text("설정").font(.display(22)).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(DrawnButtonStyle())
                        .accessibilityLabel("닫기")
                }
                .padding(.leading, 24)
                .padding(.trailing, 20)
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(.ink).frame(height: Metrics.line).padding(.horizontal, Metrics.mouldingInset) }

                HStack(spacing: 0) {
                    sidebar
                    Rectangle().fill(.ink).frame(width: Metrics.line).padding(.bottom, Metrics.mouldingInset)
                    ScrollArea {
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 18)
                    }
                }
            }
            .frame(width: 760, height: 500)
            .mouldedFrame(shadow: modalShadow)
            .overlay { if let account = confirming { confirmDisconnect(account) } }
            .accessibilityAddTraits(.isModal)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand {
            if confirming != nil { confirming = nil } else { close() }
        }
    }

    /// The usual shade would read as a light edge on the dimmed window, so the modal casts a dark one.
    private var modalShadow: Color { colorScheme == .dark ? .black : .black.opacity(0.45) }

    private func close() {
        guard calendars.addState != .signingIn else { return }
        calendars.resetAddState()
        closeIntro()
        model.isSettingsOpen = false
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            sideItem("계정", icon: "person", page: .accounts)
            sideItem("캘린더", icon: "calendar", page: .calendars)
            sideItem("일반", icon: "gearshape", page: .general)
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .frame(width: 180)
    }

    private func sideItem(_ title: String, icon: String, page target: Page) -> some View {
        let isOn = page == target
        return Button { page = target } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Color.ink : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: - Pages

    @ViewBuilder private var content: some View {
        if intro != nil || calendars.addState != .idle {
            addFlow
        } else {
            switch page {
            case .accounts: accountsPage
            case .calendars: calendarsPage
            case .general: generalPage
            }
        }
    }

    private var generalPage: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 14) {
            SectionRule("달력")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("칸 안 일정 글자 크기").font(.system(size: 14))
                    Text("작게 고를수록 한 칸에 일정이 더 많이, 제목이 더 길게 보여요.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.inkSoft)
                }
                Spacer()
                SegmentedTabs(AppModel.CellTextSize.allCases.map { ($0, $0.label) }, selection: $model.cellTextSize)
            }
            HStack(spacing: 6) {
                Mark(Palette.blue.ink, size: model.cellTextSize.markSize)
                Text("주간 스탠드업 · 디자인 리뷰 · 필라테스")
                    .font(.system(size: model.cellTextSize.points))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
            .accessibilityLabel("미리 보기")

            SectionRule("미리알림").padding(.top, 8)
            Toggle(isOn: Binding(get: { calendars.showsCompletedReminders }, set: { calendars.showsCompletedReminders = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("완료된 미리알림 보기").font(.system(size: 14))
                    Text("끄면 완료한 미리알림은 달력에서 빠져요. 켜면 줄을 그어 보여 줘요.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.inkSoft)
                }
            }
            .toggleStyle(DrawnCheckboxStyle())
        }
    }

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionRule("연결된 계정")
            if calendars.accounts.isEmpty {
                Text("아직 연결한 계정이 없어요. Google·iCloud 계정이나 이 Mac의 미리알림을 추가하면 그 일정이 달력에 보여요.")
                    .font(.system(size: 13))
                    .foregroundStyle(.inkSoft)
                    .padding(.vertical, 8)
            }
            ForEach(calendars.accounts) { account in
                accountRow(account)
                if account.id != calendars.accounts.last?.id { Rectangle().fill(.ink).frame(height: Metrics.line) }
            }
            HStack {
                Text("로그인 정보는 이 Mac의 키체인에만 저장해요.").font(.system(size: 12)).foregroundStyle(.inkSoft)
                Spacer()
                Menu {
                    Button("Google") { intro = .google }
                    Button("iCloud") { openICloudForm(appleID: nil) }
                    Button("미리알림 (이 Mac)") { intro = .reminders }
                        .disabled(calendars.accounts.contains { $0.provider == .reminders })
                } label: {
                    Label("계정 추가", systemImage: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(DrawnButtonStyle())
                .fixedSize()
            }
            .padding(.top, 4)
        }
    }

    private func accountRow(_ account: CalendarController.Account) -> some View {
        HStack(spacing: 12) {
            ProviderIcon(kind: account.provider)
                .frame(width: 32, height: 32)
                .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(account.email).font(.system(size: 14))
                HStack(spacing: 8) {
                    if account.status == .needsReauth {
                        Tag(text: "다시 연결 필요", color: .holiday)
                        Text(calendars.problems[account.id] ?? "로그인이 만료됐어요").font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft)
                    } else if let problem = calendars.problems[account.id] {
                        Tag(text: "동기화 실패", color: .holiday)
                        Text(problem).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft)
                    } else {
                        Tag(text: account.provider.label, color: .inkSoft)
                        Text("\(account.provider == .reminders ? "목록" : "캘린더") \(account.calendarCount)개 · \(SyncStatusView.syncedText(account.lastSyncedAt))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.inkSoft)
                    }
                }
            }
            Spacer()
            if account.status == .needsReauth {
                Button("다시 연결") { reconnect(account) }
                .buttonStyle(DrawnButtonStyle(.primary))
            }
            Button("연결 해제") { confirming = account }.buttonStyle(DrawnButtonStyle(.text))
        }
        .padding(.vertical, 8)
    }

    private var calendarsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            if calendars.accounts.isEmpty {
                Text("연결한 계정이 없어요. 계정 메뉴에서 계정이나 미리알림을 추가해 주세요.")
                    .font(.system(size: 13))
                    .foregroundStyle(.inkSoft)
            }
            ForEach(calendars.sourcesByAccount, id: \.0.id) { account, sources in
                VStack(alignment: .leading, spacing: 4) {
                    SectionRule(account.email) {
                        if account.status == .needsReauth { Tag(text: "다시 연결 필요", color: .holiday) }
                        else { Text(account.provider.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft) }
                    }
                    ForEach(sources) { source in
                        HStack(spacing: 10) {
                            Toggle(isOn: Binding(get: { source.isVisible }, set: { calendars.setVisible(source.id, $0) })) {
                                HStack(spacing: 10) {
                                    if source.isReminderList { ReminderMark(source.palette.ink) } else { Mark(source.palette.ink) }
                                    Text(source.name)
                                        .font(.system(size: 14))
                                        .foregroundStyle(source.isVisible ? Color.ink : Color.inkSoft)
                                }
                            }
                            .toggleStyle(DrawnCheckboxStyle())
                            .accessibilityLabel("\(source.name) 보이기")
                            Spacer()
                            if source.isHoliday { Tag(text: "공휴일", color: .inkSoft) }
                            if source.isReadOnly { Tag(text: "읽기 전용", color: .inkSoft) }
                            else { Text(source.palette.name).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft) }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            if calendars.accounts.contains(where: { $0.status == .needsReauth }) {
                Text("다시 연결하기 전까지는 마지막으로 맞춘 일정을 그대로 보여 줘요.")
                    .font(.system(size: 12))
                    .foregroundStyle(.inkSoft)
            }
        }
    }

    // MARK: - Adding an account

    /// The kind of account the add pages are about.
    private var addingKind: CalendarProviderKind { intro ?? calendars.addingKind }

    @ViewBuilder private var addFlow: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch calendars.addState {
            case .idle:
                switch addingKind {
                case .google: googleIntro
                case .icloud: iCloudForm
                case .reminders: remindersIntro
                }
            case .signingIn:
                Text(addingKind.connectTitle).font(.display(20))
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    switch addingKind {
                    case .google: Text("Google 창에서 로그인해 주세요.")
                    case .icloud: Text("iCloud에 연결하는 중이에요.")
                    case .reminders: Text("허락을 묻는 창이 뜨면 \"허용\"을 눌러 주세요.")
                    }
                }
            case .importing(let email):
                Text(email).font(.display(20))
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(addingKind == .reminders ? "미리알림 목록을 가져오는 중이에요. 창을 닫아도 계속 가져와요."
                                                  : "캘린더와 일정을 가져오는 중이에요. 창을 닫아도 계속 가져와요.")
                }
                HStack { Spacer(); Button("닫기") { calendars.resetAddState() }.buttonStyle(DrawnButtonStyle()) }
            case .done(let email, let count):
                Text(email).font(.display(20))
                Text(addingKind == .reminders
                     ? "미리알림 목록 \(count)개를 가져왔어요. 마감일이 있는 미리알림이 그날 달력에 보여요."
                     : "캘린더 \(count)개를 가져왔어요. 캘린더 메뉴에서 보일 캘린더를 고를 수 있어요.")
                HStack {
                    Spacer()
                    Button("캘린더 보기") { calendars.resetAddState(); page = .calendars }.buttonStyle(DrawnButtonStyle())
                    Button("완료") { calendars.resetAddState() }.buttonStyle(DrawnButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text("연결하지 못했어요").font(.display(20))
                Text(message)
                HStack {
                    Spacer()
                    if addingKind == .reminders {
                        Button("시스템 설정 열기") {
                            openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                        }
                        .buttonStyle(DrawnButtonStyle(.text))
                    }
                    Button("닫기") { calendars.resetAddState() }.buttonStyle(DrawnButtonStyle())
                    Button("다시 시도") { retry() }.buttonStyle(DrawnButtonStyle(.primary))
                }
            }
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var googleIntro: some View {
        Text("Google 계정 연결").font(.display(20))
        Text("Google 캘린더 일정을 이 Mac으로 가져와요. 로그인은 Google 창에서 하고, Simplify는 암호를 보지 않아요.")
        Text("처음 로그인할 때 \"확인되지 않은 앱\" 경고가 나오면 고급 › Simplify(으)로 이동을 눌러요. 개인용으로 만든 앱이라 Google 검수를 받지 않았어요.")
            .foregroundStyle(.inkSoft)
        HStack {
            Spacer()
            Button("취소") { closeIntro() }.buttonStyle(DrawnButtonStyle())
            Button("Google로 계속") {
                closeIntro()
                Task { await calendars.addGoogleAccount(authenticate: authenticate) }
            }
            .buttonStyle(DrawnButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder private var iCloudForm: some View {
        Text(reconnectingAppleID == nil ? "iCloud 계정 연결" : "iCloud 다시 연결").font(.display(20))
        Text("iCloud 캘린더 일정을 이 Mac으로 가져와요. Apple ID 암호 대신, 이 앱에만 쓰는 앱 전용 암호로 연결해요.")
        VStack(alignment: .leading, spacing: 4) {
            Text("앱 전용 암호 만들기").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Text("1. account.apple.com에 로그인해요.")
                Button("열기") { openURL(URL(string: "https://account.apple.com/account/manage")!) }
                    .buttonStyle(DrawnButtonStyle(.text))
            }
            Text("2. 로그인 및 보안 › 앱 전용 암호에서 새 암호를 만들어요. 이름은 \"Simplify\"면 돼요.")
            Text("3. 나온 암호를 아래에 붙여 넣어요.")
            Text("이중 인증을 켠 계정에서만 앱 전용 암호를 만들 수 있어요.")
                .font(.system(size: 12))
                .foregroundStyle(.inkSoft)
                .padding(.top, 2)
        }
        FormField(label: "Apple ID", isEnabled: reconnectingAppleID == nil) {
            TextField("name@icloud.com", text: $appleID)
                .textContentType(.username)
                .focused($focusedField, equals: .appleID)
        }
        FormField(label: "앱 전용 암호") {
            SecureField("abcd-efgh-ijkl-mnop", text: $appPassword)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .onSubmit(connectICloud)
        }
        // Lands in the first empty field, so the password can be pasted and sent straight away.
        // A tick later than appearing, after the modal has taken focus itself.
        .task { focusedField = appleID.isEmpty ? .appleID : .password }
        HStack {
            Text("암호는 이 Mac의 키체인에만 저장해요.").font(.system(size: 12)).foregroundStyle(.inkSoft)
            Spacer()
            Button("취소") { closeIntro() }.buttonStyle(DrawnButtonStyle())
            Button("연결") { connectICloud() }
                .buttonStyle(DrawnButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnectICloud)
        }
    }

    @ViewBuilder private var remindersIntro: some View {
        Text("미리알림 가져오기").font(.display(20))
        Text("이 Mac의 미리알림 앱에 있는 목록을 가져와요. 마감일이 있는 미리알림이 그날 달력에 보이고, 미리알림 앱에서 바꾸면 바로 따라 바뀌어요.")
        Text("처음 한 번 \"Simplify가 미리알림에 접근하려고 합니다\" 창이 떠요. 마감일이 없는 미리알림은 달력에 보이지 않아요.")
            .foregroundStyle(.inkSoft)
        HStack {
            Spacer()
            Button("취소") { closeIntro() }.buttonStyle(DrawnButtonStyle())
            Button("계속") {
                closeIntro()
                Task { await calendars.addReminders() }
            }
            .buttonStyle(DrawnButtonStyle(.primary))
            .keyboardShortcut(.defaultAction)
        }
    }

    private var canConnectICloud: Bool {
        // Apple IDs can be phone numbers too; a wrong one is caught by iCloud's answer.
        !appleID.trimmingCharacters(in: .whitespaces).isEmpty && appPassword.filter { !$0.isWhitespace }.count >= 16
    }

    private func connectICloud() {
        guard canConnectICloud else { return }
        let id = appleID, password = appPassword
        closeIntro()
        Task { await calendars.addICloudAccount(appleID: id, password: password) }
    }

    private func openICloudForm(appleID known: String?) {
        appleID = known ?? ""
        appPassword = ""
        reconnectingAppleID = known
        intro = .icloud
    }

    /// Leaves the connect page; the password typed there is not kept.
    private func closeIntro() {
        intro = nil
        appPassword = ""
    }

    private func reconnect(_ account: CalendarController.Account) {
        switch account.provider {
        case .google: Task { await calendars.addGoogleAccount(loginHint: account.email, authenticate: authenticate) }
        case .icloud: openICloudForm(appleID: account.email)
        case .reminders: Task { await calendars.addReminders() }
        }
    }

    private func retry() {
        switch addingKind {
        case .google: Task { await calendars.retryAdd(authenticate: authenticate) }
        case .icloud:
            // Back to the form with the Apple ID still filled in, to type the password again.
            calendars.resetAddState()
            intro = .icloud
        case .reminders: Task { await calendars.addReminders() }
        }
    }

    private func authenticate(_ url: URL, _ scheme: String) async throws -> URL {
        try await webAuth.authenticate(using: url, callbackURLScheme: scheme, preferredBrowserSession: .shared)
    }

    // MARK: - Disconnect

    private func confirmDisconnect(_ account: CalendarController.Account) -> some View {
        ZStack {
            Color.black.opacity(0.2).onTapGesture { confirming = nil }
            VStack(alignment: .leading, spacing: 14) {
                Text("연결을 해제할까요?").font(.display(20))
                Text(disconnectMessage(account))
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("취소") { confirming = nil }.buttonStyle(DrawnButtonStyle())
                    Button("연결 해제") {
                        let id = account.id
                        confirming = nil
                        Task { await calendars.disconnect(id) }
                    }
                    .buttonStyle(DrawnButtonStyle(.primary))
                }
            }
            .padding(22)
            .frame(width: 420)
            .mouldedFrame(shadow: modalShadow)
            .accessibilityAddTraits(.isModal)
        }
    }
}

extension SettingsModal {
    private func disconnectMessage(_ account: CalendarController.Account) -> String {
        switch account.provider {
        case .google: "\(account.email)의 일정이 Simplify에서 사라지고, 이 Mac에 저장된 로그인 정보도 지워져요. Google 캘린더의 일정은 그대로 남아 있어요."
        case .icloud: "\(account.email)의 일정이 Simplify에서 사라지고, 이 Mac에 저장된 앱 전용 암호도 지워져요. iCloud 캘린더의 일정은 그대로 남아 있어요."
        case .reminders: "미리알림이 Simplify 달력에서 사라져요. 미리알림 앱의 항목은 그대로 남아 있어요."
        }
    }
}

extension CalendarProviderKind {
    /// The tag beside an account: `Google`, `iCloud`, `이 Mac`.
    var label: String {
        switch self {
        case .google: "Google"
        case .icloud: "iCloud"
        case .reminders: "이 Mac"
        }
    }

    var connectTitle: String {
        switch self {
        case .google: "Google 계정 연결"
        case .icloud: "iCloud 계정 연결"
        case .reminders: "미리알림 가져오기"
        }
    }
}

/// The square mark in front of an account: `G`, a cloud, a checklist.
private struct ProviderIcon: View {
    let kind: CalendarProviderKind

    var body: some View {
        switch kind {
        case .google: Text("G").font(.system(size: 14, weight: .semibold))
        case .icloud: Image(systemName: "icloud").font(.system(size: 14, weight: .medium))
        case .reminders: Image(systemName: "checklist").font(.system(size: 14, weight: .medium))
        }
    }
}

/// A labelled text field drawn as an outlined box; a locked one reads as plain shaded text.
private struct FormField<Field: View>: View {
    let label: String
    var isEnabled = true
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft)
            field
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(isEnabled ? Color.ink : Color.inkSoft)
                .disabled(!isEnabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isEnabled ? Color.paper : Color.shadeSoft)
                .overlay(Rectangle().strokeBorder(isEnabled ? Color.ink : Color.inkFaint, lineWidth: Metrics.line))
        }
    }
}

/// A small outlined label: `Google`, `읽기 전용`, `다시 연결 필요`.
struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(Rectangle().strokeBorder(color, lineWidth: Metrics.line))
    }
}

/// The sync state in the toolbar, beside 새 일정. Quiet when fine; red and clickable when an
/// account needs signing in again.
struct SyncStatusView: View {
    let calendars: CalendarController
    let openSettings: () -> Void

    var body: some View {
        switch calendars.status {
        case .noAccounts:
            Button(action: openSettings) { Label("캘린더 연결", systemImage: "plus") }
                .buttonStyle(DrawnButtonStyle())
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("맞추는 중…")
            }
            .modifier(StatusText())
        case .upToDate(let last):
            Button(action: openSettings) {
                Label("계정 \(calendars.accounts.count)개 · \(Self.syncedText(last))", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.plain)
            .modifier(StatusText())
        case .needsReauth(let email):
            Button(action: openSettings) {
                Label("\(email) 다시 연결 필요", systemImage: "exclamationmark.triangle")
                    .underline()
            }
            .buttonStyle(.plain)
            .modifier(StatusText(color: .holiday))
        case .offline(let last):
            Text("오프라인 · \(Self.syncedText(last))").modifier(StatusText())
        case .failed(let email):
            Button(action: openSettings) {
                Label("\(email) 동기화 실패", systemImage: "exclamationmark.triangle").underline()
            }
            .buttonStyle(.plain)
            .modifier(StatusText(color: .holiday))
        }
    }

    /// `방금 맞춤` within a minute, otherwise `10:42에 맞춤`.
    static func syncedText(_ date: Date?) -> String {
        guard let date else { return "아직 맞추지 않음" }
        if Date.now.timeIntervalSince(date) < 60 { return "방금 맞춤" }
        return date.formatted(.dateTime.hour().minute().locale(Locale(identifier: "ko_KR"))) + "에 맞춤"
    }

    private struct StatusText: ViewModifier {
        var color: Color = .inkSoft
        func body(content: Content) -> some View {
            content.font(.system(size: 11, weight: .medium)).foregroundStyle(color)
        }
    }
}
