//
//  SourceProfileManagerView.swift
//  AlphaTrack
//
//  PRD 4.3 / 原型 v4 5.7 来源档案管理（双栏）：
//  - 左栏 272pt：圆形头像 + 星标 + 平台与战绩副标，选中浅灰底
//  - 右栏表单：88pt 标签行 + Emoji 选块 + 胶囊开关星标置顶
//  - 同人马甲合并区（灰底说明 + 主档案/候选档案条目）
//  - 危险区（赤红描边 + 档案级联删除）
//

import SwiftUI
import SwiftData

struct SourceProfileManagerView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \SourceProfile.lastUsedAt, order: .reverse)
    private var profiles: [SourceProfile]

    @State private var selectedUUID: UUID?

    private var isDark: Bool { colorScheme == .dark }

    /// 星标优先，其次按最近使用时间
    private var sortedProfiles: [SourceProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    private var selectedProfile: SourceProfile? {
        guard let uuid = selectedUUID else { return nil }
        return profiles.first { $0.uuid == uuid }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                PageHead(
                    title: "来源档案管理",
                    subtitle: "博主资料维护 · 星标置顶 · 同人马甲一键合并",
                    dark: isDark
                )

                HStack(alignment: .top, spacing: 12) {
                    listPane
                        .frame(width: 272)

                    detailPane
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 26)
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(AT.windowBg(isDark))
        .onAppear {
            if selectedUUID == nil {
                selectedUUID = sortedProfiles.first?.uuid
            }
        }
    }

    // MARK: - 左栏列表（原型 .src-list）

    private var listPane: some View {
        VStack(spacing: 0) {
            if sortedProfiles.isEmpty {
                emptyListHint
            } else {
                ForEach(sortedProfiles) { profile in
                    profileRow(profile)
                    Rectangle().fill(AT.sep(isDark)).frame(height: 1)
                }
            }
        }
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyListHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 24))
                .foregroundColor(AT.text3(isDark))
            Text("暂无来源档案")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AT.text2(isDark))
            Text("在录入浮窗中填写发言人名称后，系统会自动建档")
                .font(.system(size: 11))
                .foregroundColor(AT.text3(isDark))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    private func profileRow(_ profile: SourceProfile) -> some View {
        let isSelected = profile.uuid == selectedUUID

        return HStack(spacing: 9) {
            ZStack {
                Circle().fill(AT.seg(isDark))
                Text(profile.avatarEmoji)
                    .font(.system(size: 14))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(profile.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(AT.text(isDark))
                        .lineLimit(1)
                    if profile.isPinned {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AT.warn)
                    }
                    if profile.isSelf {
                        TagView(text: "本人", style: .winHi, dark: isDark)
                    }
                }
                Text("\(profile.platform) · \(profile.totalPredictionsCount) 条\(profile.totalFactsCount > 0 ? " +\(profile.totalFactsCount)" : "")")
                    .font(.system(size: 10.5))
                    .foregroundColor(AT.text3(isDark))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? AT.activeBg(isDark) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selectedUUID = profile.uuid }
        .contextMenu {
            Button {
                profile.isPinned.toggle()
                profile.updatedAt = Date()
                try? modelContext.save()
            } label: {
                Label(
                    profile.isPinned ? "取消星标置顶" : "星标置顶",
                    systemImage: profile.isPinned ? "star.slash" : "star"
                )
            }
        }
    }

    // MARK: - 右栏详情

    private var detailPane: some View {
        Group {
            if let profile = selectedProfile {
                ProfileEditorPane(profile: profile, isDark: isDark, onDelete: {
                    selectedUUID = nil
                })
                .id(profile.uuid)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(AT.text3(isDark))
                    Text("从左侧选择一个来源档案进行管理")
                        .font(.system(size: 12))
                        .foregroundColor(AT.text3(isDark))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 300)
                .background(AT.cardBg(isDark))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
            }
        }
    }
}

// MARK: - 档案编辑面板

private struct ProfileEditorPane: View {

