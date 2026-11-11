import SwiftUI

struct ReadmeView: View {
    @State private var contents: AttributedString?
    @State private var error: String?
    var body: some View {
        ScrollView {
            if let contents { Text(contents).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding() }
            else if let error { InlineError(message: error).padding() }
            else { ProgressView("Đang mở hướng dẫn…").padding() }
        }.navigationTitle("README")
        .task {
            do {
                guard let url = Bundle.main.url(forResource: "README", withExtension: "md") else { throw CocoaError(.fileNoSuchFile) }
                let text = try String(contentsOf: url, encoding: .utf8)
                contents = (try? AttributedString(markdown: text)) ?? AttributedString(text)
            } catch { self.error = "Không đọc được hướng dẫn." }
        }
    }
}
