import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Helper Model for Sheet
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TimeBlock.startTime, order: .reverse) private var allBlocks: [TimeBlock]
    
    // State for Export/Share
    // We use a single 'item' state to drive the sheet. This prevents "blank sheet" errors.
    @State private var shareableFile: ShareableFile?
    @State private var exportOptions = CSVExporter.ExportOptions()
    
    // State for Archive Logic
    @State private var showingFileImporter = false
    @State private var showingPruneConfirmation = false
    @State private var pruneDate: Date = Date()
    @State private var restoreCount: Int? = nil
    @State private var showingRestoreSuccess = false
    
    // Archive Date Selection
    @State private var selectedArchivePeriod = ArchivePeriod.sixMonths
    
    enum ArchivePeriod: Int, CaseIterable {
        case oneMonth = 1
        case threeMonths = 3
        case sixMonths = 6
        case oneYear = 12
        
        var label: String {
            switch self {
            case .oneMonth: return "Older than 1 Month"
            case .threeMonths: return "Older than 3 Months"
            case .sixMonths: return "Older than 6 Months"
            case .oneYear: return "Older than 1 Year"
            }
        }
        
        var date: Date {
            Calendar.current.date(byAdding: .month, value: -self.rawValue, to: Date())!
        }
    }
    
    var body: some View {
        Form {
            // MARK: - CSV Export Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Analysis Export (CSV)", systemImage: "tablecells")
                        .font(.headline)
                    Text("Export your data to CSV for analysis in Excel, Numbers, or Python. This does not remove data from the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                DisclosureGroup("Export Options") {
                    Toggle("Include Remarks", isOn: $exportOptions.includeRemarks)
                    Toggle("Include Durations", isOn: $exportOptions.includeDuration)
                    Toggle("Include Exact Times", isOn: $exportOptions.includeStartTime)
                }
                
                Button {
                    generateCSV()
                } label: {
                    Text("Generate CSV File")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("Analysis")
            }
            
            // MARK: - Archive Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Data Archive (JSON)", systemImage: "archivebox")
                        .font(.headline)
                    Text("Create a full backup of your data. You can restore this later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                Button {
                    generateFullArchive()
                } label: {
                    Text("Backup All Data")
                }
                
                Button {
                    showingFileImporter = true
                } label: {
                    Text("Restore from Backup")
                }
            } header: {
                Text("Backup & Restore")
            }
            
            // MARK: - Storage Management
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Free Up Space", systemImage: "trash")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text("Archive old records to a file and delete them from the app to improve performance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                
                Picker("Archive Range", selection: $selectedArchivePeriod) {
                    ForEach(ArchivePeriod.allCases, id: \.self) { period in
                        Text(period.label).tag(period)
                    }
                }
                
                Button(role: .destructive) {
                    preparePrune()
                } label: {
                    Text("Archive & Delete Old Records")
                }
            } header: {
                Text("Storage Management")
            }
        }
        .navigationTitle("Data Management")
        
        // MARK: - Sheets & Alerts
        
        // 1. The Share Sheet (Driven by the Item, ensuring data exists before presentation)
        .sheet(item: $shareableFile) { file in
            FileShareSheet(activityItems: [file.url])
                .presentationDetents([.medium, .large])
        }
        
        // 2. File Importer
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json]) { result in
            handleImport(result: result)
        }
        
        // 3. Prune Confirmation
        .alert("Archive Created", isPresented: $showingPruneConfirmation) {
            Button("Delete from App", role: .destructive) {
                finalizePrune()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The archive file has been generated. Do you want to DELETE these records from the app now? This cannot be undone (unless you restore the backup).")
        }
        
        // 4. Restore Success
        .alert("Restore Complete", isPresented: $showingRestoreSuccess) {
            Button("OK") {}
        } message: {
            if let count = restoreCount {
                Text("Successfully restored \(count) records.")
            }
        }
    }
    
    // MARK: - Actions
    
    private func generateCSV() {
        let exporter = CSVExporter()
        // Ensure export options are applied
        let csvString = exporter.exportTimeBlocks(allBlocks, options: exportOptions)
        let filename = exporter.generateFilename()
        
        do {
            let url = try exporter.saveToFile(csv: csvString, filename: filename)
            // Trigger the sheet by setting the item
            shareableFile = ShareableFile(url: url)
        } catch {
            print("CSV Generation Error: \(error)")
        }
    }
    
    private func generateFullArchive() {
        let manager = DataArchiveManager(modelContext: modelContext)
        do {
            let url = try manager.createArchive(olderThan: nil) // All data
            // Trigger the sheet by setting the item
            shareableFile = ShareableFile(url: url)
        } catch {
            print("Archive Error: \(error)")
        }
    }
    
    private func preparePrune() {
        let manager = DataArchiveManager(modelContext: modelContext)
        pruneDate = selectedArchivePeriod.date
        do {
            // 1. Create the archive first
            let url = try manager.createArchive(olderThan: pruneDate)
            
            // 2. Show share sheet to save it
            shareableFile = ShareableFile(url: url)
            
            // 3. Queue the confirmation alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                 showingPruneConfirmation = true
            }
            
        } catch {
            print("Prune Error: \(error)")
        }
    }
    
    private func finalizePrune() {
        let manager = DataArchiveManager(modelContext: modelContext)
        do {
            let deletedCount = try manager.deleteRecords(olderThan: pruneDate)
            print("Deleted \(deletedCount) records")
        } catch {
            print("Delete Error: \(error)")
        }
    }
    
    private func handleImport(result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let manager = DataArchiveManager(modelContext: modelContext)
            do {
                restoreCount = try manager.restoreFromArchive(url: url)
                showingRestoreSuccess = true
            } catch {
                print("Restore Error: \(error)")
            }
        case .failure(let error):
            print("Import Error: \(error)")
        }
    }
}

// MARK: - Local Helper: File Share Sheet
struct FileShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // iPad Popover Fix (Required for iPad to not crash)
        // This anchors the popover to the center of the screen if a specific button isn't provided
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView() // Temporary source
            popover.permittedArrowDirections = []
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
