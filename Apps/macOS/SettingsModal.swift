import AuthenticationServices
import ServiceManagement
import SwiftUI
import SimplifyKit

/// Settings as a box floating over the dimmed window: a menu on the left (계정 · 캘린더 · 일반), the
/// chosen page on the right. ×, esc or a click outside the box closes it.
struct SettingsModal: View {
    let model: AppModel
    let calendars: CalendarController
    @Environment(\.webAuthenticationSession) private var webAuth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var page: Page = .accounts
    @State private var isCalendarMenuOpen = false
    @State private var isAddMenuOpen = false
    /// The account kind whose connect page is open, before anything has started.
    @State private var intro: CalendarProviderKind?
    @State private var appleID = ""
    @State private var appPassword = ""
    /// Reconnecting a known iCloud account: its Apple ID stays as it is.
    @State private var reconnectingAppleID: String?
    @State private var confirming: CalendarController.Account?
    /// Accounts whose calendars are folded away on the calendars page.
    @State private var folded: Set<CalendarController.Account.ID> = []
    @FocusState private var focusedField: FormFieldID?

    enum FormFieldID { case appleID, password }

    /// `intro` opens straight on an account kind's connect page, `page` on another menu (the snapshot uses both).
    init(model: AppModel, calendars: CalendarController, intro: CalendarProviderKind? = nil, page: Page = .accounts) {
        self.model = model
        self.calendars = calendars
        _intro = State(initialValue: intro)
        _page = State(initialValue: page)
    }

