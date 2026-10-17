import SwiftUI

struct BrowseView: View {
    var body: some View {
        WorkBrowser(title:"健全",keyword:"$tag:健全$")
            .navigationBarTitleDisplayMode(.inline)
    }
}
