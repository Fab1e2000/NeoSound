import SwiftUI
import PDFKit

struct DocumentReader: View {
    let title: String
    let url: URL
    @State private var text: String?
    @State private var document: PDFDocument?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let document {
                PDFReader(document:document)
            } else if let text {
                ScrollView {
                    Text(text).font(.body).textSelection(.enabled)
                        .frame(maxWidth:.infinity,alignment:.leading).padding()
                }
            } else if let error {
                ContentUnavailableView {
                    Label("无法打开文件",systemImage:"doc.text")
                } description: { Text(error) } actions: {
                    Button("重试") { attempt += 1 }
                }
            } else {
                ProgressView("正在载入…")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id:attempt) { await load() }
    }

    private func load() async {
        error = nil
        do {
            let (data,response) = try await URLSession.shared.data(from:url)
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw ASMRAPIError.invalidResponse
            }
            if title.lowercased().hasSuffix(".pdf") || response.mimeType == "application/pdf" {
                guard let pdf = PDFDocument(data:data) else { throw ASMRAPIError.invalidResponse }
                document = pdf
            } else {
                guard let decoded = DocumentText.decode(data) else { throw ASMRAPIError.invalidResponse }
                text = decoded
            }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

nonisolated enum DocumentText {
    static func decode(_ data: Data) -> String? {
        let bytes = Array(data.prefix(2))
        if bytes == [0xff, 0xfe] || bytes == [0xfe, 0xff] {
            return String(data:data,encoding:.utf16)
        }
        return String(data:data,encoding:.utf8) ?? String(data:data,encoding:.shiftJIS)
    }
}

private struct PDFReader: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}
