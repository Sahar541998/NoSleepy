import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        header
                        monitoringCard
                        healthPermissionCard
                        liveActivityPermissionCard
                        howItWorksCard
                        testCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 48)
                }
            }
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await viewModel.onAppear() }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            Task { await viewModel.sceneDidBecomeActive() }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("NoSleepy")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Detect drowsiness with Apple Watch sleep insights and wake-up alerts.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.top, 72)
    }

    private var monitoringCard: some View {
        glassCard(
            backgroundTint: viewModel.isSleepAlertActive ? Color.red.opacity(0.2) : Color.white.opacity(0.16),
            borderTint: viewModel.isSleepAlertActive ? Color.red.opacity(0.45) : Color.white.opacity(0.25)
        ) {
            VStack(spacing: 20) {
                Text(viewModel.primaryEmoji)
                    .font(.system(size: 64))

                VStack(spacing: 8) {
                    Text(viewModel.monitoringHeadline)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)

                    Text(viewModel.monitoringStatusMessage)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(maxWidth: .infinity)
                }

                Toggle(isOn: Binding(
                    get: { viewModel.isMonitoringEnabled },
                    set: { newValue in
                        Task { await viewModel.handleMonitoringToggle(newValue) }
                    }
                )) {
                    Text(viewModel.isMonitoringEnabled ? "Monitoring enabled" : "Monitoring paused")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .toggleStyle(SwitchToggleStyle(tint: viewModel.isSleepAlertActive ? .red : .teal))

                if viewModel.isMonitoringEnabled {
                    Toggle(isOn: Binding(
                        get: { viewModel.isSoundEnabled },
                        set: { newValue in
                            viewModel.updateSoundPreference(newValue)
                        }
                    )) {
                        Label("Sound alerts", systemImage: viewModel.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: viewModel.isSoundEnabled ? .teal : .gray))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isMonitoringEnabled)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isSleepAlertActive)
    }

    private var healthPermissionCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "bed.double.fill")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Health Access")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    permissionBadge(for: viewModel.healthPermissionStatus)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.healthPermissionStatus)
    }

    private var liveActivityPermissionCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                    Text("Live Activities")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    permissionBadge(for: viewModel.liveActivityPermissionStatus)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.liveActivityPermissionStatus)
    }

    private func permissionBadge(for status: PermissionStatus) -> some View {
        Label(status.title, systemImage: status.systemImageName)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(status.tint.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
    }

    private var howItWorksCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("How NoSleepy Works", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 16) {
                    infoRow(
                        title: "Wear your Apple Watch",
                        detail: "We monitor sleep stages from your watch to spot early drowsiness.",
                        icon: "applewatch.watchface"
                    )
                    infoRow(
                        title: "Grant Health sleep access",
                        detail: "Sleep analysis data lets us know when you start nodding off.",
                        icon: "bed.double.fill"
                    )
                    infoRow(
                        title: "Enable Live Activities",
                        detail: "Keep the app running so alerts reach the Dynamic Island instantly.",
                        icon: "waveform.path.ecg.rectangle"
                    )
                    infoRow(
                        title: "Background checks",
                        detail: "NoSleepy checks every 5 minutes to see if you're nodding off.",
                        icon: "clock.arrow.2.circlepath"
                    )
                    infoRow(
                        title: "Stay awake",
                        detail: "If sleep is detected we vibrate your phone and show urgent alerts.",
                        icon: "bell.badge.waveform"
                    )
                }
            }
        }
    }

    private var testCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 18) {
                Label("Run A Test", systemImage: "flag.checkered")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text(viewModel.testStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))

                if viewModel.isRunningTest {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }

                Button {
                    viewModel.runSleepDetectionTest()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: viewModel.isRunningTest ? "hourglass" : "play.fill")
                        Text(viewModel.isRunningTest ? "Running Test…" : "Run Sleep Alert Demo")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.white.opacity(0.22), lineWidth: 1)
                        )
                )
                .foregroundStyle(.white)
                .disabled(viewModel.isRunningTest || !viewModel.isMonitoringEnabled)
                .opacity((viewModel.isRunningTest || !viewModel.isMonitoringEnabled) ? 0.65 : 1)
            }
        }
    }

    private func infoRow(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 28, height: 28)
                .foregroundStyle(.white)
                .background(
                    Circle()
                        .fill(.white.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.14, blue: 0.25),
                    Color(red: 0.05, green: 0.14, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.purple.opacity(0.35))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(x: -120, y: -260)

            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 320, height: 320)
                .blur(radius: 120)
                .offset(x: 160, y: -180)

            Circle()
                .fill(Color.teal.opacity(0.35))
                .frame(width: 360, height: 360)
                .blur(radius: 140)
                .offset(x: -160, y: 180)
        }
    }

    private func glassCard<Content: View>(
        backgroundTint: Color = Color.white.opacity(0.14),
        borderTint: Color = Color.white.opacity(0.3),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(backgroundTint)

                
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(borderTint, lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 22, x: 0, y: 18)
    }
}

#Preview {
    ContentView()
}