    enum Page { case accounts, calendars, general }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // The whole window dims, the title bar too; a click outside closes settings.
                Color.black.opacity(Metrics.opacityScrim)
                    .ignoresSafeArea()
                    .onTapGesture { if confirming == nil { close() } }
                    .accessibilityHidden(true)
                panel
                    .frame(width: min(geo.size.width - Self.margin * 2, Self.size.width),
                           height: min(geo.size.height - Self.margin * 2, Self.size.height))
                    .floatingFrame(shadow: modalShadow)
                    .accessibilityAddTraits(.isModal)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .overlay { if let account = confirming { confirmDisconnect(account) } }
        // A colour wheel left open would go on recolouring a calendar nobody is looking at.
        .onDisappear { ColorWheel.shared.release() }
    }

    /// The largest the settings box grows, and the least room it leaves around itself.
    static let size = CGSize(width: 760, height: 540)
    static let margin: CGFloat = 32

    private var panel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("설정").textStyle(.subheading).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(DrawnButtonStyle(.icon))
                    // esc: the box itself takes no focus, or every button in it would read as focused.
                    .keyboardShortcut(confirming == nil ? .cancelAction : nil)
                    // Signing in has to finish or fail first.
                    .disabled(calendars.addState == .signingIn)
                    .help(calendars.addState == .signingIn ? "로그인이 끝나면 닫을 수 있어요" : "설정 닫기 (esc)")
                    .accessibilityLabel("설정 닫기")
            }
            .padding(.leading, Metrics.spaceXxl)
            .padding(.trailing, Metrics.spaceL)
            .padding(.vertical, Metrics.spaceL)
            Rectangle().fill(.shade).frame(height: Metrics.line)

            HStack(spacing: 0) {
                sidebar
                // The same spine as between the calendar and the panel.
                Rectangle().fill(.ink).frame(width: Metrics.lineSpine)
                ScrollArea {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Metrics.spaceXxxl)
                        .padding(.vertical, Metrics.spaceXxl)
                }
            }
        }
    }

    /// The settings box and its confirmation sit over the dimmed window, where the usual shadow would not read.
    private var modalShadow: Color { colorScheme == .dark ? .black : .black.opacity(Metrics.opacityModalShadow) }

    private func close() {
        guard calendars.addState != .signingIn else { return }
        calendars.resetAddState()
        closeIntro()
        model.isSettingsOpen = false
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
            sideItem("계정", icon: "person", page: .accounts)
            sideItem("캘린더", icon: "calendar", page: .calendars)
            sideItem("일반", icon: "gearshape", page: .general)
            Spacer()
        }
        .padding(Metrics.spaceL)
        .frame(width: 184)
    }

    private func sideItem(_ title: String, icon: String, page target: Page) -> some View {
        let isOn = page == target
        return Button { page = target } label: {
            Label(title, systemImage: icon)
                .textStyle(.body)
                .fontWeight(isOn ? .semibold : .regular)
                .foregroundStyle(isOn ? Color.onInk : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.spaceM)
                .padding(.vertical, Metrics.spaceS)
                .selectableRow(chosen: isOn, inset: 0)
        }
        .buttonStyle(FocusOnlyStyle())
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
        return VStack(alignment: .leading, spacing: Metrics.spaceL) {
            SectionRule("모양")
            settingRow("테마", note: "시스템을 고르면 Mac의 밝은 모드·어두운 모드를 따라가요.") {
                SegmentedTabs(AppModel.Theme.allCases.map { ($0, $0.label) }, selection: $model.theme)
                    .accessibilityLabel("테마")
            }
            HStack(spacing: Metrics.spaceL) {
                Toggle(isOn: $model.showsPatterns) {
                    labelled("색과 함께 패턴도 표시", note: "캘린더마다 모양을 함께 그려요. 모양은 왼쪽 캘린더에서 캘린더마다 골라요.")
                }
                .toggleStyle(DrawnCheckboxStyle())
                Spacer()
                // What the marks become, whether or not it is on.
                HStack(spacing: Metrics.spaceS) {
                    ForEach([Palette.blue, .orange, .green, .pink], id: \.self) { Mark($0.ink, shape: $0.markShape) }
                }
                .environment(\.showsPalettePatterns, true)
                .accessibilityHidden(true)
            }

            SectionRule("달력").padding(.top, Metrics.spaceM)
            settingRow("주 시작 요일", note: "달력과 한 주 메모가 이 요일부터 시작해요.") {
                SegmentedTabs(AppModel.WeekStart.allCases.map { ($0, $0.label) }, selection: $model.weekStart)
                    .accessibilityLabel("주 시작 요일")
            }
            settingRow("칸 안 일정 글자 크기", note: "작게 고를수록 한 칸에 일정이 더 많이, 제목이 더 길게 보여요.") {
                SegmentedTabs(AppModel.CellTextSize.allCases.map { ($0, $0.label) }, selection: $model.cellTextSize)
            }
            HStack(spacing: Metrics.spaceS) {
                Mark(Palette.blue.ink, size: model.cellTextSize.markSize, shape: Palette.blue.markShape)
                // The size the day cells use, so the preview reads exactly like a cell.
                Text(model.showsCellTimes ? "09:30 주간 스탠드업 · 14:00 디자인 리뷰" : "주간 스탠드업 · 디자인 리뷰 · 필라테스")
                    .font(.system(size: model.cellTextSize.points))
            }
            .padding(.horizontal, Metrics.spaceL)
            .padding(.vertical, Metrics.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A strip of the weekend face, so it reads as a sample of the grid rather than a control.
            .background(.raised)
            .accessibilityLabel("미리 보기")
            Toggle(isOn: $model.showsCellTimes) {
                Text("달력 칸에 시작 시각 보기").textStyle(.item)
            }
            .toggleStyle(DrawnCheckboxStyle())

            SectionRule("새 일정").padding(.top, Metrics.spaceM)
            settingRow("기본 캘린더", note: "새 일정을 만들 때 처음 골라져 있는 캘린더예요.") {
                newEventCalendarMenu
            }

            SectionRule("미리알림").padding(.top, Metrics.spaceM)
            Toggle(isOn: Binding(get: { calendars.showsCompletedReminders }, set: { calendars.showsCompletedReminders = $0 })) {
                labelled("완료된 미리알림 보기", note: "끄면 완료한 미리알림은 달력에서 빠져요. 켜면 줄을 그어 보여 줘요.")
            }
            .toggleStyle(DrawnCheckboxStyle())

            SectionRule("메모").padding(.top, Metrics.spaceM)
            NotesMirrorRow()

            SectionRule("기기").padding(.top, Metrics.spaceM)
            DeviceSyncRow()

            SectionRule("시작").padding(.top, Metrics.spaceM)
            LoginItemRow()
        }
    }

    /// A setting's name and what it does, with its control on the right.
    private func settingRow(_ title: String, note: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: Metrics.spaceL) {
            labelled(title, note: note)
            Spacer()
            control()
        }
    }

    private func labelled(_ title: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
            Text(title).textStyle(.item)
            Text(note)
                .textStyle(.small)
                .foregroundStyle(.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 마지막으로 쓴 캘린더, or one calendar that can be written to. A chosen calendar that turned
    /// read-only or went away reads as the last one used, which is what new events then start in.
    private var newEventCalendarMenu: some View {
        let chosen = calendars.preferredNewEventSource.flatMap { calendars.isWritable($0) ? calendars.sources[$0] : nil }
        let shown = chosen ?? calendars.defaultSourceForNewEvent.flatMap { calendars.sources[$0] }
        return Button { isCalendarMenuOpen = true } label: {
            MenuLabel(text: chosen?.name ?? "마지막으로 쓴 캘린더", mark: shown?.look, isOpen: isCalendarMenuOpen)
        }
        .buttonStyle(FocusOnlyStyle())
        .fixedSize()
        .inkMenu(isPresented: $isCalendarMenuOpen) {
            [.item("마지막으로 쓴 캘린더", checked: chosen == nil) { calendars.preferredNewEventSource = nil }]
                + calendars.writableSources.flatMap { account, sources in
                    [InkMenuEntry.divider, .section("\(account.provider.label) · \(account.email)")]
                        + sources.map { source in
                            .item(source.name, swatch: InkMenuSwatch(source.look.ink, shape: source.look.shape), checked: chosen?.id == source.id) {
                                calendars.preferredNewEventSource = source.id
                            }
                        }
                }
        }
        .disabled(calendars.writableSources.isEmpty)
        .help(calendars.writableSources.isEmpty ? "일정을 쓸 수 있는 캘린더가 없어요" : "")
        .accessibilityLabel("기본 캘린더")
    }

    private var accountsPage: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceL) {
            SectionRule("연결된 계정")
            if calendars.accounts.isEmpty {
                Text("아직 연결한 계정이 없어요. Google·iCloud 계정이나 이 Mac의 미리알림을 추가하면 그 일정이 달력에 보여요.")
                    .textStyle(.body)
                    .foregroundStyle(.inkSoft)
                    .padding(.vertical, Metrics.spaceM)
            }
            ForEach(calendars.accounts) { account in
                accountRow(account)
                if account.id != calendars.accounts.last?.id { Rectangle().fill(.shade).frame(height: Metrics.line) }
            }
            HStack {
                Text("로그인 정보는 이 Mac의 키체인에만 저장해요.").textStyle(.small).foregroundStyle(.inkSoft)
                Spacer()
                Button { isAddMenuOpen = true } label: {
                    Label("계정 추가", systemImage: "plus")
                }
                .buttonStyle(DrawnButtonStyle(active: isAddMenuOpen))
                .fixedSize()
                .inkMenu(isPresented: $isAddMenuOpen) {
                    [.item("Google") { intro = .google },
                     .item("iCloud") { openICloudForm(appleID: nil) },
                     .item("미리알림 (이 Mac)", isEnabled: !calendars.accounts.contains { $0.provider == .reminders }) { intro = .reminders }]
                }
            }
            .padding(.top, Metrics.spaceXs)
        }
    }

    private func accountRow(_ account: CalendarController.Account) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceL) {
            ProviderIcon(kind: account.provider)
                .foregroundStyle(.inkSoft)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                Text(account.email).textStyle(.item)
                HStack(spacing: Metrics.spaceM) {
                    if account.status == .needsReauth {
                        ErrorTag("다시 연결 필요")
                        Text(calendars.problems[account.id] ?? "로그인이 만료됐어요").textStyle(.small).foregroundStyle(.inkSoft)
                    } else if let problem = calendars.problems[account.id] {
                        ErrorTag("동기화 실패")
                        Text(problem).textStyle(.small).foregroundStyle(.inkSoft)
                    } else {
                        Text("\(account.provider.label) · \(account.provider == .reminders ? "목록" : "캘린더") \(account.calendarCount)개 · \(SyncStatusView.syncedText(account.lastSyncedAt))")
                            .textStyle(.meta)
                            .foregroundStyle(.inkSoft)
                    }
                }
            }
            Spacer()
            if account.status == .needsReauth {
                Button("다시 연결") { reconnect(account) }
                .buttonStyle(DrawnButtonStyle(.primary))
            }
            Button("연결 해제") { confirming = account }.buttonStyle(DrawnButtonStyle(.dangerText))
        }
        .padding(.vertical, Metrics.spaceM)
    }

    private var calendarsPage: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXxl) {
            if calendars.accounts.isEmpty {
                Text("연결한 계정이 없어요. 계정 메뉴에서 계정이나 미리알림을 추가해 주세요.")
                    .textStyle(.body)
                    .foregroundStyle(.inkSoft)
            }
            ForEach(calendars.sourcesByAccount, id: \.0.id) { account, sources in
                let isFolded = folded.contains(account.id)
                VStack(alignment: .leading, spacing: Metrics.spaceXs) {
                    // The account's name folds its calendars away.
                    Button {
                        withAnimation(.easeOut(duration: Metrics.motionQuick)) {
                            if isFolded { folded.remove(account.id) } else { folded.insert(account.id) }
                        }
                    } label: {
                        HStack(spacing: Metrics.spaceS) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.inkSoft)
                                .rotationEffect(.degrees(isFolded ? -90 : 0))
                            SectionRule(account.email) {
                                if account.status == .needsReauth { ErrorTag("다시 연결 필요") }
                                else {
                                    Text(isFolded ? "\(account.provider.label) · \(sources.allSatisfy(\.isReminderList) ? "목록" : "캘린더") \(sources.count)개" : account.provider.label)
                                        .textStyle(.meta).foregroundStyle(.inkSoft)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FocusOnlyStyle())
                    .help(isFolded ? "펼치기" : "접기")
                    .accessibilityLabel(account.status == .needsReauth ? "\(account.email), 다시 연결 필요" : account.email)
                    .accessibilityValue(isFolded ? "접힘" : "펼쳐짐")
                    if !isFolded { ForEach(sources) { source in
                        HStack(spacing: Metrics.spaceM) {
                            Toggle(isOn: Binding(get: { source.isVisible }, set: { calendars.setVisible(source.id, $0) })) {
                                HStack(spacing: Metrics.spaceM) {
                                    if source.isReminderList { ReminderMark(source.look.ink) } else { Mark(source.look.ink, shape: source.look.shape) }
                                    Text(source.name)
                                        .textStyle(.item)
                                        .foregroundStyle(source.isVisible ? Color.ink : Color.inkSoft)
                                }
                            }
                            .toggleStyle(DrawnCheckboxStyle())
                            .accessibilityLabel("\(source.name) 보이기")
                            Spacer()
                            if let note = sourceNote(source) { Text(note).textStyle(.meta).foregroundStyle(.inkSoft) }
                            // A holiday calendar stays red words; its look is not the person's to pick.
                            if !source.isHoliday { StyleButton(source: source, provider: account.provider, calendars: calendars) }
                        }
                        .padding(.vertical, Metrics.spaceXs)
                    } }
                }
            }
            if calendars.accounts.contains(where: { $0.status == .needsReauth }) {
                Text("다시 연결하기 전까지는 마지막으로 맞춘 일정을 그대로 보여 줘요.")
                    .textStyle(.small)
                    .foregroundStyle(.inkSoft)
            }
        }
    }

    /// `공휴일 · 읽기 전용`, `읽기 전용`, or nil; the colour button says the colour.
    private func sourceNote(_ source: CalendarController.Source) -> String? {
        var parts: [String] = []
        if source.isHoliday { parts.append("공휴일") }
        if source.isReadOnly { parts.append("읽기 전용") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Adding an account

    /// The kind of account the add pages are about.
    private var addingKind: CalendarProviderKind { intro ?? calendars.addingKind }

    @ViewBuilder private var addFlow: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceL) {
            switch calendars.addState {
            case .idle:
                switch addingKind {
                case .google: googleIntro
                case .icloud: iCloudForm
                case .reminders: remindersIntro
                }
            case .signingIn:
                Text(addingKind.connectTitle).textStyle(.subheading)
                HStack(spacing: Metrics.spaceM) {
                    ProgressView().controlSize(.small)
                    switch addingKind {
                    case .google: Text("Google 창에서 로그인해 주세요.")
                    case .icloud: Text("iCloud에 연결하는 중이에요.")
                    case .reminders: Text("허락을 묻는 창이 뜨면 \"허용\"을 눌러 주세요.")
                    }
                }
            case .importing(let email):
                Text(email).textStyle(.item).fontWeight(.semibold)
                HStack(spacing: Metrics.spaceM) {
                    ProgressView().controlSize(.small)
                    Text(addingKind == .reminders ? "미리알림 목록을 가져오는 중이에요. 창을 닫아도 계속 가져와요."
                                                  : "캘린더와 일정을 가져오는 중이에요. 창을 닫아도 계속 가져와요.")
                }
                HStack { Spacer(); Button("닫기") { calendars.resetAddState() }.buttonStyle(DrawnButtonStyle()) }
            case .done(let email, let count):
                Text(email).textStyle(.item).fontWeight(.semibold)
                Text(addingKind == .reminders
                     ? "미리알림 목록 \(count)개를 가져왔어요. 마감일이 있는 미리알림이 그날 달력에 보여요."
                     : "캘린더 \(count)개를 가져왔어요. 캘린더 메뉴에서 보일 캘린더를 고를 수 있어요.")
                HStack {
                    Spacer()
                    Button("캘린더 보기") { calendars.resetAddState(); page = .calendars }.buttonStyle(DrawnButtonStyle())
                    Button("완료") { calendars.resetAddState() }.buttonStyle(DrawnButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                }
            case .failed(let message):
                Text(addingKind.connectTitle).textStyle(.subheading)
                NoticeBar(message, title: "연결하지 못했어요", tone: .warning)
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
        .textStyle(.body)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var googleIntro: some View {
        Text("Google 계정 연결").textStyle(.subheading)
        Text("Google 캘린더 일정을 이 Mac으로 가져와요. 로그인은 Google 창에서 하고, Simplify는 암호를 보지 않아요.")
        Text("Google 창에서 계정을 고르고 캘린더 접근을 허용해 주세요. 한 번 연결하면 다시 로그인하라고 하지 않아요.")
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
        Text(reconnectingAppleID == nil ? "iCloud 계정 연결" : "iCloud 다시 연결").textStyle(.subheading)
        Text("iCloud 캘린더 일정을 이 Mac으로 가져와요. Apple ID 암호 대신, 이 앱에만 쓰는 앱 전용 암호로 연결해요.")
        VStack(alignment: .leading, spacing: Metrics.spaceXs) {
            Text("앱 전용 암호 만들기").textStyle(.body).fontWeight(.semibold)
            HStack(spacing: Metrics.spaceM) {
                Text("1. account.apple.com에 로그인해요.")
                Button("열기") { openURL(URL(string: "https://account.apple.com/account/manage")!) }
                    .buttonStyle(DrawnButtonStyle(.text))
            }
            Text("2. 로그인 및 보안 › 앱 전용 암호에서 새 암호를 만들어요. 이름은 \"Simplify\"면 돼요.")
            Text("3. 나온 암호를 아래에 붙여 넣어요.")
            Text("이중 인증을 켠 계정에서만 앱 전용 암호를 만들 수 있어요.")
                .textStyle(.small)
                .foregroundStyle(.inkSoft)
                .padding(.top, Metrics.spaceXxs)
        }
        FormField(label: "Apple ID", focused: focusedField == .appleID, isEnabled: reconnectingAppleID == nil) {
            TextField("name@icloud.com", text: $appleID)
                .textContentType(.username)
                .focused($focusedField, equals: .appleID)
        }
        FormField(label: "앱 전용 암호", focused: focusedField == .password) {
            SecureField("abcd-efgh-ijkl-mnop", text: $appPassword)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .onSubmit(connectICloud)
        }
        // Lands in the first empty field, so the password can be pasted and sent straight away.
        .task { focusedField = appleID.isEmpty ? .appleID : .password }
        HStack {
            Text("암호는 이 Mac의 키체인에만 저장해요.").textStyle(.small).foregroundStyle(.inkSoft)
            Spacer()
            Button("취소") { closeIntro() }.buttonStyle(DrawnButtonStyle())
            Button("연결") { connectICloud() }
                .buttonStyle(DrawnButtonStyle(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!canConnectICloud)
        }
    }

    @ViewBuilder private var remindersIntro: some View {
        Text("미리알림 가져오기").textStyle(.subheading)
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
            Color.black.opacity(Metrics.opacityScrim).ignoresSafeArea().onTapGesture { confirming = nil }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.spaceL) {
                Text("연결을 해제할까요?").textStyle(.subheading)
                Text(disconnectMessage(account))
                    .textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("취소") { confirming = nil }.buttonStyle(DrawnButtonStyle()).keyboardShortcut(.cancelAction)
                    Button("연결 해제") {
                        let id = account.id
                        confirming = nil
                        Task { await calendars.disconnect(id) }
                    }
                    .buttonStyle(DrawnButtonStyle(.danger))
                }
            }
            .padding(Metrics.spaceXxxl)
            .frame(width: 420)
            .floatingFrame(shadow: modalShadow)
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

/// How a calendar is drawn, as a small box: `파랑`, `자동 · 파랑` while the colour follows its
/// provider, and the shape after it once one is picked (`파랑 · 세모`). A click, or Space with the
/// keyboard, opens the colours and shapes under it.
private struct StyleButton: View {
    let source: CalendarController.Source
    let provider: CalendarProviderKind
    let calendars: CalendarController
    @State private var isOpen = false

    var body: some View {
        let label = Self.label(source)
        Button { isOpen = true } label: {
            HStack(spacing: Metrics.spaceS) {
                Text(label)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .textStyle(.meta)
            .foregroundStyle(isOpen ? Color.ink : Color.inkSoft)
            .padding(.leading, Metrics.spaceS)
            .padding(.trailing, Metrics.spaceXs)
            .padding(.vertical, Metrics.spaceXxs)
            .background(isOpen ? Color.rowActive : Color.clear)
            .overlay(Rectangle().strokeBorder(isOpen ? Color.ink : Color.shade, lineWidth: Metrics.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(FocusOnlyStyle())
        .fixedSize()
        .help("색과 모양 고르기")
        .accessibilityLabel("\(source.name) 색과 모양")
        .accessibilityValue(label)
        .anchoredPop(isPresented: $isOpen) {
            StylePop(sourceID: source.id, provider: provider, calendars: calendars) { isOpen = false }
        }
    }

    static func label(_ source: CalendarController.Source) -> String {
        var parts = source.style.hasColor ? [source.look.name] : ["자동", source.look.name]
        if let shape = source.style.shape { parts.append(shape.name) }
        return parts.joined(separator: " · ")
    }
}

/// A calendar's colour (자동, the nine palette colours, or any from the colour wheel) and the shape
/// its marks take with patterns on (자동, or one of nine). Picking keeps the pop open; the arrow keys
/// move the cursor through both, Return picks, Esc closes.
struct StylePop: View {
    let sourceID: String
    let provider: CalendarProviderKind
    let calendars: CalendarController
    let close: () -> Void
    /// Starts on the colour in use.
    @State private var cursor: Int
    @FocusState private var focused: Bool
    @Environment(\.showsPalettePatterns) private var showsPatterns
    @Environment(\.isRenderingSnapshot) private var isRenderingSnapshot

    /// One choice in the pop, in reading order.
    private enum Choice: Hashable {
        case autoColor, palette(Palette), wheel, autoShape, shape(MarkShape)
    }

    /// The cursor walks these rows: two of colours, the colour wheel, then two of shapes. Reminder
    /// lists keep their rings whatever the shape, so they get no shapes.
    private static func rows(shapes: Bool) -> [[Choice]] {
        let colors = [Choice.autoColor] + Palette.allCases.map(Choice.palette)
        let shapeChoices = [Choice.autoShape] + MarkShape.allCases.map(Choice.shape)
        let colorRows = [Array(colors[0..<5]), Array(colors[5...]), [Choice.wheel]]
        return shapes ? colorRows + [Array(shapeChoices[0..<5]), Array(shapeChoices[5...])] : colorRows
    }

    private static let columns = 5
    private static let swatch: CGFloat = 28
    private static let gridWidth = swatch * CGFloat(columns) + Metrics.spaceL * CGFloat(columns - 1)

    private var rows: [[Choice]] { Self.rows(shapes: calendars.sources[sourceID]?.isReminderList != true) }
    private var choices: [Choice] { rows.flatMap { $0 } }
    /// The column up and down keep to, across the one-wide colour wheel row.
    @State private var column = 0

    init(sourceID: String, provider: CalendarProviderKind, calendars: CalendarController, close: @escaping () -> Void) {
        self.sourceID = sourceID
        self.provider = provider
        self.calendars = calendars
        self.close = close
        let start = calendars.sources[sourceID].map(Self.chosenColor) ?? .autoColor
        let index = Self.rows(shapes: false).flatMap { $0 }.firstIndex(of: start) ?? 0
        _cursor = State(initialValue: index)
        _column = State(initialValue: index < 10 ? index % 5 : 0)
    }

    var body: some View {
        if let source = calendars.sources[sourceID] {
            content(source)
        }
    }

    private func content(_ source: CalendarController.Source) -> some View {
        VStack(alignment: .leading, spacing: Metrics.spaceM) {
            Text("개인 색").textStyle(.section)
            grid(Array(rows[0...1]), source: source)
            wheelRow(source)
            // Broken where the sentence breaks, not wherever the width runs out.
            Text("자동은 \(providerName) 색(\(source.autoPalette.name))에\n가장 가까운 색이에요.")
                .textStyle(.small)
                .foregroundStyle(.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if rows.count > 3 {
                Rectangle().fill(.shade).frame(height: Metrics.line).padding(.vertical, Metrics.spaceXs)
                Text("모양").textStyle(.section)
                grid(Array(rows[3...4]), source: source)
                Text(showsPatterns ? "자동은 색에 맞는 모양이에요." : "일반 › 모양의 패턴 표시를\n켜면 달력에 보여요.")
                    .textStyle(.small)
                    .foregroundStyle(.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Everything as wide as the swatch grid, so the 다른 색 row and the notes line up with it.
        .frame(width: Self.gridWidth, alignment: .leading)
        .padding(Metrics.spaceL)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            focused = true
            // The wheel left open for another calendar stops sending to it.
            ColorWheel.shared.release(unless: sourceID)
        }
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .onKeyPress(.upArrow) { jump(-1) }
        .onKeyPress(.downArrow) { jump(1) }
        .onKeyPress(.return) {
            pick(choices[cursor], source: source)
            return .handled
        }
        .onExitCommand(perform: close)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(source.name) 색과 모양")
    }

    private var providerName: String {
        switch provider {
        case .google: "Google"
        case .icloud: "iCloud"
        case .reminders: "미리알림"
        }
    }

    private static func chosenColor(_ source: CalendarController.Source) -> Choice {
        if source.style.hex != nil { return .wheel }
        return source.style.palette.map(Choice.palette) ?? .autoColor
    }

    private func chosenShape(_ source: CalendarController.Source) -> Choice {
        source.style.shape.map(Choice.shape) ?? .autoShape
    }

    // MARK: Keys

    private func position(of index: Int) -> (row: Int, column: Int) {
        var start = 0
        for (row, items) in rows.enumerated() {
            if index < start + items.count { return (row, index - start) }
            start += items.count
        }
        return (0, 0)
    }

    /// Left and right stay within a row.
    private func step(_ offset: Int) -> KeyPress.Result {
        let (row, at) = position(of: cursor)
        if rows[row].indices.contains(at + offset) {
            cursor += offset
            column = at + offset
        }
        return .handled
    }

    /// Up and down go to the row above or below, at the nearest column.
    private func jump(_ offset: Int) -> KeyPress.Result {
        let (row, _) = position(of: cursor)
        guard rows.indices.contains(row + offset) else { return .handled }
        let target = rows[row + offset]
        cursor = choices.firstIndex(of: target[min(column, target.count - 1)]) ?? cursor
        return .handled
    }

    // MARK: Picking

    private func pick(_ choice: Choice, source: CalendarController.Source) {
        var style = source.style
        switch choice {
        case .autoColor: style.palette = nil; style.hex = nil
        case .palette(let palette): style.palette = palette; style.hex = nil
        case .wheel:
            ColorWheel.shared.open(source.look.ink, for: sourceID) { hex in
                guard var style = calendars.sources[sourceID]?.style else { return }
                style.hex = hex
                calendars.setStyle(sourceID, style)
            }
            return
        case .autoShape: style.shape = nil
        case .shape(let shape): style.shape = shape
        }
        calendars.setStyle(sourceID, style)
    }

    private func isCursor(_ choice: Choice) -> Bool {
        (focused || isRenderingSnapshot) && choices.firstIndex(of: choice) == cursor
    }

    private func grid(_ rows: [[Choice]], source: CalendarController.Source) -> some View {
        Grid(horizontalSpacing: Metrics.spaceL, verticalSpacing: Metrics.spaceM) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { choice in swatch(choice, source: source) }
                }
            }
        }
        // Room for the chosen one's ring, which stands outside its swatch.
        .padding(.vertical, Metrics.spaceXs)
    }

    private func swatch(_ choice: Choice, source: CalendarController.Source) -> some View {
        let chosen = choice == Self.chosenColor(source) || choice == chosenShape(source)
        let name = name(of: choice)
        return Button { pick(choice, source: source) } label: {
            ZStack {
                switch choice {
                case .autoColor, .autoShape:
                    Rectangle().strokeBorder(Color.inkSoft, style: StrokeStyle(lineWidth: Metrics.line, dash: [2, 2]))
                    Text("자동").textStyle(.meta).fontWeight(.semibold).foregroundStyle(.inkSoft)
                case .palette(let palette):
                    Rectangle().fill(palette.ink)
                case .shape(let shape):
                    Rectangle().strokeBorder(.shade, lineWidth: Metrics.line)
                    // In the calendar's own colour, as its marks will show.
                    Mark(source.look.ink, size: 14, outlined: false, shape: shape)
                        .environment(\.showsPalettePatterns, true)
                case .wheel:
                    EmptyView()
                }
            }
            .frame(width: Self.swatch, height: Self.swatch)
            // The one in use stands in an ink square; the keys' cursor in the usual ring.
            .overlay { if chosen { Rectangle().strokeBorder(.ink, lineWidth: 2).padding(-4) } }
            .focusRing(isCursor(choice) && !chosen)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// 다른 색…, with the picked colour beside it once there is one.
    private func wheelRow(_ source: CalendarController.Source) -> some View {
        let chosen = Self.chosenColor(source) == .wheel
        return Button { pick(.wheel, source: source) } label: {
            HStack(spacing: Metrics.spaceS) {
                if chosen { Rectangle().fill(source.look.ink).frame(width: 12, height: 12) }
                Text(chosen ? "직접 고른 색 · 바꾸기…" : "다른 색…").textStyle(.small)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.spaceS)
            .frame(width: Self.gridWidth, height: 24)
            .overlay(Rectangle().strokeBorder(.shade, lineWidth: Metrics.line))
            // In use: the same ink square around it as a chosen swatch.
            .overlay { if chosen { Rectangle().strokeBorder(.ink, lineWidth: 2).padding(-4) } }
            .focusRing(isCursor(.wheel) && !chosen)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("색상 휠에서 고르기")
        .accessibilityLabel("다른 색")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func name(of choice: Choice) -> String {
        switch choice {
        case .autoColor: "자동 색"
        case .palette(let palette): palette.name
        case .wheel: "다른 색"
        case .autoShape: "자동 모양"
        case .shape(let shape): shape.name
        }
    }
}

/// The system colour wheel for one calendar at a time. It stays open beside settings and sends
/// every change, in sRGB, to whoever opened it last.
@MainActor
final class ColorWheel: NSObject {
    static let shared = ColorWheel()
    private var onChange: ((String) -> Void)?
    /// The calendar the wheel is sending to.
    private var owner: String?

    func open(_ current: Color, for owner: String, onChange: @escaping (String) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        // The starting colour goes in before the action, so opening alone changes nothing.
        panel.setAction(nil)
        panel.color = NSColor(current)
        self.onChange = onChange
        self.owner = owner
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.orderFront(nil)
    }

    /// Closes the wheel, unless it is sending to `keep`; nil closes it whatever it is for.
    func release(unless keep: String? = nil) {
        guard owner != nil, owner != keep else { return }
        onChange = nil
        owner = nil
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        guard let rgb = panel.color.usingColorSpace(.sRGB) else { return }
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        onChange?(String(format: "#%02x%02x%02x", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent)))
    }
}

/// 설정 › 일반 › 시작: Simplify among the Mac's login items. The state is macOS's, read whenever the
/// page opens, so a change made in 시스템 설정 shows here.
private struct LoginItemRow: View {
    @State private var status: SMAppService.Status = .notRegistered
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            Toggle(isOn: Binding(get: { status == .enabled || status == .requiresApproval }, set: set)) {
                VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                    Text("Mac에 로그인할 때 열기").textStyle(.item)
                    Text("켜 두면 Mac을 켤 때 Simplify가 함께 열려요.").textStyle(.small).foregroundStyle(.inkSoft)
                }
            }
            .toggleStyle(DrawnCheckboxStyle())
            if let note = failure ?? (status == .requiresApproval ? "시스템 설정 › 일반 › 로그인 항목에서 허용해 주세요." : nil) {
                Label(note, systemImage: "exclamationmark.triangle")
                    .textStyle(.small)
                    .foregroundStyle(Tokens.error)
                    // Under the label's words, past the checkbox.
                    .padding(.leading, 16 + Metrics.spaceM)
            }
        }
        .task { status = SMAppService.mainApp.status }
        // Back from 시스템 설정, where it may have been allowed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
    }

    private func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failure = nil
        } catch {
            failure = on ? "로그인 항목에 넣지 못했어요. 시스템 설정 › 일반 › 로그인 항목에서 넣어 주세요." : "로그인 항목에서 빼지 못했어요."
        }
        status = SMAppService.mainApp.status
    }
}

/// 설정 › 일반 › 메모: copies of memos in the 메모 app's Simplify folder (`NotesMirror`).
private struct NotesMirrorRow: View {
    @Bindable private var mirror = NotesMirror.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            HStack(spacing: Metrics.spaceL) {
                Toggle(isOn: $mirror.isOn) {
                    VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                        Text("Apple 메모에도 쓰기").textStyle(.item)
                        Text("메모를 저장할 때마다 메모 앱의 Simplify 폴더에 같은 내용을 써요. 메모 앱에서 고친 내용은 다음에 쓸 때 덮어써요.")
                            .textStyle(.small)
                            .foregroundStyle(.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(DrawnCheckboxStyle())
                Spacer()
                Button("지금 모두 보내기") { mirror.sendAll() }
                    .buttonStyle(DrawnButtonStyle())
                    .disabled(!mirror.isOn || mirror.status == .sending)
            }
            if mirror.isOn, let note {
                Label(note, systemImage: "exclamationmark.triangle")
                    .textStyle(.small)
                    .foregroundStyle(Tokens.error)
                    // Under the label's words, past the checkbox.
                    .padding(.leading, 16 + Metrics.spaceM)
            }
        }
    }

    private var note: String? {
        switch mirror.status {
        case .denied: "시스템 설정 › 개인정보 보호 및 보안 › 자동화에서 허락해 주세요."
        case .failed: "메모 앱에 쓰지 못했어요. 다음에 다시 써 볼게요."
        case .idle, .sending: nil
        }
    }
}

/// The square mark in front of an account: `G`, a cloud, a checklist.
private struct ProviderIcon: View {
    let kind: CalendarProviderKind

    var body: some View {
        switch kind {
        case .google: Text("G").textStyle(.item).fontWeight(.semibold)
        case .icloud: Image(systemName: "icloud").font(.system(size: 13, weight: .regular))
        case .reminders: Image(systemName: "checklist").font(.system(size: 13, weight: .regular))
        }
    }
}

/// A labelled text field in the one input look; a locked one reads as disabled.
private struct FormField<Field: View>: View {
    let label: String
    var focused: Bool
    var isEnabled = true
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceS) {
            Text(label).textStyle(.meta).foregroundStyle(.inkSoft)
            // Disabled outside the drawn field, so the field reads it and draws itself locked.
            field
                .drawnField(.box, focused: focused)
                .disabled(!isEnabled)
        }
    }
}

/// Something wrong with an account: a warning sign and an ink tag, never red.
private struct ErrorTag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: Metrics.spaceXs) {
            Image(systemName: "exclamationmark.triangle")
                .textStyle(.meta)
                .accessibilityHidden(true)
            Tag(text, color: Tokens.error, fill: .errorTint)
        }
        .foregroundStyle(Tokens.error)
    }
}

/// The sync state in the toolbar, beside 새 일정. Quiet when fine; ink with a warning sign and
/// clickable when an account needs signing in again.
struct SyncStatusView: View {
    let calendars: CalendarController
    let openSettings: () -> Void

    var body: some View {
        switch calendars.status {
        case .noAccounts:
            Button(action: openSettings) { Label("캘린더 연결", systemImage: "plus") }
                .buttonStyle(DrawnButtonStyle())
        case .syncing:
            HStack(spacing: Metrics.spaceS) {
                ProgressView().controlSize(.mini)
                Text("맞추는 중…")
            }
            .modifier(StatusText())
        case .upToDate(let last):
            Button(action: openSettings) {
                Label("계정 \(calendars.accounts.count)개 · \(Self.syncedText(last))", systemImage: "arrow.triangle.2.circlepath")
            }
            .contentShape(Rectangle())
            .buttonStyle(FocusOnlyStyle())
            .modifier(StatusText())
        case .needsReauth(let email):
            Button(action: openSettings) {
                Label("\(email) 다시 연결 필요", systemImage: "exclamationmark.triangle")
                    .underline()
            }
            .contentShape(Rectangle())
            .buttonStyle(FocusOnlyStyle())
            .modifier(StatusText(color: Tokens.error))
        case .offline(let last):
            Text("오프라인 · \(Self.syncedText(last))").modifier(StatusText())
        case .failed(let email):
            Button(action: openSettings) {
                Label("\(email) 동기화 실패", systemImage: "exclamationmark.triangle").underline()
            }
            .contentShape(Rectangle())
            .buttonStyle(FocusOnlyStyle())
            .modifier(StatusText(color: Tokens.error))
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
            content.textStyle(.meta).foregroundStyle(color)
        }
    }
}
