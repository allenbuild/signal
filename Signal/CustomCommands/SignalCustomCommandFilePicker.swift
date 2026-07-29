@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

/// User-driven file selection seam. Constructing a picker never presents UI;
/// a panel is shown only in direct response to an Import or Export button.
@MainActor
public protocol SignalCustomCommandFileChoosing: AnyObject {
    func chooseImportURL() -> URL?
    func chooseExportURL(suggestedFilename: String) -> URL?
}

@MainActor
public final class SignalCustomCommandSystemFilePicker:
    SignalCustomCommandFileChoosing
{
    public init() {}

    public func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Import Fist Command Draft"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    public func chooseExportURL(
        suggestedFilename: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Saved Signal Commands"
        panel.prompt = "Export"
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = suggestedFilename
        return panel.runModal() == .OK ? panel.url : nil
    }
}
