import SwiftUI

struct ContentView: View {
    @State private var viewModel = TourViewModel()
    @State private var sharePayload: SharePayload?
    @State private var selectedTab = 0
    @Bindable private var appSettings = AppSettings.shared
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                rootContent
                    .navigationTitle(viewModel.tour != nil ? "Your Tour" : "Walking Tour")
                    .toolbar { planToolbarContent }
            }
            .tabItem {
                Label("Plan", systemImage: "map.fill")
            }
            .tag(0)

            NavigationStack {
                SavedToursView(viewModel: viewModel) {
                    selectedTab = 0
                }
            }
            .tabItem {
                Label("Saved", systemImage: "bookmark.fill")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .tint(AppTheme.primary(for: effectiveColorScheme))
        .preferredColorScheme(appSettings.appearance.colorScheme)
        .task {
            viewModel.onAppear()
        }
        .onChange(of: viewModel.locationService.locationRevision) { _, _ in
            viewModel.handleLocationUpdate()
        }
        .sheet(isPresented: $viewModel.showSaveSheet) {
            SaveTourSheet(viewModel: viewModel)
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .onChange(of: viewModel.state) { _, newState in
            if newState == .success, viewModel.tour != nil {
                selectedTab = 0
            }
        }
    }

    private var effectiveColorScheme: ColorScheme {
        appSettings.appearance.colorScheme ?? systemColorScheme
    }

    @ViewBuilder
    private var rootContent: some View {
        if viewModel.tour != nil, viewModel.state == .success {
            TourActiveView(viewModel: viewModel)
        } else {
            TourSetupView(viewModel: viewModel)
        }
    }

    @ToolbarContentBuilder
    private var planToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if viewModel.tour != nil {
                Button("New Tour") {
                    viewModel.resetTour()
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if let tour = viewModel.tour {
                Button {
                    viewModel.showSaveSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }

                Button {
                    sharePayload = SharePayload(tour: tour)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
