//
//  StorageManager.swift
//  AlphaTrack
//
//  统一存储位置管理 (PRD 数据存储可配置化)
//  支持两种模式：
//  1. 沙盒内默认位置（~/Library/Containers/<bundleID>/Data/...）
//  2. 用户自选目录（iCloud Drive / 外接硬盘 / NAS 挂载点等），
//     通过 security-scoped bookmark 持久化访问权限，App 重启后依然有效。
//

import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - 存储位置模式

enum StorageLocationMode: String, Sendable {
    /// 沙盒内默认位置（App 自动管理，用户不可见）
    case sandboxed = "sandboxed"
    /// 用户自选目录
    case custom = "custom"
}

// MARK: - 存储管理错误

enum StorageError: LocalizedError {
    case userCancelled
    case bookmarkCreationFailed
    case bookmarkResolutionFailed
    case directoryNotWritable(URL)
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "用户取消了选择"
        case .bookmarkCreationFailed:
            return "无法保存目录访问权限，请重新选择"
        case .bookmarkResolutionFailed:
            return "无法恢复目录访问权限，可能该目录已被移动或卸载"
        case .directoryNotWritable(let url):
            return "目录不可写入：\(url.path)"
        case .migrationFailed(let reason):
            return "数据迁移失败：\(reason)"
        }
    }
}

// MARK: - StorageManager

@MainActor
final class StorageManager: ObservableObject {

    static let shared = StorageManager()

    // MARK: 常量

    private let bookmarkKey = "AlphaTrack.CustomStorageBookmark"
    private let databaseFileName = "AlphaTrack.store"
    private let screenshotsFolderName = "Screenshots"

    // MARK: 可观察状态

    @Published private(set) var mode: StorageLocationMode = .sandboxed
    @Published private(set) var customLocationURL: URL?
    /// 上次操作的提示信息（供设置界面展示）
    @Published var lastMessage: String?
    /// 自定义目录是否可访问（外接硬盘被拔掉时为 false）
    @Published private(set) var isCustomLocationAccessible: Bool = true

    // MARK: 内部状态

    private var isAccessingSecurityScope = false

    private init() {
        restoreCustomLocation()
    }

    // MARK: - 核心路径

    /// 数据库文件完整路径（供 SwiftData ModelConfiguration 使用）
    var databaseURL: URL {
        switch mode {
        case .sandboxed:
            return defaultBaseURL.appendingPathComponent("default.store", isDirectory: false)
        case .custom:
            guard let base = customLocationURL else {
                return defaultBaseURL.appendingPathComponent("default.store", isDirectory: false)
            }
            return base.appendingPathComponent(databaseFileName, isDirectory: false)
        }
    }

    /// 截图附件的基准目录（Screenshots 的父目录）
    var attachmentsBaseURL: URL {
        switch mode {
        case .sandboxed:
            return defaultDocumentsURL
        case .custom:
            return customLocationURL ?? defaultDocumentsURL
        }
    }

    /// 截图目录完整路径
    var screenshotsDirectoryURL: URL {
        attachmentsBaseURL.appendingPathComponent(screenshotsFolderName, isDirectory: true)
    }

    /// 当前生效的存储根目录（用于界面展示）
    var currentRootURL: URL {
        switch mode {
        case .sandboxed:
            return defaultBaseURL
        case .custom:
            return customLocationURL ?? defaultBaseURL
        }
    }

    /// 沙盒内默认 Application Support 目录
    private var defaultBaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// 沙盒内默认 Documents 目录
    private var defaultDocumentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - 权限管理

