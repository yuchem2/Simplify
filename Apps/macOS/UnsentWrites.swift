import SwiftUI
import SimplifyKit

/// Stands in the toolbar instead of the sync status while event changes have not reached their
/// calendar: `보내기 대기 2건`, or with a warning sign `보내지 못한 일정 1건`. A click lists them.
struct UnsentWritesButton: View {
    let calendars: CalendarController
    @State private var isOpen = false

    var body: some View {
        let failed = calendars.unsentWrites.filter(\.isFailed).count
        Button { isOpen.toggle() } label: {
            Label(failed > 0 ? "보내지 못한 일정 \(failed)건" : "보내기 대기 \(calendars.unsentWrites.count)건",
                  systemImage: failed > 0 ? "exclamationmark.triangle" : "arrow.triangle.2.circlepath")
                .fontWeight(failed > 0 ? .semibold : .regular)
        }
        // Errors stay in ink: the warning sign and the weight tell them apart, red is for holidays and delete.
        .buttonStyle(DrawnButtonStyle(.text))
        .help(calendars.isOffline ? "인터넷에 연결되면 저장돼요" : "보낼 변경 목록")
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            UnsentWritesList(calendars: calendars)
        }
    }
}

private struct UnsentWritesList: View {
    let calendars: CalendarController

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spaceXs) {
            SectionRule("보내기 대기")
                .padding(.bottom, Metrics.spaceXs)
            ForEach(calendars.unsentWrites) { write in
                row(write)
            }
            if calendars.unsentWrites.isEmpty {
                Text("모두 보냈어요.").textStyle(.body).foregroundStyle(.inkSoft)
            }
        }
        .padding(Metrics.spaceXl)
        .frame(width: 320, alignment: .leading)
        .background(.paper)
    }

    private func row(_ write: PendingWrite) -> some View {
        let source = calendars.sources[write.calendar.sourceID]
        let title = write.draft?.title ?? write.event?.title ?? ""
        return HStack(alignment: .firstTextBaseline, spacing: Metrics.spaceM) {
            Mark(source?.palette.ink, size: 10)
            VStack(alignment: .leading, spacing: Metrics.spaceXxs) {
                Text(title.isEmpty ? "(제목 없음)" : title)
                    .textStyle(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Group {
                    if write.isFailed {
                        Text("\(Image(systemName: "exclamationmark.triangle")) \(detail(write, calendarName: source?.name))")
                    } else {
                        Text(detail(write, calendarName: source?.name))
                    }
                }
                .textStyle(.small)
                .foregroundStyle(write.isFailed ? Tokens.error : Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Metrics.spaceL) {
                    if write.isFailed {
                        Button("다시 시도") { calendars.retryWrite(write.id) }
                    }
                    Button("버리기") { calendars.discardWrite(write.id) }
                }
                .buttonStyle(DrawnButtonStyle(.text))
                .padding(.top, Metrics.spaceXxs)
            }
        }
        .padding(.vertical, Metrics.spaceXs)
    }

    /// `고침 · 운동 · 연결되면 보내요`, or why the calendar refused it.
    private func detail(_ write: PendingWrite, calendarName: String?) -> String {
        let action = switch write.kind {
        case .create: "새 일정"
        case .update: "고침"
        case .delete: "지움"
        }
        let state = switch write.status {
        case .failed(let error): "보내지 못했어요: \(error.message)"
        case .waiting: calendars.isOffline ? "연결되면 보내요" : "곧 보내요"
        case .sent: "보냈어요"
        }
        return [action, calendarName, state].compactMap(\.self).joined(separator: " · ")
    }
}

extension PendingWrite {
    var isFailed: Bool {
        if case .failed = status { true } else { false }
    }
}
