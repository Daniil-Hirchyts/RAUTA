import SwiftUI

struct ProfileBasicsScreen: View {
    var body: some View { ProfileStepFlow(steps: [.about, .experience], onFinish: AppStore.shared.navigation.pop) }
}
struct TrainingPreferencesScreen: View {
    var body: some View { ProfileStepFlow(steps: [.goal, .duration], onFinish: AppStore.shared.navigation.pop) }
}
struct HealthEligibilityScreen: View {
    var body: some View { ProfileStepFlow(steps: [.health], onFinish: AppStore.shared.navigation.pop) }
}