    /// 恢复上次保存的自定义目录（App 启动时调用）
    private func restoreCustomLocation() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) else {
            mode = .sandboxed
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // bookmark 过期（目录被移动过）时，用原路径重新生成 bookmark
            if isStale {
                try saveBookmark(for: url)
            }

            // 开始访问 security-scoped resource（整个 App 生命周期保持）
            if url.startAccessingSecurityScopedResource() {
                isAccessingSecurityScope = true
            }

            customLocationURL = url
            mode = .custom
            isCustomLocationAccessible = true

            // 确保子目录存在
            ensureDirectoriesExist()
        } catch {
            // 目录不可访问（外接硬盘被拔、权限丢失）：降级到沙盒默认位置
            customLocationURL = nil
            mode = .sandboxed
            isCustomLocationAccessible = false
            lastMessage = "自定义存储位置无法访问，已临时回退到默认位置。请检查外接设备是否已连接。"
        }
    }

    /// 保存目录的 security-scoped bookmark
    private func saveBookmark(for url: URL) throws {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: bookmarkKey)
        } catch {
            throw StorageError.bookmarkCreationFailed
        }
    }

    /// 弹出系统目录选择面板，让用户选择新的存储位置
    /// - Returns: 是否成功切换（用户取消返回 false）
    @discardableResult
    func selectCustomLocation() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择存储位置"
        panel.message = "选择 AlphaTrack 存证数据与截图的保存目录（建议选 iCloud Drive 或专用同步文件夹）"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return false
        }

        do {
            try setCustomLocation(selectedURL)
            return true
        } catch {
            lastMessage = error.localizedDescription
            return false
        }
    }

    /// 设置自定义存储位置（含可写性校验与数据迁移）
    func setCustomLocation(_ url: URL) throws {
        // 1. 校验目录可写
        guard isWritable(directory: url) else {
            throw StorageError.directoryNotWritable(url)
        }

        // 2. 记录旧位置，用于迁移
        let oldRoot = currentRootURL
        let oldMode = mode

        // 3. 保存 bookmark
        try saveBookmark(for: url)

        // 4. 开始访问
        if url.startAccessingSecurityScopedResource() {
            isAccessingSecurityScope = true
        }

        customLocationURL = url
        mode = .custom
        isCustomLocationAccessible = true

        // 5. 确保目录结构存在
        ensureDirectoriesExist()

        // 6. 迁移旧数据到新位置
        if oldMode == .sandboxed || oldRoot != url {
            do {
                try migrateData(from: oldRoot, to: url)
                lastMessage = "存储位置已切换，数据已迁移。请重启 AlphaTrack 使改动生效。"
            } catch {
                lastMessage = "存储位置已切换，但数据迁移失败：\(error.localizedDescription)。请手动拷贝旧数据。"
            }
        }
    }

    /// 恢复沙盒内默认位置
    func resetToDefault() {
        let oldRoot = currentRootURL

        // 停止访问旧的 security-scoped resource
        if isAccessingSecurityScope, let old = customLocationURL {
            old.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }

        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        customLocationURL = nil
        mode = .sandboxed
        isCustomLocationAccessible = true

        // 从旧的自选目录迁移回默认位置
        do {
            try migrateData(from: oldRoot, to: defaultBaseURL)
            lastMessage = "已恢复默认存储位置，数据已迁回。请重启 AlphaTrack 使改动生效。"
        } catch {
            lastMessage = "已恢复默认位置，但数据迁移失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 数据迁移

    /// 把旧位置的数据库与截图迁移到新位置
    /// - 目标位置已存在同名数据库时跳过（不覆盖，避免数据丢失）
    private func migrateData(from sourceRoot: URL, to destRoot: URL) throws {
        let fm = FileManager.default
        guard sourceRoot.standardizedFileURL != destRoot.standardizedFileURL else { return }

        // 源目录不存在（首次设置自定义位置，且旧位置还没数据）时无需迁移
        guard fm.fileExists(atPath: sourceRoot.path) else { return }

        // 数据库名跟随目标位置：沙盒默认位置用 default.store，自定义目录用 AlphaTrack.store
        // 必须与 databaseURL 的命名规则保持一致，否则迁回后 App 读不到数据
        let srcDBName = (sourceRoot == defaultBaseURL) ? "default.store" : databaseFileName
        let dstDBName = (destRoot == defaultBaseURL) ? "default.store" : databaseFileName

        let srcDBURL = sourceRoot.appendingPathComponent(srcDBName)
        let destDBURL = destRoot.appendingPathComponent(dstDBName)

        // 目标已有数据库就不覆盖，保留现有数据
        if !fm.fileExists(atPath: destDBURL.path), fm.fileExists(atPath: srcDBURL.path) {
            do {
                // SQLite WAL 模式下，主库 + -wal + -shm 必须成套搬运，
                // 只搬主库会丢失尚未 checkpoint 的近期数据
                try fm.copyItem(at: srcDBURL, to: destDBURL)
                for suffix in ["-wal", "-shm"] {
                    let srcSide = sourceRoot.appendingPathComponent(srcDBName + suffix)
                    guard fm.fileExists(atPath: srcSide.path) else { continue }
                    try? fm.copyItem(at: srcSide, to: destRoot.appendingPathComponent(dstDBName + suffix))
                }
            } catch {
                throw StorageError.migrationFailed("数据库文件 \(srcDBName)：\(error.localizedDescription)")
            }
        }

        // 迁移截图目录
        let srcShots = sourceRoot.appendingPathComponent(screenshotsFolderName)
        let dstShots = destRoot.appendingPathComponent(screenshotsFolderName)
        if fm.fileExists(atPath: srcShots.path) {
            try? fm.createDirectory(at: dstShots, withIntermediateDirectories: true)
            let contents = (try? fm.contentsOfDirectory(
                at: srcShots,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for fileURL in contents {
                let dst = dstShots.appendingPathComponent(fileURL.lastPathComponent)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: fileURL, to: dst)
                }
            }
        }
    }

    // MARK: - 辅助

    /// 确保存储目录结构存在
    func ensureDirectoriesExist() {
        let fm = FileManager.default
        try? fm.createDirectory(at: attachmentsBaseURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: screenshotsDirectoryURL, withIntermediateDirectories: true)
    }

    /// 校验目录是否可写
    private func isWritable(directory: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: directory.path, isDirectory: &isDir)
        if !exists {
            // 目录不存在时尝试创建
            do {
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return false
            }
        } else if !isDir.boolValue {
            return false
        }
        return fm.isWritableFile(atPath: directory.path)
    }

    /// 当前存储位置的可读描述（界面展示用）
    var locationDescription: String {
        switch mode {
        case .sandboxed:
            return "App 沙盒内（默认）"
        case .custom:
            return customLocationURL?.path ?? "自定义位置"
        }
    }

    /// 在 Finder 中打开当前存储位置
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([currentRootURL])
    }
}