    @Bindable var profile: SourceProfile
    var isDark: Bool
    var onDelete: () -> Void = {}
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SourceProfile.name, order: .forward)
    private var allProfiles: [SourceProfile]

    @State private var newAlias: String = ""
    @State private var mergeCandidateUUID: UUID?
    @State private var showMergeConfirm: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    private static let platformOptions = [
        "Twitter/X", "微信公众号", "微博", "雪球", "B站", "小红书",
        "YouTube", "券商研报", "财联社/新闻", "社群/群聊", "播客", "自主思考"
    ]

    private static let emojiOptions = ["⚡", "🏛️", "🦁", "🧠", "📊", "🎯", "💎", "📢", "👤", "🐂", "🐻", "🔭"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                basicSection
                statsSection
                aliasSection
                mergeSection
                dangerSection
            }
            .padding(16)
        }
        .background(AT.cardBg(isDark))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AT.cardBorder(isDark), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .alert(alertTitle, isPresented: $showAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .confirmationDialog(
            "合并后，被合并档案将被删除，其存证与别名并入当前档案。此操作不可撤销。",
            isPresented: $showMergeConfirm,
            titleVisibility: .visible
        ) {
            Button("确认合并") { performMerge() }
            Button("取消", role: .cancel) { }
        }
        .alert(
            "⚠️ 谨慎删除提示",
            isPresented: $showDeleteConfirm
        ) {
            Button("确认删除（彻底清空名下所有存证）", role: .destructive) {
                performDelete()
            }
            Button("取消", role: .cancel) { }
        } message: {
            let count = profile.predictions?.count ?? 0
            Text("确认彻底删除来源档案「\(profile.name)」吗？\n\n注意：该操作将同时彻底删除该博主/来源名下的全部 \(count) 条历史存证判断记录，且删除后无法恢复！请谨慎确认。")
        }
    }

    // MARK: 基本资料（原型 .form-row：88pt 标签行）

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            formRow("名称") {
                TextField("来源名称", text: $profile.name)
                    .styledField(isDark: isDark)
            }

            formRow("头像") {
                HStack(spacing: 5) {
                    ForEach(Self.emojiOptions, id: \.self) { emoji in
                        Button {
                            profile.avatarEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 14))
                                .frame(width: 30, height: 30)
                                .background(profile.avatarEmoji == emoji ? AT.accent.opacity(0.15) : AT.control(isDark))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(profile.avatarEmoji == emoji ? AT.accent : AT.cardBorder(isDark), lineWidth: 1)
                                )
                                .cornerRadius(8)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
            }

            formRow("平台") {
                Picker("", selection: $profile.platform) {
                    ForEach(Self.platformOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            formRow("专注领域") {
                TextField("如：加密货币 / 宏观流动性", text: $profile.domainTag)
                    .styledField(isDark: isDark)
                    .frame(maxWidth: .infinity)
            }

            formRow("备注") {
                TextField("补充该来源的背景与观察", text: Binding(
                    get: { profile.notes ?? "" },
                    set: { profile.notes = $0.isEmpty ? nil : $0 }
                ))
                .styledField(isDark: isDark)
                .frame(maxWidth: .infinity)
            }

            formRow("星标置顶") {
                HStack(spacing: 8) {
                    ATSwitch(isOn: profile.isPinned) {
                        profile.isPinned.toggle()
                        profile.updatedAt = Date()
                        try? modelContext.save()
                    }
                    Text("置顶后直接排在 HUD 录入胶囊首部")
                        .font(.system(size: 11))
                        .foregroundColor(AT.text3(isDark))
                }
            }
        }
    }

    // MARK: 战绩

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                statChip("存证总数", "\(profile.totalPredictionsCount)")
                statChip("命中", "\(profile.winCount)")
                statChip("未命中", "\(profile.lossCount)")
                statChip("客观数据", "\(profile.totalFactsCount)")
                statChip("胜率", String(format: "%.1f%%", profile.winRate))
            }
            HStack(spacing: 10) {
                TagView(text: profile.mbtiCode, style: .fact, dark: isDark)
                Text(profile.mbtiTitle)
                    .font(.system(size: 12))
                    .foregroundColor(AT.text2(isDark))
                Spacer()
                Button("重算战绩与 MBTI") {
                    profile.recalculateStatsAndMBTI()
                    try? modelContext.save()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AT.accent)
                .buttonStyle(PressStyle())
            }
        }
    }

    // MARK: 别名 / 马甲

    private var aliasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("别名 / 历史马甲")

            if profile.aliasNames.isEmpty {
                Text("暂无别名。合并马甲后，被合并的来源名称会自动记录在此。")
                    .font(.system(size: 11))
                    .foregroundColor(AT.text3(isDark))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(profile.aliasNames, id: \.self) { alias in
                        HStack {
                            Text(alias)
                                .font(.system(size: 12))
                                .foregroundColor(AT.text2(isDark))
                            Spacer()
                            Button {
                                profile.aliasNames.removeAll { $0 == alias }
                                try? modelContext.save()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(AT.text3(isDark))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AT.cardBg(isDark))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("新增别名", text: $newAlias)
                    .styledField(isDark: isDark)
                    .frame(width: 220)
                    .onSubmit(addAlias)
                Button("添加") { addAlias() }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AT.accent)
                    .buttonStyle(PressStyle())
                    .disabled(newAlias.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: 合并（原型 .merge-zone）

    private var mergeSection: some View {
        let candidates = allProfiles.filter { $0.uuid != profile.uuid }

        return VStack(alignment: .leading, spacing: 8) {
            Text("同人马甲合并")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(AT.text(isDark))
            Text("合并后名下存证平滑迁移至主档案，原名称归入别名列表，并自动重算战绩与人格")
                .font(.system(size: 10.5))
                .foregroundColor(AT.text3(isDark))

            // 主档案条目
            HStack(spacing: 8) {
                Text("\(profile.avatarEmoji) \(profile.name)")
                    .font(.system(size: 11.5))
                    .foregroundColor(AT.text(isDark))
                TagView(text: profile.mbtiCode, style: .neutral, dark: isDark)
                Spacer()
                TagView(text: "主档案", style: .fact, dark: isDark)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AT.cardBg(isDark))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))

            if candidates.isEmpty {
                Text("当前没有其他档案可合并。")
                    .font(.system(size: 10.5))
                    .foregroundColor(AT.text3(isDark))
            } else {
                HStack(spacing: 8) {
                    Picker("", selection: $mergeCandidateUUID) {
                        Text("选择要合并的马甲档案…").tag(Optional<UUID>.none)
                        ForEach(candidates, id: \.uuid) { candidate in
                            Text("\(candidate.avatarEmoji) \(candidate.name)").tag(Optional(candidate.uuid))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        showMergeConfirm = true
                    } label: {
                        Text("合并")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AT.text2(isDark))
                            .padding(.horizontal, 12)
                            .frame(height: 24)
                            .background(AT.seg(isDark))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PressStyle())
                    .disabled(mergeCandidateUUID == nil)
                }
            }
        }
        .padding(13)
        .background(AT.seg(isDark))
        .cornerRadius(10)
    }

    // MARK: 删除（原型 .danger-zone）

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("档案级联删除")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(AT.bear(isDark))
            Text("将彻底删除该档案及其名下全部存证记录，不可撤销")
                .font(.system(size: 10.5))
                .foregroundColor(AT.text2(isDark))

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Text("删除档案与全部存证")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AT.bear(isDark))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AT.bear(isDark).opacity(0.42), lineWidth: 1)
                    )
                    .cornerRadius(8)
            }
            .buttonStyle(PressStyle())
        }
        .padding(13)
        .background(AT.bear(isDark).opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AT.bear(isDark).opacity(0.34), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    // MARK: 行为

    private func addAlias() {
        let clean = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !profile.aliasNames.contains(clean) else {
            newAlias = ""
            return
        }
        profile.aliasNames.append(clean)
        profile.updatedAt = Date()
        newAlias = ""
        try? modelContext.save()
    }

    private func performMerge() {
        guard let uuid = mergeCandidateUUID,
              let other = allProfiles.first(where: { $0.uuid == uuid }) else { return }

        let otherName = other.name
        profile.absorb(other)
        modelContext.delete(other)
        mergeCandidateUUID = nil

        do {
            try modelContext.save()
            notify(title: "合并完成", message: "「\(otherName)」的存证与别名已并入「\(profile.name)」。")
        } catch {
            notify(title: "合并失败", message: error.localizedDescription)
        }
    }

    private func performDelete() {
        let name = profile.name
        if let list = profile.predictions {
            for entry in list {
                modelContext.delete(entry)
            }
        }
        let descriptor = FetchDescriptor<PredictionEntry>(
            predicate: #Predicate { $0.authorName == name }
        )
        if let matches = try? modelContext.fetch(descriptor) {
            for entry in matches {
                modelContext.delete(entry)
            }
        }
        modelContext.delete(profile)
        onDelete()
        do {
            try modelContext.save()
            notify(title: "删除成功", message: "已彻底删除博主「\(name)」及其所有历史存证记录。")
        } catch {
            notify(title: "删除失败", message: error.localizedDescription)
        }
    }

    private func notify(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    // MARK: 组件

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(AT.text2(isDark))
    }

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundColor(AT.text2(isDark))
                .frame(width: 88, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundColor(AT.text3(isDark))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(AT.text(isDark))
        }
        .frame(minWidth: 64, alignment: .leading)
        .padding(8)
        .background(AT.seg(isDark))
        .cornerRadius(6)
    }
}

// MARK: - 输入框统一样式（原型 .input）

extension View {
    @ViewBuilder
    func styledField(isDark: Bool) -> some View {
        if #available(macOS 13.0, *) {
            self.textFieldStyle(.plain)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(AT.control(isDark))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(AT.cardBorder(isDark), lineWidth: 1))
        } else {
            self.textFieldStyle(.roundedBorder)
        }
    }
}

#Preview {
    SourceProfileManagerView()
        .modelContainer(for: [PredictionEntry.self, SourceProfile.self], inMemory: true)
}
