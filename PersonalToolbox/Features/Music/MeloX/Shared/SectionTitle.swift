import SwiftUI

struct SectionTitle: View {
    let title: String
    var destination: MusicRoute?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline.weight(.bold))
            Spacer()
            if let destination {
                NavigationLink(value: destination) {
                    Text("查看全部")
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }
}
