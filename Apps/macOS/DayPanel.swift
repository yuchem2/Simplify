import SwiftUI
import SimplifyKit

/// The moulded panel beside the month: the chosen day, its week, or its month.
/// Sections are empty for now; events (stage 2), memos (stage 5) and ToDos (stage 6) fill them.
struct DayPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        let period = model.panelPeriod
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                SegmentedTabs([(PeriodScope.day, "하루"), (.week, "한 주"), (.month, "한 달")], selection: $model.panelScope, fillsWidth: true)
                HStack(alignment: .firstTextBaseline) {
                    Text(period.title)
                        .font(.display(22))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if period.scope == .week {
                        Text(period.rangeText).font(.system(size: 11, weight: .medium)).foregroundStyle(.inkSoft)
                    } else if period.scope == .day && period.contains(model.today) {
                        Text("오늘")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.7)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(sections(for: period.scope), id: \.title) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionRule(section.title) {
                                if let action = section.action {
                                    Button(action) {}.buttonStyle(DrawnButtonStyle(.text)).disabled(true)
                                }
                            }
                            if section.isMemo {
                                Text(section.empty)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.inkFaint)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                                    .overlay(Rectangle().strokeBorder(.ink, lineWidth: Metrics.line))
                            } else {
                                Text(section.empty)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.inkSoft)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .mouldedFrame()
    }

    private struct Section {
        var title: String
        var action: String?
        var empty: String
        var isMemo = false
    }

    private func sections(for scope: PeriodScope) -> [Section] {
        switch scope {
        case .day:
            [Section(title: "일정", action: "추가", empty: "이날은 일정이 없어요."),
             Section(title: "할 일", action: "가져오기", empty: "할 일이 없어요."),
             Section(title: "메모", empty: "이날의 메모를 적어 보세요.", isMemo: true)]
        case .week:
            [Section(title: "이번 주 일정", empty: "이번 주는 일정이 없어요."),
             Section(title: "이번 주 할 일", action: "가져오기", empty: "할 일이 없어요."),
             Section(title: "주간 메모", empty: "이번 주 메모를 적어 보세요.", isMemo: true)]
        case .month:
            [Section(title: "이번 달 할 일", action: "가져오기", empty: "할 일이 없어요."),
             Section(title: "월간 메모", empty: "이번 달 메모를 적어 보세요.", isMemo: true)]
        }
    }
}
