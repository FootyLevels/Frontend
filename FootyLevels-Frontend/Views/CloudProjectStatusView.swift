import SwiftUI

/// A finalized private upload is not yet a model result. Media preparation and
/// authenticated reconstruction are integrated in FP-54/39, not guessed here.
struct CloudProjectStatusView: View {
    let project: CloudProject
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lock.shield").font(.system(size: 34)).foregroundStyle(SL.green)
            Text(project.title).font(SL.display(28, .bold))
            if let label = project.label { Text(label).foregroundStyle(SL.muted) }
            Text(project.statusText).font(.headline)
            Text("Your project belongs to your signed-in account. Frame selection and 3D generation will be available after media preparation is connected.")
                .font(.callout).foregroundStyle(SL.muted)
            Text("You can explore the complete 3D workspace using the included example.")
                .font(.footnote).foregroundStyle(SL.muted)
            Spacer()
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(SL.page).navigationTitle("Private project").navigationBarTitleDisplayMode(.inline)
    }
}
