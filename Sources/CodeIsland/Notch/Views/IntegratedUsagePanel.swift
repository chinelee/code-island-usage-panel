import SwiftUI

struct IntegratedUsagePanel: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var rateLimitStore: RateLimitStore
    @ObservedObject var openTokenStore: OpenTokenUsageStore
    @ObservedObject var sessionTokenStore: SessionTokenUsageStore
    @ObservedObject var settingsStore: SettingsStore
    let onOpenSettings: () -> Void

    @Environment(\.notchTheme) private var theme

    private let panelPadding: CGFloat = 22
    private let chartHeight: CGFloat = 118

    private var codexUsage: ProviderUsage { rateLimitStore.snapshot(for: .codex) }

    private var activeSessions: [Session] {
        sessionStore.activeSessions.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            codexSection
            separator
            tokenSection
            separator
            sessionSection
            Spacer(minLength: 6)
            footer
        }
        .padding(.horizontal, panelPadding)
        .padding(.top, 46)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await refreshData() }
    }

    private var codexSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                ProviderIcon(provider: .codex, size: 20)
                Text("Codex")
                    .font(theme.font(size: 16, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                Button(action: refreshAll) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新")
                    }
                    .font(theme.font(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(codexUsage.accountEmail ?? "Codex 账号")
                    .font(theme.font(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.78))
                    .lineLimit(1)
                if let plan = codexUsage.plan {
                    Text(plan.uppercased())
                        .font(theme.font(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.48))
                }
                Spacer()
                Text("当前账户")
                    .font(theme.font(size: 9))
                    .foregroundColor(.white.opacity(0.38))
            }

            if let weekly = codexUsage.sevenDay {
                HStack(spacing: 10) {
                    Circle()
                        .fill(quotaColor(weekly.usedPercentage))
                        .shadow(color: quotaColor(weekly.usedPercentage).opacity(0.55), radius: 4)
                        .frame(width: 8, height: 8)
                    Text("本周")
                        .font(theme.font(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 42, alignment: .leading)
                    quotaProgress(weekly.usedPercentage)
                    Text("\(weekly.usedPercentage)%")
                        .font(theme.font(size: 13, weight: .heavy))
                        .foregroundColor(quotaColor(weekly.usedPercentage))
                        .frame(width: 40, alignment: .trailing)
                    Text(weekly.timeRemaining)
                        .font(theme.font(size: 10))
                        .foregroundColor(.white.opacity(0.46))
                        .frame(width: 60, alignment: .trailing)
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(.white.opacity(0.22)).frame(width: 8, height: 8)
                    Text(codexUsage.error ?? "暂未读取到额度")
                        .font(theme.font(size: 10))
                        .foregroundColor(.white.opacity(0.38))
                    Spacer()
                }
            }

            HStack(spacing: 14) {
                if let weekly = codexUsage.sevenDay {
                    detailLabel(title: "剩余", value: "\(max(0, 100 - weekly.usedPercentage))%")
                    detailLabel(title: "重置", value: resetTime(weekly.resetsAt))
                }
                if let balance = codexUsage.creditsBalance {
                    detailLabel(title: "Credits", value: balance)
                }
                if let suffix = codexUsage.accountIDSuffix, !suffix.isEmpty {
                    detailLabel(title: "账户", value: "•••\(suffix)")
                }
                Spacer()
            }

            if !codexUsage.availableModels.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.green.opacity(0.75))
                    Text("可用模型")
                        .foregroundColor(.white.opacity(0.3))
                    Text(codexUsage.availableModels.joined(separator: " · "))
                        .foregroundColor(.white.opacity(0.58))
                    Spacer()
                }
                .font(theme.font(size: 9, weight: .medium))
            }
        }
        .padding(.bottom, 16)
    }

    private var tokenSection: some View {
        VStack(spacing: 11) {
            HStack {
                Text("Token 消耗")
                    .font(theme.font(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                Spacer()
                Text("1hr \(formatTokens(openTokenStore.latestHourTokens)) · 24h \(formatTokens(openTokenStore.totalTokens)) tok")
                    .font(theme.font(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.48))
            }

            toolSummary
            tokenTypeSummary

            let modelUsage = Array(openTokenStore.modelUsage24Hours.prefix(6))
            if !modelUsage.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(modelUsage) { usage in
                        modelUsageRow(usage)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 5) {
                let maximum = max(openTokenStore.hourBuckets.map(\.total).max() ?? 0, 1)
                ForEach(openTokenStore.hourBuckets) { bucket in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        if bucket.total == 0 {
                            Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(bucket.modelTokens.sorted(by: { $0.key < $1.key }), id: \.key) { model, value in
                                    Rectangle()
                                        .fill(modelColor(model))
                                        .frame(height: segmentHeight(value, maximum: maximum))
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: chartHeight)

            HStack {
                Text(axisTime(hoursAgo: 24))
                Spacer()
                Text(axisTime(hoursAgo: 16))
                Spacer()
                Text(axisTime(hoursAgo: 8))
                Spacer()
                Text("现在")
            }
            .font(theme.font(size: 9))
            .foregroundColor(.white.opacity(0.38))

            if let error = openTokenStore.errorMessage {
                Text(error)
                    .font(theme.font(size: 9))
                    .foregroundColor(.orange.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 16)
    }

    private var toolSummary: some View {
        HStack(spacing: 8) {
            ForEach(openTokenStore.toolUsage24Hours) { usage in
                HStack(spacing: 6) {
                    ProviderIcon(provider: provider(forTool: usage.tool), size: 13)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayTool(usage.tool))
                            .font(theme.font(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.46))
                        Text(formatTokens(usage.tokens))
                            .font(theme.font(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Spacer(minLength: 0)
                    Text(toolShare(usage.tokens))
                        .font(theme.font(size: 9))
                        .foregroundColor(toolColor(usage.tool).opacity(0.8))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var tokenTypeSummary: some View {
        let breakdown = openTokenStore.tokenBreakdown24Hours
        return HStack(spacing: 0) {
            tokenTypeCell("输入", breakdown.input)
            tokenTypeCell("输出", breakdown.output)
            tokenTypeCell("缓存读", breakdown.cacheRead)
            tokenTypeCell("缓存写", breakdown.cacheWrite)
        }
        .padding(.vertical, 2)
    }

    private func tokenTypeCell(_ title: String, _ value: Int64) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(theme.font(size: 8))
                .foregroundColor(.white.opacity(0.32))
            Text(formatTokens(value))
                .font(theme.font(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
    }

    private var sessionSection: some View {
        VStack(spacing: 9) {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("活跃会话")
                        .font(theme.font(size: 13, weight: .heavy))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(activeSessions.count) 个运行中")
                    .font(theme.font(size: 10))
                    .foregroundColor(.white.opacity(0.48))
            }

            if activeSessions.isEmpty {
                HStack(spacing: 8) {
                    Circle().fill(.white.opacity(0.18)).frame(width: 7, height: 7)
                    Text("当前没有活跃会话")
                        .font(theme.font(size: 11))
                        .foregroundColor(.white.opacity(0.36))
                    Spacer()
                }
            } else {
                ForEach(activeSessions.prefix(5), id: \.id) { session in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(statusColor(session.status))
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(session.displayName)
                                    .font(theme.font(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.78))
                                    .lineLimit(1)
                                Text("· \(displayProvider(session.source))")
                                    .font(theme.font(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                                if let model = session.shortModelName {
                                    Text("· \(model)")
                                        .font(theme.font(size: 9))
                                        .foregroundColor(.white.opacity(0.3))
                                        .lineLimit(1)
                                }
                            }
                            HStack(spacing: 8) {
                                if let tool = session.currentTool, !tool.isEmpty {
                                    Text("工具 \(shortToolName(tool))")
                                }
                                if let effort = session.effortLevel, !effort.isEmpty {
                                    Text("推理 \(effort)")
                                }
                            }
                            .font(theme.font(size: 8))
                            .foregroundColor(.white.opacity(0.28))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(sessionTokenStore.tokens(for: session.id).map(formatTokens) ?? "暂无 Token")
                                .font(theme.font(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.48))
                            HStack(spacing: 6) {
                                Text(session.durationText)
                                    .foregroundColor(.white.opacity(0.34))
                                Text(session.status.displayText)
                                    .foregroundColor(statusColor(session.status).opacity(0.88))
                            }
                            .font(theme.font(size: 9, weight: .semibold))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 15)
    }

    private var footer: some View {
        HStack {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Text("OpenToken 本机聚合")
                .font(theme.font(size: 9))
                .foregroundColor(.white.opacity(0.26))
            if let refreshedAt = openTokenStore.lastRefreshedAt {
                Text("· 更新 \(refreshClock(refreshedAt))")
                    .font(theme.font(size: 9))
                    .foregroundColor(.white.opacity(0.26))
            }
            Spacer()
            Button(action: { settingsStore.soundEnabled.toggle() }) {
                Image(systemName: settingsStore.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.34))
            }
            .buttonStyle(.plain)
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var separator: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
    }

    private func refreshAll() {
        Task {
            await refreshData()
        }
    }

    private func refreshData() async {
        async let limits: Void = rateLimitStore.refresh()
        async let tokens: Void = openTokenStore.refresh()
        async let sessions: Void = sessionTokenStore.refresh(sessions: activeSessions)
        _ = await (limits, tokens, sessions)
    }

    private func detailLabel(title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundColor(.white.opacity(0.3))
            Text(value).foregroundColor(.white.opacity(0.56))
        }
        .font(theme.font(size: 9, weight: .medium))
    }

    private func quotaProgress(_ percent: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.13))
                Capsule()
                    .fill(quotaColor(percent))
                    .frame(width: proxy.size.width * min(CGFloat(percent) / 100, 1))
            }
        }
        .frame(height: 7)
    }

    private func modelUsageRow(_ usage: OpenTokenModelUsage) -> some View {
        HStack(spacing: 6) {
            Circle().fill(modelColor(usage.model)).frame(width: 7, height: 7)
            Text(usage.model)
                .font(theme.font(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(formatTokens(usage.tokens))
                .font(theme.font(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.54))
        }
    }

    private func segmentHeight(_ value: Int64, maximum: Int64) -> CGFloat {
        max(CGFloat(value) / CGFloat(maximum) * chartHeight, value > 0 ? 2 : 0)
    }

    private func modelColor(_ model: String) -> Color {
        let lower = model.lowercased()
        if lower.contains("astra") { return Color(red: 0.18, green: 0.80, blue: 0.72) }
        if lower.contains("sol") { return Color(red: 0.69, green: 0.42, blue: 0.95) }
        if lower.contains("terra") { return Color(red: 0.30, green: 0.61, blue: 0.95) }
        if lower.contains("opus") || lower.contains("claude") { return Color(red: 0.96, green: 0.53, blue: 0.24) }
        if lower.contains("glm") || lower.contains("buddy") { return Color(red: 0.94, green: 0.38, blue: 0.68) }
        return Color(red: 0.42, green: 0.78, blue: 0.46)
    }

    private func quotaColor(_ percent: Int) -> Color {
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        if percent >= 50 { return .yellow }
        return .green
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .waitingPermission, .error: return .red
        case .thinking, .toolUse: return .green
        case .idle: return .cyan
        case .completed: return .gray
        }
    }

    private func displayProvider(_ source: String) -> String {
        switch source {
        case "codebuddy": return "WorkBuddy"
        case "claude", "claude-code": return "Claude"
        default: return AIProvider.from(source).displayName
        }
    }

    private func axisTime(hoursAgo: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date().addingTimeInterval(TimeInterval(-hoursAgo * 3600)))
    }

    private func resetTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "E HH:mm"
        return formatter.string(from: date)
    }

    private func refreshClock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func provider(forTool tool: String) -> AIProvider {
        switch tool {
        case "claude": return .claude
        case "workbuddy": return .codebuddy
        default: return .codex
        }
    }

    private func displayTool(_ tool: String) -> String {
        switch tool {
        case "claude": return "Claude"
        case "workbuddy": return "WorkBuddy"
        default: return "Codex"
        }
    }

    private func toolColor(_ tool: String) -> Color {
        switch tool {
        case "claude": return Color(red: 0.96, green: 0.53, blue: 0.24)
        case "workbuddy": return Color(red: 0.94, green: 0.38, blue: 0.68)
        default: return Color(red: 0.18, green: 0.80, blue: 0.72)
        }
    }

    private func toolShare(_ tokens: Int64) -> String {
        guard openTokenStore.totalTokens > 0 else { return "0%" }
        let percent = Int((Double(tokens) / Double(openTokenStore.totalTokens) * 100).rounded())
        return "\(percent)%"
    }

    private func shortToolName(_ value: String) -> String {
        let tail = value.split(separator: "_").last.map(String.init) ?? value
        return tail.count > 18 ? String(tail.prefix(17)) + "…" : tail
    }

    private func formatTokens(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fk", Double(value) / 1_000) }
        return "\(value)"
    }
}
