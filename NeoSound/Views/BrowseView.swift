import SwiftUI

struct BrowseView: View {
    var body: some View {
        WorkBrowser(title:"浏览",keyword:"$tag:健全$")
            .navigationBarTitleDisplayMode(.large)
    }
}
