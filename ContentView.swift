//
//  ContentView.swift
//  AlphaTrack
//
//  Created by AlphaTrack on 2026/9/5.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    @ObservedObject private var router = DeepLinkRouter.shared

    /// 深链 / 列表点击所打开的复盘详情条目
    @State private var detailEntry: PredictionEntry?

    var body: some View {
        DashboardView()
        // 捕获 openWindow 动作，供菜单栏微面板等 AppKit 侧打开窗口（见 WindowRouter）
        .installWindowRouter()
        .onAppear {
            HUDPanelController.shared.registerGlobalShortcuts()
        }
        // PRD 4.4：接收 alphatrack:// 深链并落地到复盘详情
        .onOpenURL { url in
            guard router.handle(url) else { return }
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            resolveDeepLinkTarget()
        }
        .sheet(item: $detailEntry) { entry in
            EntryDetailView(entry: entry)
        }
    }

    // MARK: - 深链落地

    private func resolveDeepLinkTarget() {
        if router.consumeQuickEntryRequest() {
            HUDPanelController.shared.show()
        }
        guard let uuid = router.consumePendingEntryUUID() else { return }

        var descriptor = FetchDescriptor<PredictionEntry>(
            predicate: #Predicate { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        if let entry = try? modelContext.fetch(descriptor).first {
            detailEntry = entry
        } else {
            NSSound.beep()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PredictionEntry.self, SourceProfile.self], inMemory: true)
}
