import SwiftUI

struct ImplicitInterpolatedKeyFixture: View {
    let capacity = 60

    var body: some View {
        Text("reminder.form.capacity-confirmation.message \(capacity)")
    }
}
